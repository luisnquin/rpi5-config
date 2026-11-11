const std = @import("std");

pub fn build(b: *std.Build) void {
    const mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = b.standardTargetOptions(.{}),
        .optimize = b.standardOptimizeOption(.{}),
        .link_libc = true,
    });
    b.installArtifact(b.addExecutable(.{ .name = "skinner", .root_module = mod }));
    const tests = b.addRunArtifact(b.addTest(.{ .root_module = mod }));
    b.step("test", "Run unit tests").dependOn(&tests.step);
}
