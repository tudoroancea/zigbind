const std = @import("std");

// Import Python C API directly
pub const py = @cImport({
    // TODO: do we need to define Py_LIMITED_API?
    // @cDefine("Py_LIMITED_API", "0x030C0000");
    @cInclude("Python.h");
});

// Re-export commonly used types
pub const PyObject = py.PyObject;
pub const PyMethodDef = py.PyMethodDef;
pub const PyModuleDef = py.PyModuleDef;
pub const PyModuleDef_Base = py.PyModuleDef_Base;

pub fn module(pymodule_def: *py.PyModuleDef) ?*PyObject {
    return py.PyModule_Create(pymodule_def);
}
