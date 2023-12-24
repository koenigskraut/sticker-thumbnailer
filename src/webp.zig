const std = @import("std");
const webp = @import("webp");

const Image = @import("common.zig").Image;
const DecoderConfig = webp.decode.DecoderConfig;

pub fn readWebp(allocator: std.mem.Allocator, data: []const u8, max_dimension: usize) !Image {
    const width_in, const height_in = try webp.decode.getInfo(data);

    var config: DecoderConfig = undefined;
    try config.init();

    const width: f64 = @floatFromInt(width_in);
    const height: f64 = @floatFromInt(height_in);
    const scale = @as(f64, @floatFromInt(max_dimension)) / @max(width, height);

    config.options.use_scaling = 1;
    config.options.scaled_width = @intFromFloat(@round(scale * width));
    config.options.scaled_height = @intFromFloat(@round(scale * height));
    const stride = config.options.scaled_width * 4;

    config.output.colorspace = .RGBA;
    const buf = try allocator.alloc(u8, @intCast(stride * config.options.scaled_height));
    config.output.u.RGBA.rgba = buf.ptr;
    config.output.u.RGBA.size = buf.len;
    config.output.u.RGBA.stride = stride;
    config.output.is_external_memory = 1;

    try webp.decode.decode(data, &config);

    return .{
        .width = @intCast(config.options.scaled_width),
        .height = @intCast(config.options.scaled_height),
        .buf = buf,
    };
}
