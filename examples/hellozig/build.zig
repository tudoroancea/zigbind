const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    // TODO: this is redundant with zigbind
    const python_prefix = b.option(
        []const u8,
        "python_prefix",
        "Path to Python installation (e.g., /usr/local or /home/user/.venv)",
    ) orelse {
        std.debug.print("Error: python_prefix build option not set\n", .{});
        std.process.exit(1);
    };

    const lib = b.addLibrary(.{
        .name = "hellozig.abi3", // For Python extension modules with stable ABI, use .abi3 suffix
        .linkage = .dynamic,
        .root_module = b.createModule(.{
            .root_source_file = b.path("hellozig.zig"),
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

    // TODO: move this to zigbind
    // Copy and rename the extension module to match Python's naming convention
    const rename_step = b.addInstallFile(lib.getEmittedBin(), "lib/hellozig.abi3.so");
    b.getInstallStep().dependOn(&rename_step.step);
}
