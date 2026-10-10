const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{
        .default_target = .{ .cpu_model = .baseline, .os_tag = .windows, .abi = .gnu },
    });
    // Default to ReleaseSmall (Zig 0.16's standardOptimizeOption falls back to
    // Debug without -Drelease, so supply the default ourselves).
    const optimize = b.option(std.builtin.OptimizeMode, "optimize", "Optimize mode") orelse .ReleaseSmall;

    const exe = b.addExecutable(.{
        .name = "keymouse",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .strip = optimize != .Debug,
        }),
    });
    exe.subsystem = .windows;
    exe.root_module.linkSystemLibrary("user32", .{});
    exe.root_module.linkSystemLibrary("kernel32", .{});
    exe.root_module.linkSystemLibrary("gdi32", .{});
    exe.root_module.linkSystemLibrary("shell32", .{});
    exe.root_module.linkSystemLibrary("advapi32", .{});
    b.installArtifact(exe);
}
