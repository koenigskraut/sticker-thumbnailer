const std = @import("std");
const c = @cImport({
    @cInclude("libavutil/imgutils.h");
    @cInclude("libavcodec/avcodec.h");
    @cInclude("libavformat/avformat.h");
    @cInclude("libavformat/avio.h");
    @cInclude("libavutil/timestamp.h");
    @cInclude("libavutil/opt.h");
    @cInclude("libavutil/file.h");
    @cInclude("libswscale/swscale.h");
});

const Image = @import("common.zig").Image;

fn readFn(data_arg: ?*anyopaque, buf: [*c]u8, len: c_int) callconv(.C) c_int {
    const data = @as(*[]const u8, @ptrCast(@alignCast(data_arg.?))).*;
    const read = @min(data.len, @as(usize, @intCast(len)));
    // std.debug.print("readFn called with {*} (len {})\n", .{ data_arg.?, data.len });
    @memcpy(buf[0..read], data[0..read]);
    return @intCast(read);
}

// fn writeFn(data: ?*anyopaque, buf: [*c]u8, len: c_int) callconv(.C) c_int {

// }

fn seekFn(_: ?*anyopaque, _: i64, _: c_int) callconv(.C) i64 {
    // std.debug.print("seekFn called\n", .{});
    return 0;
}

pub fn readWebm(allocator: std.mem.Allocator, data_arg: []const u8, max_dimension: usize) !Image {
    var data = data_arg;
    c.av_log_set_level(c.AV_LOG_WARNING);

    const buf_len = 8192;
    const avio_buffer: [*c]u8 = @ptrCast(c.av_malloc(buf_len) orelse return error.OutOfMemory);

    const avio_context: ?*c.AVIOContext = c.avio_alloc_context(
        @ptrCast(avio_buffer),
        buf_len,
        0,
        @ptrCast(&data),
        &readFn,
        null,
        &seekFn,
    );

    var input_fc: ?*c.AVFormatContext = c.avformat_alloc_context();
    defer c.avformat_close_input(&input_fc);

    input_fc.?.pb = avio_context;
    input_fc.?.flags |= c.AVFMT_FLAG_CUSTOM_IO;
    if (c.avformat_open_input(&input_fc, "video", null, null) != 0) return error.OpenInputError;
    defer {
        c.av_free(input_fc.?.pb.?.*.buffer);
        c.avio_context_free(&input_fc.?.pb);
    }

    // if (true) return std.mem.zeroes(Image);

    const input_codec: *const c.AVCodec = c.avcodec_find_decoder_by_name("libvpx-vp9").?;
    var input_cc: ?*c.AVCodecContext = c.avcodec_alloc_context3(input_codec);
    defer c.avcodec_free_context(&input_cc);
    if (c.avcodec_open2(input_cc, input_codec, null) != 0) return error.CodecOpenError;

    var pFrame: ?*c.AVFrame = c.av_frame_alloc();
    defer c.av_frame_free(&pFrame);
    var packet: c.AVPacket = undefined;
    defer c.av_packet_unref(&packet);

    if (c.av_read_frame(input_fc, &packet) != 0) return error.ReadFrameError;
    if (c.avcodec_send_packet(input_cc, &packet) != 0) return error.PacketSendingError;
    var ret = c.avcodec_receive_frame(input_cc, pFrame);
    if (ret == -11) {
        while (true) {
            if (c.avcodec_send_packet(input_cc, &packet) != 0) return error.PacketSendingError;
            ret = c.avcodec_receive_frame(input_cc, pFrame);
            if (ret == 0) break;
        }
    }

    if (ret != 0) {
        var buf = [_]u8{0} ** c.AV_ERROR_MAX_STRING_SIZE;
        // std.debug.print("{} {s}\n", .{ ret, c.av_make_error_string(&buf[0], buf.len, ret) });
        buf = std.mem.zeroes(@TypeOf(buf));
        _ = c.av_strerror(ret, &buf, buf.len);
        // std.debug.print("{s}\n", .{buf[0..]});
        return error.PacketReceivingError;
    }
    // std.debug.print("!!! {}\n", .{input_cc.?.pix_fmt});

    const width_f: f64 = @floatFromInt(input_cc.?.width);
    const height_f: f64 = @floatFromInt(input_cc.?.height);
    const scale = @as(f64, @floatFromInt(max_dimension)) / @max(width_f, height_f);

    const width: u32 = @intFromFloat(@round(width_f * scale));
    const height: u32 = @intFromFloat(@round(height_f * scale));

    const png_codec: *const c.AVCodec = c.avcodec_find_encoder(c.AV_CODEC_ID_PNG).?;
    var png_cc: *c.AVCodecContext = c.avcodec_alloc_context3(png_codec).?;
    defer c.avcodec_free_context(@ptrCast(&png_cc));
    png_cc.width = @intCast(width);
    png_cc.height = @intCast(height);
    png_cc.pix_fmt = c.AV_PIX_FMT_RGBA;
    png_cc.time_base = c.AVRational{ .num = 1, .den = 1 };
    if (c.avcodec_open2(png_cc, png_codec, null) != 0) return error.CodecOpenError;

    var frame_rgba: *c.AVFrame = c.av_frame_alloc().?;
    defer c.av_frame_free(@ptrCast(&frame_rgba));
    frame_rgba.format = png_cc.pix_fmt;
    frame_rgba.width = png_cc.width;
    frame_rgba.height = png_cc.height;

    // Allocate a buffer for the new frame
    const num_bytes = c.av_image_get_buffer_size(frame_rgba.format, frame_rgba.width, frame_rgba.height, 1);
    const buf = try allocator.alloc(u8, @intCast(num_bytes));

    _ = c.av_image_fill_arrays(
        &frame_rgba.data,
        &frame_rgba.linesize,
        buf.ptr,
        frame_rgba.format,
        frame_rgba.width,
        frame_rgba.height,
        1,
    );

    const sws_ctx: *c.SwsContext = c.sws_getContext(
        input_cc.?.width,
        input_cc.?.height,
        input_cc.?.pix_fmt,
        frame_rgba.width,
        frame_rgba.height,
        frame_rgba.format,
        c.SWS_LANCZOS,
        null,
        null,
        null,
    ).?;
    defer c.sws_freeContext(sws_ctx);

    // Convert the frame
    _ = c.sws_scale(
        sws_ctx,
        &pFrame.?.data,
        &pFrame.?.linesize,
        0,
        input_cc.?.height,
        &frame_rgba.data,
        &frame_rgba.linesize,
    );

    // var output_packet: *c.AVPacket = c.av_packet_alloc().?;
    // defer c.av_packet_free(@ptrCast(&output_packet));
    // ret = c.avcodec_send_frame(png_cc, frame_rgba);
    // ret = c.avcodec_receive_packet(png_cc, output_packet);

    // var file = try std.fs.cwd().createFile("video.png", .{});
    // try file.writeAll(output_packet.data[0..@intCast(output_packet.size)]);

    // std.debug.print("got_output: {}\n", .{ret});
    return .{
        .width = width,
        .height = height,
        .buf = buf,
    };
}
