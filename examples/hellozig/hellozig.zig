const zb = @import("zigbind");

fn hello() []const u8 {
    return "Hello from Zig!";
}

export fn PyInit_hellozig() callconv(.c) ?*zb.PyObject {
    var module = zb.Module.init(.{
        .name = "hellozig",
        .doc = "Minimal hello world Zig extension module",
    }) catch return null;

    module.def(.{ .name = "hello", .func = hello, .doc = "Return a greeting" }) catch return null;

    return module.pyobject();
}
