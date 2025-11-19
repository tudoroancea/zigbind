const std = @import("std");
const zb = @import("zigbind");

fn sum_list(nums: []const i32) i32 {
    var total: i32 = 0;
    for (nums) |n| {
        total +|= n;
    }
    return total;
}

fn make_list(n: i32) ![]i32 {
    const allocator = std.heap.c_allocator;
    const list = try allocator.alloc(i32, @intCast(n));
    for (0..@intCast(n)) |i| {
        list[i] = @intCast(i);
    }
    return list;
}

fn double_list(nums: []const i32) ![]i32 {
    const allocator = std.heap.c_allocator;
    const result = try allocator.alloc(i32, nums.len);
    for (nums, 0..) |n, i| {
        result[i] = n * 2;
    }
    return result;
}

export fn PyInit_test_memory_leak() callconv(.c) ?*zb.PyObject {
    var module = zb.Module.init(.{
        .name = "test_memory_leak",
        .doc = "Test module for memory leak detection",
    }) catch return null;

    module.def(.{ .name = "sum_list", .func = sum_list, .doc = "Sum integers in list" }) catch return null;
    module.def(.{ .name = "make_list", .func = make_list, .doc = "Create list 0..n" }) catch return null;
    module.def(.{ .name = "double_list", .func = double_list, .doc = "Double all values in list" }) catch return null;

    return module.pyobject();
}
