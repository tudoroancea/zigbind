#!/usr/bin/env python3
"""Demo of zigbind ergonomic function API."""

import hellozig

# Test simple string return
print("hello():", hellozig.hello())

# Test string parameter
print("greet('World'):", hellozig.greet("World"))

# Test integer parameters and return
print("add(5, 3):", hellozig.add(5, 3))

# Test float parameters and return
print("multiply(3.14, 2.0):", hellozig.multiply(3.14, 2.0))

# Test optional return (normal case)
print("divide(10.0, 2.0):", hellozig.divide(10.0, 2.0))

# Test optional return (error case)
try:
    print("divide(10.0, 0.0):", hellozig.divide(10.0, 0.0))
except ValueError as e:
    print("divide(10.0, 0.0): Caught ValueError:", e)

# Test boolean return
print("is_positive(5):", hellozig.is_positive(5))
print("is_positive(-3):", hellozig.is_positive(-3))

print("\n✅ All tests passed!")
