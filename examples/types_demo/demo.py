#!/usr/bin/env python3
"""Demo of type conversions in zigbind: int, float, bool, string, error handling."""

import types_demo

# Integer arithmetic
print("add(5, 3):", types_demo.add(5, 3))

# Float arithmetic
print("multiply(3.14, 2.0):", types_demo.multiply(3.14, 2.0))

# Boolean return
print("is_positive(5):", types_demo.is_positive(5))
print("is_positive(-3):", types_demo.is_positive(-3))

# String parameter and return
print("greet('Zig'):", types_demo.greet("Zig"))

# Error handling (error case)
try:
    types_demo.divide(10.0, 0.0)
except ValueError as e:
    print("divide(10.0, 0.0): Caught ValueError:", e)

# Division (normal case)
print("divide(10.0, 2.0):", types_demo.divide(10.0, 2.0))

print("\n✅ All type conversions working!")
