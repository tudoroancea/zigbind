"""
Memory leak detection tests for list conversions.
Can be run with valgrind on Linux:
    valgrind --leak-check=full python -m pytest tests/test_memory_leak.py -v
"""

import pytest
import sys
import os
import gc

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "zig-out", "lib"))


@pytest.fixture(scope="session")
def test_mod():
    """Load test_memory_leak module after build."""
    import importlib.util
    lib_path = os.path.join(os.path.dirname(__file__), "zig-out", "lib")
    spec = importlib.util.spec_from_file_location("test_memory_leak", os.path.join(lib_path, "test_memory_leak.abi3.so"))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod



class TestMemoryLeaks:
    def test_many_allocations(self, test_mod):
        for i in range(1000):
            lst = test_mod.make_list(100)
            assert len(lst) == 100

    def test_large_lists(self, test_mod):
        for i in range(100):
            lst = test_mod.make_list(10000)
            assert len(lst) == 10000
            doubled = test_mod.double_list(lst)
            assert len(doubled) == 10000
            del lst
            del doubled
            gc.collect()

    def test_nested_operations(self, test_mod):
        for _ in range(500):
            lst1 = test_mod.make_list(50)
            lst2 = test_mod.double_list(lst1)
            total = test_mod.sum_list(lst2)
            assert total == 2 * sum(range(50))

    def test_python_to_zig(self, test_mod):
        for i in range(1000):
            result = test_mod.sum_list(list(range(100)))
            assert result == sum(range(100))

    def test_alternating_directions(self, test_mod):
        for i in range(500):
            zig_list = test_mod.make_list(50)
            total = test_mod.sum_list(zig_list)
            assert total == sum(range(50))

    def test_stress_different_sizes(self, test_mod):
        sizes = [1, 10, 100, 1000, 100, 10, 1, 50, 500]
        for _ in range(100):
            for size in sizes:
                lst = test_mod.make_list(size)
                assert len(lst) == size
                total = test_mod.sum_list(lst)
                assert total == sum(range(size))


class TestMemoryCorrectness:
    def test_values_correct(self, test_mod):
        for size in [1, 5, 10, 50, 100]:
            lst = test_mod.make_list(size)
            doubled = test_mod.double_list(lst)
            total = test_mod.sum_list(doubled)
            assert total == 2 * sum(range(size))

    def test_contents_preserved(self, test_mod):
        original = [1, 2, 3, 4, 5]
        doubled = test_mod.double_list(original)
        assert doubled == [2, 4, 6, 8, 10]
        quadrupled = test_mod.double_list(doubled)
        assert quadrupled == [4, 8, 12, 16, 20]
