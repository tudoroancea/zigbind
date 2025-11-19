const zb = @import("zigbind");

fn hello() []const u8 {
    return "Hello from Zig!";
}

fn greet(name: []const u8) []const u8 {
    return name;
}

fn add(a: i32, b: i32) i32 {
    return a + b;
}

fn multiply(a: f64, b: f64) f64 {
    return a * b;
}

fn is_positive(x: i32) bool {
    return x > 0;
}

fn divide(a: f64, b: f64) !?f64 {
    if (b == 0.0) return error.ValueError;
    return a / b;
}

export fn PyInit_test_functions() callconv(.c) ?*zb.PyObject {
    var module = zb.Module.init(.{
        .name = "test_functions",
        .doc = "Test module for basic function types",
    }) catch return null;

    module.def(.{ .name = "hello", .func = hello, .doc = "Return hello greeting" }) catch return null;
    module.def(.{ .name = "greet", .func = greet, .doc = "Return input string" }) catch return null;
    module.def(.{ .name = "add", .func = add, .doc = "Add two integers" }) catch return null;
    module.def(.{ .name = "multiply", .func = multiply, .doc = "Multiply two floats" }) catch return null;
    module.def(.{ .name = "is_positive", .func = is_positive, .doc = "Check if positive" }) catch return null;
    module.def(.{ .name = "divide", .func = divide, .doc = "Divide floats, raise ValueError on zero" }) catch return null;

    return module.pyobject();
}
