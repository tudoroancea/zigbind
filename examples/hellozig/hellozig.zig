const std = @import("std");
const zb = @import("zigbind");

// Simple function that returns a string
fn hello() []const u8 {
    return "Hello from Zig!";
}

// Function with parameters - just echo back the name
fn greet(name: []const u8) []const u8 {
    // Note: We're returning the input string directly
    // For formatted strings, we'd need to allocate properly
    return name;
}

// Function with numbers
fn add(a: i32, b: i32) i32 {
    return a + b;
}

// Function with floats
fn multiply(a: f64, b: f64) f64 {
    return a * b;
}

// Function with optional return
fn divide(a: f64, b: f64) !?f64 {
    if (b == 0.0) {
        return error.ValueError;
    }
    return a / b;
}

// Function with boolean
fn is_positive(x: i32) bool {
    return x > 0;
}

export fn PyInit_hellozig() callconv(.c) ?*zb.PyObject {
    var module = zb.Module.init(.{
        .name = "hellozig",
        .doc = "Example Zig extension module with ergonomic API",
    }) catch return null;

    module.def(.{ .name = "hello", .func = hello, .doc = "Return a greeting from Zig" }) catch return null;
    module.def(.{ .name = "greet", .func = greet, .doc = "Echo back the name (demo of string parameter)" }) catch return null;
    module.def(.{ .name = "add", .func = add, .doc = "Add two integers" }) catch return null;
    module.def(.{ .name = "multiply", .func = multiply, .doc = "Multiply two floats" }) catch return null;
    module.def(.{ .name = "divide", .func = divide, .doc = "Divide two floats (returns None if divisor is zero)" }) catch return null;
    module.def(.{ .name = "is_positive", .func = is_positive, .doc = "Check if a number is positive" }) catch return null;

    return module.pyobject();
}
