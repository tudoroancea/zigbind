const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const python_prefix = b.option(
        []const u8,
        "python_prefix",
        "Path to Python installation",
    ) orelse {
        std.debug.print("Error: python_prefix build option not set\n", .{});
        std.process.exit(1);
    };

    const lib = b.addLibrary(.{
        .name = "types_demo.abi3",
        .linkage = .dynamic,
        .root_module = b.createModule(.{
            .root_source_file = b.path("types_demo.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    lib.root_module.addImport("zigbind", b.dependency("zigbind", .{
        .target = target,
        .optimize = optimize,
        .python_prefix = python_prefix,
    }).module("zigbind"));
    b.installArtifact(lib);

    const rename_step = b.addInstallFile(lib.getEmittedBin(), "lib/types_demo.abi3.so");
    b.getInstallStep().dependOn(&rename_step.step);
}
