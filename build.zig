const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const dep_rlottie = b.dependency("rlottie", .{ .target = target, .optimize = optimize });
    const dep_webp = b.dependency("zig_webp", .{ .target = target, .optimize = optimize });
    const dep_ffmpeg = b.dependency("libffmpeg", .{ .target = target, .optimize = optimize });

    _ = b.addModule("sticker-thumbnailer", .{ .source_file = .{ .path = "src/root.zig" }, .dependencies = &.{
        .{ .name = "lottie", .module = dep_rlottie.module("zig-rlottie") },
        .{ .name = "webp", .module = dep_webp.module("zig-webp") },
    } });

    const link = b.addStaticLibrary(.{
        .name = "linking",
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    link.linkLibrary(dep_rlottie.artifact("rlottie"));
    link.linkLibrary(dep_webp.artifact("webp"));
    link.linkLibrary(dep_ffmpeg.artifact("ffmpeg"));
    b.installArtifact(link);
}
