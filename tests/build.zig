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

    const modules = [_]struct { name: []const u8, file: []const u8 }{
        .{ .name = "test_functions", .file = "test_functions.zig" },
        .{ .name = "test_containers", .file = "test_containers.zig" },
        .{ .name = "test_memory_leak", .file = "test_memory_leak.zig" },
    };

    for (modules) |mod| {
        const lib = b.addLibrary(.{
            .name = b.fmt("{s}.abi3", .{mod.name}),
            .linkage = .dynamic,
            .root_module = b.createModule(.{
                .root_source_file = b.path(mod.file),
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

        const rename_step = b.addInstallFile(lib.getEmittedBin(), b.fmt("lib/{s}.abi3.so", .{mod.name}));
        b.getInstallStep().dependOn(&rename_step.step);
    }
}
