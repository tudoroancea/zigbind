# Zig-Python Type Translation Research

**Date**: 2025-11-18
**Purpose**: Determine implementation strategy for Zig structs → Python classes and Python container types

---

## Table of Contents

1. [Executive Summary](#executive-summary)
2. [Zig Structs → Python Classes](#zig-structs--python-classes)
3. [Container Types Translation](#container-types-translation)
4. [Implementation Dependencies](#implementation-dependencies)
5. [Recommended Implementation Order](#recommended-implementation-order)

---

## Executive Summary

### Key Findings

**Q: Do we need general class support before implementing lists, tuples, dicts, sets?**

**A: No - container types can be implemented independently of custom class support.**

Container types (`list`, `tuple`, `dict`, `set`) are **built-in Python types** with their own C API functions. They don't require custom `PyTypeObject` creation or class binding infrastructure. However, both features will benefit from shared infrastructure in the type casting system.

### Recommended Approach

1. **Container types first** (simpler, high value, no class infrastructure needed)
   - Extend `type_caster.zig` with array/slice → list conversions
   - Add support for maps → dict, sets, tuples
   - Lower complexity, immediate value for function parameters

2. **Custom class support second** (more complex, requires new infrastructure)
   - Create `class.zig` for custom type registration
   - Implement `PyTypeObject` wrapper generation
   - Add method and property binding support
   - Requires object lifecycle management

---

## Zig Structs → Python Classes

### Zig Side: Structs

**What Zig provides:**

```zig
const Point = struct {
    x: f64,
    y: f64,

    pub fn init(x: f64, y: f64) Point {
        return Point{ .x = x, .y = y };
    }

    pub fn distance(self: Point, other: Point) f64 {
        const dx = self.x - other.x;
        const dy = self.y - other.y;
        return @sqrt(dx * dx + dy * dy);
    }

    pub fn deinit(self: *Point) void {
        // Cleanup if needed
    }
};
```

**Zig struct characteristics:**
- **Compile-time type introspection**: `@typeInfo(T)` reveals fields, methods, alignment
- **Field access**: `@field(instance, "fieldName")` for dynamic field access
- **Method conventions**: Methods take `self` or `*self` as first parameter
- **No inheritance**: Zig doesn't have traditional OOP inheritance
- **Interfaces via**: `anytype` parameters with duck typing, or explicit interface structs
- **Memory**: Structs are value types, can be stack or heap allocated

### Python Side: Custom Types

**What Python C API provides:**

#### Modern Approach (Limited API / Stable ABI)

Use `PyType_FromSpec` and `PyType_Spec` for heap-allocated types:

```c
// Type specification
PyType_Spec Point_spec = {
    .name = "mymodule.Point",
    .basicsize = sizeof(PointObject),
    .itemsize = 0,
    .flags = Py_TPFLAGS_DEFAULT,
    .slots = Point_slots,  // Array of PyType_Slot
};

// Instance structure
typedef struct {
    PyObject_HEAD      // Python object header
    double x;
    double y;
} PointObject;

// Slots define behavior
PyType_Slot Point_slots[] = {
    {Py_tp_new, Point_new},
    {Py_tp_dealloc, Point_dealloc},
    {Py_tp_methods, Point_methods},
    {Py_tp_getset, Point_getsetters},
    {Py_tp_doc, "2D Point"},
    {0, NULL},
};
```

#### Key Structures

**1. PyMethodDef** - Define methods:
```c
PyMethodDef Point_methods[] = {
    {"distance", (PyCFunction)Point_distance, METH_VARARGS,
     "Calculate distance to another point"},
    {NULL, NULL, 0, NULL},
};
```

**2. PyGetSetDef** - Define properties (getters/setters):
```c
PyGetSetDef Point_getsetters[] = {
    {"x", (getter)Point_get_x, (setter)Point_set_x,
     "X coordinate", NULL},
    {"y", (getter)Point_get_y, (setter)Point_set_y,
     "Y coordinate", NULL},
    {NULL, NULL, NULL, NULL, NULL},
};
```

**3. PyMemberDef** - Direct member access (simpler, less control):
```c
PyMemberDef Point_members[] = {
    {"x", T_DOUBLE, offsetof(PointObject, x), 0, "X coordinate"},
    {"y", T_DOUBLE, offsetof(PointObject, y), 0, "Y coordinate"},
    {NULL, 0, 0, 0, NULL},
};
```

### Zigbind Implementation Strategy

**Current pattern** (from existing implementation):
```zig
// type_caster.zig uses @typeInfo switch
return switch (@typeInfo(T)) {
    .int => fromPythonInt(T, obj),
    .float => fromPythonFloat(T, obj),
    // ... etc
};
```

**Extended pattern for structs**:
```zig
// In type_caster.zig
.@"struct" => |struct_info| {
    // Two cases:
    // 1. Registered custom type → extract instance
    // 2. Unregistered struct → convert from dict (future)
    return fromPythonStruct(T, obj);
},
```

**New file: `src/class.zig`**

Core responsibilities:
1. **Type registration**: Create `PyTypeObject` via `PyType_FromSpec`
2. **Instance wrapping**: Store Zig struct instance in Python object
3. **Method binding**: Generate C wrappers for Zig methods
4. **Property handling**: Generate getters/setters for struct fields
5. **Lifecycle management**: Handle `__new__`, `__init__`, `__dealloc__`

**Key data structure**:
```zig
/// Wrapper that combines PyObject header with Zig instance
fn InstanceWrapper(comptime T: type) type {
    return extern struct {
        // MUST be first field - Python expects this layout
        py_object: py.PyObject,

        // Zig instance data follows
        instance: T,
    };
}
```

**Type registration API** (matches existing `defineFunction` pattern):
```zig
pub fn defineClass(module: *py.PyObject, comptime config: anytype) !*py.PyTypeObject {
    const T = config.type;

    // Generate slots array at compile time
    const slots = comptime generateSlots(T);

    // Create PyType_Spec
    const spec = py.PyType_Spec{
        .name = config.name.ptr,
        .basicsize = @sizeOf(InstanceWrapper(T)),
        .itemsize = 0,
        .flags = py.Py_TPFLAGS_DEFAULT,
        .slots = &slots,
    };

    // Create type object
    const type_obj = py.PyType_FromSpec(&spec) orelse return error.TypeError;

    // Add to module
    _ = py.PyModule_AddObject(module, config.name.ptr, type_obj);

    return @ptrCast(type_obj);
}
```

**Method binding**:
```zig
pub fn defineMethod(type_obj: *py.PyTypeObject, comptime config: anytype) !void {
    // Similar to defineFunction but extracts instance first
    const wrapper = struct {
        fn call(self: ?*py.PyObject, args: ?*py.PyObject) callconv(.c) ?*py.PyObject {
            const instance_wrapper = @ptrCast(*InstanceWrapper(T), @alignCast(self.?));
            const instance = &instance_wrapper.instance;

            // Parse args (skip self)
            const zig_args = parseArgs(config.func, args.?) catch return null;

            // Call method: func(instance, ...args)
            const result = @call(.auto, config.func, .{instance} ++ zig_args) catch |err| {
                errors.setException(err);
                return null;
            };

            return convertResult(result) catch return null;
        }
    };

    // Add to type's method array
    // (implementation depends on how we store methods)
}
```

### Challenges & Solutions

| Challenge | Solution |
|-----------|----------|
| **Object layout** | Use `extern struct` with `PyObject` first, Zig instance second |
| **Memory management** | Implement `tp_new`/`tp_dealloc` wrappers that call Zig `init`/`deinit` if present |
| **Method discovery** | Use `@typeInfo(T).@"struct".decls` to find all public methods at compile time |
| **Field access** | Generate `PyGetSetDef` array at compile time using `@typeInfo(T).@"struct".fields` |
| **Reference counting** | Wrapper handles Python refcount; Zig instance uses normal Zig lifecycle |
| **Inheritance** | Not supported initially (Zig doesn't have inheritance anyway) |

---

## Container Types Translation

### Python Container Types

Python provides **four main container types** with dedicated C APIs:

#### 1. List (mutable sequence)

**C API Functions:**
```c
PyObject* PyList_New(Py_ssize_t len);                    // Create new list
int PyList_SetItem(PyObject *list, Py_ssize_t i, PyObject *item);
PyObject* PyList_GetItem(PyObject *list, Py_ssize_t i);  // Borrowed ref
int PyList_Append(PyObject *list, PyObject *item);
```

**Characteristics:**
- Dynamic size, O(1) append, O(1) indexed access
- Mutable, items can be any Python object
- Steals reference on `SetItem`, returns borrowed ref on `GetItem`

#### 2. Tuple (immutable sequence)

**C API Functions:**
```c
PyObject* PyTuple_New(Py_ssize_t len);
int PyTuple_SetItem(PyObject *tuple, Py_ssize_t i, PyObject *item);  // Only during construction!
PyObject* PyTuple_GetItem(PyObject *tuple, Py_ssize_t i);
```

**Characteristics:**
- Fixed size after creation
- Immutable (can only set items before first exposure to Python code)
- Faster than list for iteration, commonly used for function arguments

#### 3. Dict (hash map)

**C API Functions:**
```c
PyObject* PyDict_New();
int PyDict_SetItem(PyObject *dict, PyObject *key, PyObject *val);
PyObject* PyDict_GetItem(PyObject *dict, PyObject *key);       // Borrowed ref
int PyDict_DelItem(PyObject *dict, PyObject *key);
PyObject* PyDict_Keys(PyObject *dict);
PyObject* PyDict_Values(PyObject *dict);
PyObject* PyDict_Items(PyObject *dict);
```

**Characteristics:**
- Key-value mapping, O(1) average access
- Keys must be hashable (int, str, tuple of immutables, etc.)
- Values can be any Python object

#### 4. Set (hash set)

**C API Functions:**
```c
PyObject* PySet_New(PyObject *iterable);
int PySet_Add(PyObject *set, PyObject *key);
int PySet_Discard(PyObject *set, PyObject *key);
int PySet_Contains(PyObject *set, PyObject *key);
```

**Characteristics:**
- Unordered collection of unique items
- Items must be hashable
- O(1) membership testing

### Zig Container Types

Zig provides several container types in the standard library:

#### 1. Slices ([]T)

```zig
const numbers: []const i32 = &[_]i32{1, 2, 3, 4, 5};
const mutable: []i32 = try allocator.alloc(i32, 10);
```

**Characteristics:**
- Fat pointer: `{ .ptr = *T, .len = usize }`
- Can be const or mutable
- No built-in growth (use ArrayList for that)
- Natural mapping to Python list/tuple

#### 2. Arrays ([N]T)

```zig
const fixed: [5]i32 = [_]i32{1, 2, 3, 4, 5};
```

**Characteristics:**
- Fixed size known at compile time
- Stack allocated
- Coerces to slice
- Maps naturally to Python tuple (immutable, fixed size)

#### 3. ArrayList(T)

```zig
const std = @import("std");
var list = std.ArrayList(i32).init(allocator);
try list.append(42);
```

**Characteristics:**
- Dynamic array with growth
- Generic over element type
- Owns its memory
- Perfect mapping to Python list

#### 4. HashMap / AutoHashMap

```zig
var map = std.AutoHashMap([]const u8, i32).init(allocator);
try map.put("answer", 42);
```

**Characteristics:**
- Key-value storage
- Generic over key and value types
- Requires hashable keys
- Maps directly to Python dict

#### 5. HashSet / AutoHashSet

```zig
var set = std.AutoHashSet(i32).init(allocator);
try set.put(42);
```

**Characteristics:**
- Unique value storage
- Generic over element type
- Maps directly to Python set

### Zigbind Implementation Strategy

**Extend `type_caster.zig` with new cases:**

```zig
pub fn TypeCaster(comptime T: type) type {
    return struct {
        pub fn fromPython(obj: *py.PyObject) !T {
            return switch (@typeInfo(T)) {
                // ... existing cases ...

                .pointer => |ptr| {
                    if (ptr.size == .slice) {
                        // Handle slices
                        if (ptr.child == u8) {
                            return fromPythonString(obj);  // Existing
                        } else {
                            return fromPythonList(T, obj);  // New
                        }
                    }
                    @compileError("Unsupported pointer type");
                },

                .array => |arr| {
                    // Fixed-size arrays → tuple or list
                    return fromPythonArray(T, arr.len, arr.child, obj);
                },

                // For stdlib types, check type name
                else => {
                    const type_name = @typeName(T);
                    if (std.mem.startsWith(u8, type_name, "std.array_list.ArrayList")) {
                        return fromPythonArrayList(T, obj);
                    } else if (std.mem.startsWith(u8, type_name, "std.hash_map.HashMap")) {
                        return fromPythonHashMap(T, obj);
                    } else if (std.mem.startsWith(u8, type_name, "std.hash_map.AutoHashMap")) {
                        return fromPythonAutoHashMap(T, obj);
                    }
                    // ... etc
                    @compileError("Unsupported type: " ++ type_name);
                },
            };
        }

        pub fn toPython(value: T) !*py.PyObject {
            // Similar switch for conversion to Python
        }
    };
}
```

### Implementation Examples

#### Slice ↔ List

```zig
fn fromPythonList(comptime T: type, obj: *py.PyObject) !T {
    // T is []ElementType
    const ti = @typeInfo(T);
    const ElementType = ti.pointer.child;

    // Verify it's a list
    if (py.PyList_Check(obj) == 0) {
        return errors.Error.TypeError;
    }

    // Get size
    const size = py.PyList_Size(obj);
    if (size < 0) return errors.Error.RuntimeError;

    // Allocate Zig slice
    // Note: Need allocator! This is a challenge - where does it come from?
    const slice = try allocator.alloc(ElementType, @intCast(size));
    errdefer allocator.free(slice);

    // Convert each element
    for (0..@intCast(size)) |i| {
        const item = py.PyList_GetItem(obj, @intCast(i)) orelse {
            return errors.Error.RuntimeError;
        };
        slice[i] = try TypeCaster(ElementType).fromPython(item);
    }

    return slice;
}

fn toPythonList(slice: anytype) !*py.PyObject {
    const list = py.PyList_New(@intCast(slice.len)) orelse {
        return errors.Error.MemoryError;
    };
    errdefer py.Py_DecRef(list);

    for (slice, 0..) |item, i| {
        const py_item = try TypeCaster(@TypeOf(item)).toPython(item);
        // PyList_SetItem steals reference, no need to DecRef
        _ = py.PyList_SetItem(list, @intCast(i), py_item);
    }

    return list;
}
```

#### HashMap ↔ Dict

```zig
fn toPythonDict(map: anytype) !*py.PyObject {
    const dict = py.PyDict_New() orelse {
        return errors.Error.MemoryError;
    };
    errdefer py.Py_DecRef(dict);

    var it = map.iterator();
    while (it.next()) |entry| {
        const py_key = try TypeCaster(@TypeOf(entry.key_ptr.*)).toPython(entry.key_ptr.*);
        defer py.Py_DecRef(py_key);

        const py_val = try TypeCaster(@TypeOf(entry.value_ptr.*)).toPython(entry.value_ptr.*);
        defer py.Py_DecRef(py_val);

        const result = py.PyDict_SetItem(dict, py_key, py_val);
        if (result < 0) {
            return errors.Error.RuntimeError;
        }
    }

    return dict;
}
```

### Key Challenges

| Challenge | Solution |
|-----------|----------|
| **Allocator requirement** | Pass allocator to type casters, or use arena allocator per call |
| **Memory ownership** | Returned slices from `fromPython` must be freed by caller |
| **Nested containers** | Recursive `TypeCaster` calls handle nested structures automatically |
| **Type erasure** | Can't detect ArrayList/HashMap from `@typeInfo` alone - need string matching or trait system |
| **Hashability** | Python dict keys must be hashable - need runtime check or compile-time restriction |

---

## Implementation Dependencies

### Dependency Graph

```
┌─────────────────────────────────────────────────┐
│         Core Type System (Iteration 1) ✅       │
│  - Basic types: int, float, bool, str, void     │
│  - Optionals, error unions                      │
│  - Function wrapping with auto type conversion  │
└────────────────┬────────────────────────────────┘
                 │
        ┌────────┴──────────┐
        │                   │
        ▼                   ▼
┌───────────────┐    ┌──────────────────┐
│  Containers   │    │  Custom Classes  │
│  (Iteration   │    │   (Iteration 2)  │
│     2a?)      │    │                  │
└───────────────┘    └──────────────────┘
        │                   │
        │                   │
        └────────┬──────────┘
                 │
                 ▼
        ┌────────────────┐
        │  Shared Future │
        │   Features:    │
        │  - Allocators  │
        │  - Generics    │
        │  - Advanced    │
        └────────────────┘
```

### Analysis

**Containers are INDEPENDENT of classes:**

✅ **Can implement containers without class support:**
- Lists, tuples, dicts, sets are built-in Python types
- Use existing `PyList_*`, `PyDict_*`, etc. C API functions
- No need for `PyTypeObject` creation or custom types
- Only requires extending `type_caster.zig`

✅ **Can implement classes without container support:**
- Custom class binding uses `PyType_FromSpec`
- Methods and properties work with basic types
- Containers are just another type the casters can handle

⚠️ **Shared dependencies both will need:**

1. **Allocator management**:
   - Containers: Need allocator to create Zig slices/collections from Python
   - Classes: Need allocator for instance data (if dynamic)
   - **Solution**: Thread-local arena allocator or parameter passing

2. **Type caster recursion**:
   - Containers: Already works (tested with Optional)
   - Classes: Will need for struct field conversions
   - **Solution**: Current architecture already supports this

3. **Error handling**:
   - Both already use existing `errors.zig` system
   - No new infrastructure needed

### What's Actually Independent

**Completely independent implementations:**

- ✅ Container support doesn't need any class code
- ✅ Class support doesn't need any container code
- ✅ Both can be developed in parallel if desired
- ✅ Testing can happen independently

**Shared infrastructure (already exists):**

- ✅ Type casting framework (`type_caster.zig`)
- ✅ Error handling (`errors.zig`)
- ✅ Python API imports (`python_api.zig`)
- ✅ Module registration (`module.zig`)

---

## Recommended Implementation Order

### Option A: Containers First (Recommended)

**Rationale:**
1. **Lower complexity**: Uses existing Python types, no new infrastructure
2. **Higher immediate value**: Functions can now accept/return lists, dicts, etc.
3. **Faster iteration**: Smaller scope, quicker to test and refine
4. **Validates type caster design**: Tests recursive type conversion before classes
5. **User facing benefit**: Most functions work with containers more than custom types

**Iteration 2a: Container Support (1-2 weeks)**

Tasks:
1. Add allocator parameter to type casters (or use arena)
2. Implement `[]T` ↔ list conversion
3. Implement `[N]T` ↔ tuple conversion
4. Implement dict support (if we detect HashMap)
5. Implement set support (if we detect HashSet)
6. Add comprehensive tests
7. Update examples

**Files to modify:**
- `src/type_caster.zig` - Add new type cases
- `src/function.zig` - Pass allocator to parseArgs
- `tests/test_containers.py` - New test file
- `examples/containers/` - New example

**Iteration 2b: Class Support (2-3 weeks)**

Tasks:
1. Create `src/class.zig`
2. Implement `defineClass()` API
3. Implement method binding via `defineMethod()`
4. Implement property support via `defineProperty()`
5. Handle object lifecycle (new, init, dealloc)
6. Add struct field auto-discovery
7. Add comprehensive tests
8. Update examples

**Files to create/modify:**
- `src/class.zig` - New file
- `src/type_caster.zig` - Add struct case
- `tests/test_classes.py` - New test file
- `examples/classes/` - New example

### Option B: Classes First (Alternative)

**Rationale:**
1. **Original plan**: Implementation plan shows this was intended next
2. **Foundation for future**: Classes enable OOP patterns
3. **Inspiration from nanobind**: Follows their implementation order

**Iteration 2: Class Support**
- Same tasks as Option A Iteration 2b above

**Iteration 3: Container Support**
- Same tasks as Option A Iteration 2a above

### Option C: Parallel Development

**Rationale:**
1. **Independence**: Features don't depend on each other
2. **Team efficiency**: If multiple developers, can work simultaneously

**Risks:**
- Merge conflicts in `type_caster.zig`
- Need coordination on allocator strategy
- More complex testing matrix

---

## Detailed Type Mapping Tables

### Zig → Python Type Mappings

| Zig Type | Python Type | Conversion API | Notes |
|----------|-------------|----------------|-------|
| `i8` to `i64` | `int` | `PyLong_FromLongLong` | ✅ Already implemented |
| `u8` to `u64` | `int` | `PyLong_FromUnsignedLongLong` | Check sign in fromPython |
| `f32`, `f64` | `float` | `PyFloat_FromDouble` | ✅ Already implemented |
| `bool` | `bool` | `PyBool_FromLong` | ✅ Already implemented |
| `[]const u8` | `str` | `PyUnicode_FromStringAndSize` | ✅ Already implemented |
| `?T` | `T \| None` | Check `Py_IsNone()` | ✅ Already implemented |
| `!T` | T or exception | Set exception on error | ✅ Already implemented |
| `void` | `None` | `Py_None()` | ✅ Already implemented |
| `[]T` | `list[T]` | `PyList_New/SetItem` | 🔲 TODO |
| `[N]T` | `tuple[T, ...]` | `PyTuple_New/SetItem` | 🔲 TODO |
| `ArrayList(T)` | `list[T]` | `PyList_New/SetItem` | 🔲 TODO |
| `HashMap(K,V)` | `dict[K, V]` | `PyDict_New/SetItem` | 🔲 TODO |
| `HashSet(T)` | `set[T]` | `PySet_New/Add` | 🔲 TODO |
| `enum { A, B }` | `Enum` or `int` | Custom or `PyLong_FromLong` | 🔲 TODO (Iteration 3) |
| `union(enum)` | Custom | `PyType_FromSpec` | 🔲 TODO (Iteration 4) |
| `struct { }` | Custom class | `PyType_FromSpec` | 🔲 TODO (Iteration 2/2b) |

### Python → Zig Type Mappings

| Python Type | Zig Type | Validation | Notes |
|-------------|----------|------------|-------|
| `int` | `i32`, `i64`, etc. | Overflow check | ✅ Already implemented |
| `float` | `f32`, `f64` | Accept int too | ✅ Already implemented |
| `bool` | `bool` | `PyObject_IsTrue` | ✅ Already implemented |
| `str` | `[]const u8` | UTF-8 check | ✅ Already implemented |
| `None` | `?T` (null) | `Py_IsNone()` | ✅ Already implemented |
| `list` | `[]T` | Element type check | 🔲 TODO, requires allocator |
| `tuple` | `[N]T` or `[]T` | Size/type check | 🔲 TODO |
| `dict` | `HashMap(K, V)` | Key/value type check | 🔲 TODO |
| `set` | `HashSet(T)` | Element type check | 🔲 TODO |
| Custom class | `struct` | Type check | 🔲 TODO (Iteration 2/2b) |

---

## Allocator Strategy for Containers

### Problem

Converting Python containers to Zig requires allocation:

```zig
// This needs an allocator!
fn fromPythonList(obj: *py.PyObject) ![]i32 {
    const slice = try allocator.alloc(i32, size);  // ❌ Where does allocator come from?
    // ...
}
```

### Options

#### Option 1: Arena Allocator Per Function Call

```zig
// In function.zig wrapper
pub fn defineFunction(...) {
    const wrapper = struct {
        fn call(self: ?*py.PyObject, args: ?*py.PyObject) callconv(.c) ?*py.PyObject {
            // Create arena for this call
            var arena = std.heap.ArenaAllocator.init(std.heap.c_allocator);
            defer arena.deinit();  // Frees everything when function returns

            const allocator = arena.allocator();

            // Pass allocator to parseArgs
            const zig_args = parseArgs(func, args.?, allocator) catch ...;

            // ... rest of call ...
        }
    };
}
```

**Pros:**
- ✅ Simple: All allocations freed automatically
- ✅ No memory leaks possible
- ✅ Thread-safe: Each call gets its own arena

**Cons:**
- ❌ Can't return Zig containers that own memory (they'd be freed)
- ❌ Slight overhead for arena creation/destruction

**Verdict:** ✅ **Best for function parameters** (containers going Zig → Python)

#### Option 2: Caller-Managed Allocator

```zig
// User passes allocator explicitly
pub fn defineFunction(module: *py.PyObject, comptime config: anytype, allocator: Allocator) !void {
    // Store allocator, use in conversions
}
```

**Pros:**
- ✅ Flexible: Caller controls memory strategy
- ✅ Can return owned memory

**Cons:**
- ❌ Less ergonomic: Every function needs allocator parameter
- ❌ Breaks existing API

**Verdict:** ❌ Too invasive for current design

#### Option 3: Global Allocator

```zig
var global_allocator: Allocator = std.heap.c_allocator;

pub fn setAllocator(allocator: Allocator) void {
    global_allocator = allocator;
}
```

**Pros:**
- ✅ Ergonomic: No API changes
- ✅ Flexible: User can swap allocator

**Cons:**
- ❌ Global state
- ❌ Thread-safety concerns
- ❌ Harder to track leaks

**Verdict:** ⚠️ Possible but not ideal

#### Option 4: Hybrid Approach (Recommended)

```zig
// Use arena for parameters (Python → Zig)
// Use C allocator for return values (Zig → Python)

// Function wrapper creates arena
var arena = std.heap.ArenaAllocator.init(std.heap.c_allocator);
defer arena.deinit();

const zig_args = parseArgs(func, args, arena.allocator()) catch ...;

// Return values use C allocator
const result = callFunc(zig_args);  // May contain owned containers
return toPython(result, std.heap.c_allocator) catch ...;
```

**Pros:**
- ✅ Safe for parameters (auto-freed)
- ✅ Allows returning owned data
- ✅ Minimal API impact

**Cons:**
- ⚠️ Returned containers must be manually freed (document this)

**Verdict:** ✅ **Recommended approach**

---

## Testing Strategy

### Container Tests

```python
# tests/test_containers.py

def test_list_parameter():
    """Test function accepting list parameter"""
    import zigmod
    result = zigmod.sum_list([1, 2, 3, 4])
    assert result == 10

def test_list_return():
    """Test function returning list"""
    import zigmod
    result = zigmod.make_range(5)
    assert result == [0, 1, 2, 3, 4]

def test_dict_parameter():
    """Test function accepting dict parameter"""
    import zigmod
    result = zigmod.sum_dict_values({"a": 1, "b": 2, "c": 3})
    assert result == 6

def test_nested_containers():
    """Test nested structures"""
    import zigmod
    result = zigmod.process_nested([[1, 2], [3, 4]])
    assert result == [[2, 3], [4, 5]]
```

### Class Tests

```python
# tests/test_classes.py

def test_class_creation():
    """Test instantiating Zig struct as Python class"""
    import zigmod
    point = zigmod.Point(3.0, 4.0)
    assert point.x == 3.0
    assert point.y == 4.0

def test_class_method():
    """Test calling method on instance"""
    import zigmod
    p1 = zigmod.Point(0.0, 0.0)
    p2 = zigmod.Point(3.0, 4.0)
    assert p1.distance(p2) == 5.0

def test_class_property():
    """Test property getter/setter"""
    import zigmod
    point = zigmod.Point(1.0, 2.0)
    point.x = 10.0
    assert point.x == 10.0
```

---

## Conclusion

### Summary

1. **Containers and classes are independent** - either can be implemented first
2. **Recommend containers first** - simpler, faster value, validates type caster design
3. **Both will share allocator infrastructure** - plan this carefully
4. **Testing strategy is clear** - comprehensive pytest suite for both

### Next Steps

1. **Decision**: Choose implementation order (Option A recommended)
2. **Allocator design**: Implement hybrid allocator strategy
3. **Start implementation**: Begin with chosen feature
4. **Iterate**: Build, test, refine, repeat

### Open Questions

1. **Enum support**: How to map Zig enums to Python? (IntEnum, custom class, or just int?)
2. **Tagged unions**: How to represent `union(enum)` in Python?
3. **Generic types**: Should we support generic Zig functions/structs?
4. **Memory semantics**: How to handle mutable vs immutable containers?
5. **Stable ABI timeline**: When to enable Limited API support?

---

**End of Research Document**
