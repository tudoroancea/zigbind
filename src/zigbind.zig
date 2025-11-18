const std = @import("std");

// Import Python C API directly
const py = @cImport({
    @cDefine("Py_LIMITED_API", "0x030C0000");
    @cInclude("Python.h");
});

// Re-export commonly used types
pub const PyObject = py.PyObject;
pub const PyMethodDef = py.PyMethodDef;
pub const PyModuleDef = py.PyModuleDef;
pub const PyModuleDef_Base = py.PyModuleDef_Base;

// Python function: hello() -> str
fn hello_impl(_: ?*PyObject, _: ?*PyObject) callconv(.c) ?*PyObject {
    const message = "Hello from Zig!";
    return py.PyUnicode_FromStringAndSize(message.ptr, message.len);
}

// Method definitions table
var methods = [_]PyMethodDef{
    .{
        .ml_name = "hello",
        .ml_meth = hello_impl,
        .ml_flags = py.METH_NOARGS,
        .ml_doc = "Return a greeting from Zig",
    },
    .{
        .ml_name = null,
        .ml_meth = null,
        .ml_flags = 0,
        .ml_doc = null,
    }, // Sentinel
};

// Module definition - use std.mem.zeroInit to properly initialize all fields to zero
var module_def = std.mem.zeroInit(PyModuleDef, .{
    .m_name = "zigbind",
    .m_doc = "Python bindings for Zig",
    .m_size = -1,
    .m_methods = &methods,
});

// Module initialization
export fn PyInit_zigbind() callconv(.c) ?*PyObject {
    return py.PyModule_Create(&module_def);
}
