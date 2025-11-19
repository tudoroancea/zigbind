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

// Function that takes a list of integers and returns their sum
fn sum_list(nums: []const i32) i32 {
    var total: i32 = 0;
    for (nums) |n| {
        total +|= n; // Saturating add to handle overflow
    }
    return total;
}

// Function that returns a list of integers
fn make_list(n: i32) ![]i32 {
    const allocator = std.heap.c_allocator;
    const list = try allocator.alloc(i32, @intCast(n));
    for (0..@intCast(n)) |i| {
        list[i] = @intCast(i);
    }
    return list;
}

// Function that doubles all elements in a list
fn double_list(nums: []const i32) ![]i32 {
    const allocator = std.heap.c_allocator;
    const result = try allocator.alloc(i32, nums.len);
    for (nums, 0..) |n, i| {
        result[i] = n * 2;
    }
    return result;
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
    module.def(.{ .name = "sum_list", .func = sum_list, .doc = "Sum all integers in a list" }) catch return null;
    module.def(.{ .name = "make_list", .func = make_list, .doc = "Create a list of integers from 0 to n-1" }) catch return null;
    module.def(.{ .name = "double_list", .func = double_list, .doc = "Double all elements in a list" }) catch return null;

    return module.pyobject();
}
