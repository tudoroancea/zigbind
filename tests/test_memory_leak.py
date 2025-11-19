"""
Memory leak detection test for list conversions.

This test is designed to detect memory leaks when converting between
Python lists and Zig slices. It can be run with valgrind on Linux:

    valgrind --leak-check=full --show-leak-kinds=all \\
        python -m pytest tests/test_memory_leak.py -v

Expected on macOS without valgrind:
- Tests pass but memory may leak (can't detect without tools)
- Run on Linux with valgrind to verify no leaks

Expected with valgrind and fix:
- All allocations properly freed
- No "definitely lost" or "indirectly lost" blocks
"""

import pytest
import sys
import os
import gc

# Add hellozig to path
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "examples", "hellozig", "zig-out", "lib"))

import hellozig


class TestMemoryLeakDetection:
    """Tests specifically designed to detect memory leaks with valgrind."""

    def test_many_list_allocations_and_returns(self):
        """
        Test: Allocate many lists and immediately discard them.

        If slices aren't freed, this will leak memory.
        With valgrind: valgrind --leak-check=full python -m pytest tests/test_memory_leak.py::TestMemoryLeakDetection::test_many_list_allocations_and_returns -v
        """
        for i in range(1000):
            # Each call allocates a list on the Zig side
            lst = hellozig.make_list(100)
            # List goes out of scope immediately (should be freed by Python's GC)
            # But the underlying Zig allocation might leak
            assert len(lst) == 100

    def test_large_list_creation_many_times(self):
        """
        Test: Create large lists repeatedly.

        If slice allocations leak, memory usage should grow significantly.
        With valgrind will show if c_allocator calls are matched with frees.
        """
        for i in range(100):
            # Create a large list
            lst = hellozig.make_list(10000)
            assert len(lst) == 10000
            # Process it
            doubled = hellozig.double_list(lst)
            assert len(doubled) == 10000
            # Explicit GC to ensure Python cleanup happens
            del lst
            del doubled
            gc.collect()

    def test_nested_list_operations_leak(self):
        """
        Test: Perform nested list operations that allocate multiple slices.

        Each operation allocates and converts lists. Leaks compound.
        """
        for _ in range(500):
            # make_list allocates a slice
            lst1 = hellozig.make_list(50)
            # double_list allocates another slice
            lst2 = hellozig.double_list(lst1)
            # sum_list consumes the list
            total = hellozig.sum_list(lst2)
            assert total == 2 * sum(range(50))

    def test_list_from_python_allocation(self):
        """
        Test: Pass Python lists to Zig many times.

        Each call to sum_list with a Python list causes fromPythonList to allocate.
        If these allocations aren't freed, we leak.
        """
        for i in range(1000):
            result = hellozig.sum_list(list(range(100)))
            assert result == sum(range(100))

    def test_alternating_directions(self):
        """
        Test: Alternate between Python->Zig and Zig->Python conversions.

        This exercises both fromPythonList and toPythonList allocation paths.
        """
        for i in range(500):
            # Zig allocates and returns (toPythonList)
            zig_list = hellozig.make_list(50)
            # Python passes it back to Zig (fromPythonList)
            total = hellozig.sum_list(zig_list)
            assert total == sum(range(50))

    def test_stress_different_sizes(self):
        """
        Test: Allocate lists of various sizes repeatedly.

        Stresses both allocation and deallocation paths.
        """
        sizes = [1, 10, 100, 1000, 100, 10, 1, 50, 500]
        for _ in range(100):
            for size in sizes:
                lst = hellozig.make_list(size)
                assert len(lst) == size
                total = hellozig.sum_list(lst)
                assert total == sum(range(size))


class TestMemoryBehaviorCharacterization:
    """
    Tests to characterize memory behavior for debugging.

    If a leak exists, these tests may show it indirectly through:
    - Program behavior (none expected, but included for completeness)
    - System resource usage (can be monitored externally)
    """

    def test_correct_values_despite_potential_leak(self):
        """
        Verify correctness even if memory leaks exist.

        This ensures the functional aspect is correct, orthogonal to memory leaks.
        """
        for size in [1, 5, 10, 50, 100]:
            lst = hellozig.make_list(size)
            doubled = hellozig.double_list(lst)
            total = hellozig.sum_list(doubled)
            expected = 2 * sum(range(size))
            assert total == expected, f"Failed for size {size}: {total} != {expected}"

    def test_list_contents_preserved(self):
        """
        Verify list contents are correct through conversions.

        Even if memory leaks, contents should be correct.
        """
        original = [1, 2, 3, 4, 5]
        doubled = hellozig.double_list(original)
        assert doubled == [2, 4, 6, 8, 10]
        # And back again
        quadrupled = hellozig.double_list(doubled)
        assert quadrupled == [4, 8, 12, 16, 20]


# Instructions for running with valgrind on Linux:
#
# 1. Install valgrind:
#    sudo apt-get install valgrind
#
# 2. Run test with leak detection:
#    valgrind --leak-check=full --show-leak-kinds=all \
#    --log-file=valgrind_out.txt \
#    python -m pytest tests/test_memory_leak.py -v -s
#
# 3. Examine output:
#    - "definitely lost" = memory leaked (BAD)
#    - "indirectly lost" = memory leaked through pointers (BAD)
#    - "possibly lost" = might be leaked (depends on implementation)
#    - "still reachable" = leaked but program exited (often OK for one-time init)
#
# Expected output with proper fixes:
#    ERROR SUMMARY: 0 errors from 0 contexts (suppressed: X from X)
#
# Example valgrind output snippet to look for:
#    HEAP SUMMARY:
#        in use at exit: 0 bytes in 0 blocks
#    LEAK SUMMARY:
#        definitely lost: 0 bytes in 0 blocks
#        indirectly lost: 0 bytes in 0 blocks
#
# If you see numbers > 0 for "definitely lost" or "indirectly lost",
# there are memory leaks that need fixing.
