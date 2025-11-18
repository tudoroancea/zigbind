const std = @import("std");
const zigbind = @import("zigbind");

fn hello_impl(_: ?*zigbind.PyObject, _: ?*zigbind.PyObject) callconv(.c) ?*zigbind.PyObject {
    const message = "Hello from Zig!";
    return zigbind.py.PyUnicode_FromStringAndSize(message.ptr, message.len);
}

var pymethods = [_]zigbind.PyMethodDef{.{
    .ml_name = "hello",
    .ml_meth = hello_impl,
    .ml_flags = zigbind.py.METH_NOARGS,
    .ml_doc = "Return a greeting from Zig",
}};

var pymodule_def = std.mem.zeroInit(zigbind.PyModuleDef, .{
    .m_name = "hellozig",
    .m_doc = "a simple hello would suffice",
    .m_size = -1,
    .m_methods = &pymethods,
});

export fn PyInit_hellozig() callconv(.c) ?*zigbind.PyObject {
    return zigbind.module(&pymodule_def);
}
