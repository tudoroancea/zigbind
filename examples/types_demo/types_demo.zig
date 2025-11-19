const zb = @import("zigbind");

fn add(a: i32, b: i32) i32 {
    return a + b;
}

fn multiply(a: f64, b: f64) f64 {
    return a * b;
}

fn is_positive(x: i32) bool {
    return x > 0;
}

fn greet(name: []const u8) []const u8 {
    return name;
}

fn divide(a: f64, b: f64) !?f64 {
    if (b == 0.0) return error.ValueError;
    return a / b;
}

export fn PyInit_types_demo() callconv(.c) ?*zb.PyObject {
    var module = zb.Module.init(.{
        .name = "types_demo",
        .doc = "Demo of basic type conversions: int, float, bool, string, error handling",
    }) catch return null;

    module.def(.{ .name = "add", .func = add, .doc = "Add two integers" }) catch return null;
    module.def(.{ .name = "multiply", .func = multiply, .doc = "Multiply two floats" }) catch return null;
    module.def(.{ .name = "is_positive", .func = is_positive, .doc = "Check if positive" }) catch return null;
    module.def(.{ .name = "greet", .func = greet, .doc = "Echo a name" }) catch return null;
    module.def(.{ .name = "divide", .func = divide, .doc = "Divide (raises ValueError on div by zero)" }) catch return null;

    return module.pyobject();
}
