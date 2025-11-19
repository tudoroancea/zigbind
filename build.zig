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

    // Detect Python version by checking what headers exist
    // Try python3.14, 3.13, 3.12, etc.
    const versions = [_][]const u8{ "python3.14", "python3.13", "python3.12", "python3.11" };
    var found_version: ?[]const u8 = null;

    inline for (versions) |ver| {
        const include_dir = b.fmt("{s}/include/{s}", .{ python_prefix, ver });
        if (std.fs.openDirAbsolute(include_dir, .{}) catch null) |dir_const| {
            var dir = dir_const;
            dir.close();
            found_version = ver;
            break;
        }
    }

    if (found_version == null) {
        std.debug.print("Error: Could not find Python headers in {s}/include/\n", .{python_prefix});
        std.process.exit(1);
    }

    const python_version = found_version.?;
    zigbind.addIncludePath(.{ .cwd_relative = b.fmt("{s}/include/{s}", .{ python_prefix, python_version }) });
    zigbind.addLibraryPath(.{ .cwd_relative = b.fmt("{s}/lib", .{python_prefix}) });
    zigbind.linkSystemLibrary(python_version, .{});
}
