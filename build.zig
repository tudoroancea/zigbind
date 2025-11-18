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
    const zigbind = b.addModule("zigbind", .{
        .root_source_file = b.path("src/zigbind.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    zigbind.addIncludePath(.{ .cwd_relative = b.fmt("{s}/include/python3.12", .{python_prefix}) });
    zigbind.addLibraryPath(.{ .cwd_relative = b.fmt("{s}/lib", .{python_prefix}) });
    zigbind.linkSystemLibrary("python3.12", .{});
}
