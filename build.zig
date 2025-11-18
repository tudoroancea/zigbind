const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Get Python prefix from build option
    const python_prefix = b.option(
        []const u8,
        "python_prefix",
        "Path to Python installation (e.g., /usr/local or /home/user/.venv)",
    ) orelse {
        std.debug.print("Error: python_prefix build option not set\n", .{});
        std.process.exit(1);
    };

    // Create the zigbind extension module
    // For Python extension modules with stable ABI, use .abi3 suffix
    const zigbind = b.addLibrary(.{
        .name = "zigbind.abi3",
        .linkage = .dynamic,
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/zigbind.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    // Link against Python
    zigbind.linkLibC();
    // const include_path = ;
    // const lib_path = b.fmt("{s}/lib", .{python_prefix});
    zigbind.addIncludePath(.{ .cwd_relative = b.fmt("{s}/include/python3.12", .{python_prefix}) });
    zigbind.addLibraryPath(.{ .cwd_relative = b.fmt("{s}/lib", .{python_prefix}) });
    zigbind.linkSystemLibrary("python3.12");

    // For stable ABI
    zigbind.root_module.addCMacro("Py_LIMITED_API", "0x030C0000");

    b.installArtifact(zigbind);

    // Copy and rename the extension module to match Python's naming convention
    const rename_step = b.addInstallFile(
        zigbind.getEmittedBin(),
        "lib/zigbind.abi3.so",
    );
    b.getInstallStep().dependOn(&rename_step.step);
}
