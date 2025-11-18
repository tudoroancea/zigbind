const std = @import("std");
const python_api = @import("python_api.zig");
const py = python_api.py;

/// Zigbind error types
pub const Error = error{
    TypeError,
    ValueError,
    MemoryError,
    OverflowError,
    RuntimeError,
    UnicodeError,
    KeyError,
    IndexError,
};

/// Map Zig error to appropriate Python exception type
pub fn getPyException(err: anyerror) *py.PyObject {
    return switch (err) {
        error.OutOfMemory => py.PyExc_MemoryError,
        error.InvalidUtf8 => py.PyExc_UnicodeError,
        error.Overflow => py.PyExc_OverflowError,
        Error.TypeError => py.PyExc_TypeError,
        Error.ValueError => py.PyExc_ValueError,
        Error.MemoryError => py.PyExc_MemoryError,
        Error.OverflowError => py.PyExc_OverflowError,
        Error.UnicodeError => py.PyExc_UnicodeError,
        Error.KeyError => py.PyExc_KeyError,
        Error.IndexError => py.PyExc_IndexError,
        else => py.PyExc_RuntimeError,
    };
}

/// Set Python exception from Zig error
pub fn setException(err: anyerror) void {
    const exc = getPyException(err);
    const msg = @errorName(err);
    py.PyErr_SetString(exc, msg.ptr);
}

/// Set Python exception with custom message
pub fn setExceptionWithMessage(err: anyerror, message: [*:0]const u8) void {
    const exc = getPyException(err);
    py.PyErr_SetString(exc, message);
}

/// Check if a Python error occurred
pub fn checkError() bool {
    return py.PyErr_Occurred() != null;
}

/// Clear Python error
pub fn clearError() void {
    py.PyErr_Clear();
}
