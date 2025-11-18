// Central Python C API import
// All other modules should import this to share the same py types
pub const py = @cImport({
    // TODO: Stable ABI support - will be implemented in later iteration
    // @cDefine("Py_LIMITED_API", "0x030C0000");
    @cInclude("Python.h");
});
