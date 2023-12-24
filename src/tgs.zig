const std = @import("std");
const lottie = @import("lottie");

const Image = @import("common.zig").Image;

fn bgraToRgba(data: []u32, comptime stride: usize) void {
    const line_len = 4 * stride;
    const mask: @Vector(line_len, i32) = comptime blk: {
        @setEvalBranchQuota(line_len);
        const block = [4]i32{ 2, 1, 0, 3 };
        var result: [line_len]i32 = undefined;
        for (&result, 0..) |*v, i| v.* = block[i % 4] + (i / 4) * 4;
        break :blk result;
    };
    const ptr: [*][line_len]u8 = @ptrCast(data.ptr);
    const parsing: [][line_len]u8 = ptr[0..@divExact(data.len, stride)];
    for (parsing) |*v| {
        v.* = @bitCast(@shuffle(u8, v.*, undefined, mask));
    }
}

pub fn readTgs(allocator: std.mem.Allocator, data: []const u8, max_dimension: usize) !Image {
    var in_stream = std.io.fixedBufferStream(data);

    var gzip_stream = try std.compress.gzip.decompress(allocator, in_stream.reader());
    defer gzip_stream.deinit();

    var out = std.ArrayList(u8).init(allocator);

    var fifo = std.fifo.LinearFifo(u8, .{ .Static = 4096 }).init();
    try fifo.pump(gzip_stream.reader(), out.writer());

    const tgs_data: [:0]const u8 = try out.toOwnedSliceSentinel(0);

    var animation = try lottie.Animation.fromData(tgs_data, "", "");
    defer animation.destroy();
    const width_anim, const height_anim = animation.getSize();
    const width_f: f64 = @floatFromInt(width_anim);
    const height_f: f64 = @floatFromInt(height_anim);

    const scale: f64 = @as(f64, @floatFromInt(max_dimension)) / @max(width_f, height_f);
    const width: u32 = @intFromFloat(@round(width_f * scale));
    const height: u32 = @intFromFloat(@round(height_f * scale));

    const buf = try allocator.alloc(u32, width * height);
    animation.render(0, buf, width, height, width * @sizeOf(u32));
    bgraToRgba(buf, 512);
    return .{
        .width = width,
        .height = height,
        .buf = @as([*]u8, @ptrCast(buf.ptr))[0 .. buf.len * 4],
    };
}
