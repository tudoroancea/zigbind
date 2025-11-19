const std = @import("std");
const python_api = @import("python_api.zig");
const errors = @import("errors.zig");
const py = python_api.py;

/// Generic type caster for converting between Zig and Python types
pub fn TypeCaster(comptime T: type) type {
    return struct {
        /// Convert Python object to Zig value
        pub fn fromPython(obj: *py.PyObject) !T {
            return switch (@typeInfo(T)) {
                .int => fromPythonInt(T, obj),
                .float => fromPythonFloat(T, obj),
                .bool => fromPythonBool(obj),
                .pointer => |ptr| {
                    // Special handling: []const u8 is a string, not a list
                    if (ptr.size == .slice and ptr.child == u8 and ptr.is_const) {
                        return fromPythonString(obj);
                    }
                    // General list handling: []T where T is any type
                    if (ptr.size == .slice) {
                        return fromPythonList(T, obj);
                    }
                    @compileError("Unsupported pointer type: " ++ @typeName(T));
                },
                .optional => |opt| {
                    if (py.Py_IsNone(obj) != 0) {
                        return null;
                    }
                    const Inner = opt.child;
                    return try TypeCaster(Inner).fromPython(obj);
                },
                else => @compileError("Unsupported type for conversion: " ++ @typeName(T)),
            };
        }

        /// Convert Zig value to Python object
        pub fn toPython(value: T) !*py.PyObject {
            return switch (@typeInfo(T)) {
                .int => toPythonInt(value),
                .float => toPythonFloat(value),
                .bool => toPythonBool(value),
                .pointer => |ptr| {
                    // Special handling: []const u8 is a string, not a list
                    if (ptr.size == .slice and ptr.child == u8 and ptr.is_const) {
                        return toPythonString(value);
                    }
                    // General list handling: []T where T is any type
                    if (ptr.size == .slice) {
                        return toPythonList(T, value);
                    }
                    @compileError("Unsupported pointer type: " ++ @typeName(T));
                },
                .optional => {
                    if (value) |v| {
                        return try TypeCaster(@TypeOf(v)).toPython(v);
                    } else {
                        py.Py_IncRef(py.Py_None());
                        return @ptrCast(py.Py_None());
                    }
                },
                .void => {
                    py.Py_IncRef(py.Py_None());
                    return @ptrCast(py.Py_None());
                },
                else => @compileError("Unsupported type for conversion: " ++ @typeName(T)),
            };
        }
    };
}

// Integer conversion
fn fromPythonInt(comptime T: type, obj: *py.PyObject) !T {
    if (py.PyLong_Check(obj) == 0) {
        return errors.Error.TypeError;
    }

    const long_val = py.PyLong_AsLongLong(obj);
    if (py.PyErr_Occurred() != null) {
        return errors.Error.OverflowError;
    }

    return std.math.cast(T, long_val) orelse errors.Error.OverflowError;
}

fn toPythonInt(value: anytype) !*py.PyObject {
    const result = py.PyLong_FromLongLong(@as(c_longlong, value));
    if (result == null) {
        return errors.Error.MemoryError;
    }
    return result.?;
}

// Float conversion
fn fromPythonFloat(comptime T: type, obj: *py.PyObject) !T {
    // Accept both floats and ints
    var float_val: f64 = undefined;

    if (py.PyFloat_Check(obj) != 0) {
        float_val = py.PyFloat_AsDouble(obj);
    } else if (py.PyLong_Check(obj) != 0) {
        float_val = @floatFromInt(py.PyLong_AsLongLong(obj));
    } else {
        return errors.Error.TypeError;
    }

    if (py.PyErr_Occurred() != null) {
        return errors.Error.TypeError;
    }

    return @floatCast(float_val);
}

fn toPythonFloat(value: anytype) !*py.PyObject {
    const result = py.PyFloat_FromDouble(@as(f64, @floatCast(value)));
    if (result == null) {
        return errors.Error.MemoryError;
    }
    return result.?;
}

// Bool conversion
fn fromPythonBool(obj: *py.PyObject) !bool {
    const is_true = py.PyObject_IsTrue(obj);
    if (is_true < 0) {
        return errors.Error.TypeError;
    }
    return is_true == 1;
}

fn toPythonBool(value: bool) !*py.PyObject {
    // Use PyBool_FromLong instead of Py_True/Py_False to avoid translation issues
    const result = py.PyBool_FromLong(if (value) @as(c_long, 1) else @as(c_long, 0));
    if (result == null) {
        return errors.Error.MemoryError;
    }
    return result.?;
}

// String conversion
fn fromPythonString(obj: *py.PyObject) ![]const u8 {
    if (py.PyUnicode_Check(obj) == 0) {
        return errors.Error.TypeError;
    }

    var size: isize = undefined;
    const ptr = py.PyUnicode_AsUTF8AndSize(obj, &size);
    if (ptr == null) {
        return errors.Error.UnicodeError;
    }

    // Return a slice view into the Python string
    // Note: This is only valid while the Python object is alive
    return ptr[0..@intCast(size)];
}

fn toPythonString(str: []const u8) !*py.PyObject {
    const result = py.PyUnicode_FromStringAndSize(str.ptr, @intCast(str.len));
    if (result == null) {
        return errors.Error.MemoryError;
    }
    return result.?;
}

// Helper to check if value is None
pub fn isNone(obj: *py.PyObject) bool {
    return py.Py_IsNone(obj) != 0;
}

// List conversion ([]T ↔ list[T])
//
// Memory management:
// - fromPythonList allocates a Zig slice with std.heap.c_allocator
// - Caller is responsible for freeing the slice when done
// - toPythonList creates a new PyList with owned references
fn fromPythonList(comptime ListType: type, obj: *py.PyObject) !ListType {
    // ListType is []T or []const T
    const ptrinfo = @typeInfo(ListType).pointer;
    const ElementType = ptrinfo.child;
    const ElementCaster = TypeCaster(ElementType);

    // Verify we have a sequence
    if (py.PySequence_Check(obj) == 0) {
        return errors.Error.TypeError;
    }

    // Get sequence length
    // PySequence_Length can return -1 on error
    const seq_len = py.PySequence_Length(obj);
    if (seq_len < 0) {
        return errors.Error.RuntimeError;
    }

    const len = @as(usize, @intCast(seq_len));

    // Allocate slice for the elements
    // Using c_allocator since this interops with Python memory
    const allocator = std.heap.c_allocator;
    const slice = try allocator.alloc(ElementType, len);
    errdefer allocator.free(slice); // Free slice on error

    // Convert each element
    // PySequence_GetItem returns a NEW reference that we must decref
    for (0..len) |i| {
        const py_item = py.PySequence_GetItem(obj, @intCast(i));
        if (py_item == null) {
            // Error occurred; clean up and propagate
            return errors.Error.RuntimeError;
        }
        // PySequence_GetItem returned a NEW reference, so we must decref it
        defer py.Py_DecRef(py_item.?);

        // Convert the Python object to Zig type
        slice[i] = try ElementCaster.fromPython(py_item.?);
    }

    return slice;
}

fn toPythonList(comptime T: type, value: anytype) !*py.PyObject {
    // T is []const ElementType; value is []const ElementType
    const ptrinfo = @typeInfo(T).pointer;
    const ElementType = ptrinfo.child;
    const ElementCaster = TypeCaster(ElementType);
    const len = value.len;

    // Create a new Python list
    const py_list = py.PyList_New(@intCast(len));
    if (py_list == null) {
        return errors.Error.MemoryError;
    }
    // On error, we need to decref the list
    errdefer py.Py_DecRef(py_list.?);

    // Fill the list with converted elements
    for (value, 0..) |elem, i| {
        // Convert Zig element to Python object
        const py_elem = try ElementCaster.toPython(elem);
        // py_elem is a NEW reference (ownership passed to us)

        // PyList_SetItem STEALS the reference to py_elem
        // If it fails, we must decref py_elem ourselves
        const set_result = py.PyList_SetItem(py_list.?, @intCast(i), py_elem);
        if (set_result < 0) {
            // PyList_SetItem failed and did NOT steal the reference
            py.Py_DecRef(py_elem);
            return errors.Error.RuntimeError;
        }
        // PyList_SetItem succeeded and stole the reference, don't decref py_elem
    }

    return py_list.?;
}

// Reference counting helpers
pub fn incref(obj: *py.PyObject) void {
    py.Py_IncRef(obj);
}

pub fn decref(obj: *py.PyObject) void {
    py.Py_DecRef(obj);
}
