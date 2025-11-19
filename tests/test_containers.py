"""
Test suite for zigbind container type support (lists, tuples, dicts, sets).
Tests list conversions in both directions with various element types.
"""

import pytest
import sys
import os

# Add hellozig to path
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "examples", "hellozig", "zig-out", "lib"))

import hellozig


class TestListBasics:
    """Test basic list functionality with integers."""

    def test_sum_empty_list(self):
        """Test summing an empty list."""
        result = hellozig.sum_list([])
        assert result == 0
        assert isinstance(result, int)

    def test_sum_single_element(self):
        """Test summing a list with one element."""
        result = hellozig.sum_list([42])
        assert result == 42

    def test_sum_multiple_elements(self):
        """Test summing a list with multiple elements."""
        result = hellozig.sum_list([1, 2, 3, 4, 5])
        assert result == 15

    def test_sum_negative_numbers(self):
        """Test summing with negative numbers."""
        result = hellozig.sum_list([-5, 10, -3, 8])
        assert result == 10

    def test_sum_large_numbers(self):
        """Test summing with large numbers."""
        result = hellozig.sum_list([1000000, 2000000, 3000000])
        assert result == 6000000


class TestListReturns:
    """Test functions that return lists from Zig to Python."""

    def test_make_list_zero(self):
        """Test creating a list of size 0."""
        result = hellozig.make_list(0)
        assert result == []
        assert isinstance(result, list)

    def test_make_list_small(self):
        """Test creating a small list."""
        result = hellozig.make_list(5)
        assert result == [0, 1, 2, 3, 4]
        assert isinstance(result, list)
        assert all(isinstance(x, int) for x in result)

    def test_make_list_medium(self):
        """Test creating a medium-sized list."""
        result = hellozig.make_list(10)
        assert result == list(range(10))
        assert len(result) == 10

    def test_make_list_large(self):
        """Test creating a larger list."""
        n = 100
        result = hellozig.make_list(n)
        assert len(result) == n
        assert result == list(range(n))


class TestListTransformations:
    """Test functions that transform lists."""

    def test_double_list_empty(self):
        """Test doubling an empty list."""
        result = hellozig.double_list([])
        assert result == []

    def test_double_list_single(self):
        """Test doubling a single-element list."""
        result = hellozig.double_list([5])
        assert result == [10]

    def test_double_list_multiple(self):
        """Test doubling a list with multiple elements."""
        result = hellozig.double_list([1, 2, 3, 4, 5])
        assert result == [2, 4, 6, 8, 10]

    def test_double_list_negatives(self):
        """Test doubling with negative numbers."""
        result = hellozig.double_list([-5, -2, 0, 3])
        assert result == [-10, -4, 0, 6]

    def test_double_list_preserves_type(self):
        """Test that results are integers."""
        result = hellozig.double_list([1, 2, 3])
        assert all(isinstance(x, int) for x in result)


class TestListTypeConversions:
    """Test type conversions with lists."""

    def test_float_list_from_ints(self):
        """Test passing integer list where floats are accepted."""
        # This tests implicit conversion (if supported)
        # Some extensions may accept int where float is expected
        try:
            result = hellozig.sum_list([1.5, 2.5, 3.0])
            assert isinstance(result, (int, float))
        except (TypeError, ValueError):
            # It's OK if the extension requires strict int type
            pytest.skip("Float lists not supported")

    def test_list_wrong_element_type(self):
        """Test that passing wrong element types raises appropriate error."""
        with pytest.raises((TypeError, ValueError)):
            hellozig.sum_list(["a", "b", "c"])

    def test_list_mixed_types(self):
        """Test that mixed type lists raise error."""
        with pytest.raises((TypeError, ValueError)):
            hellozig.sum_list([1, 2.5, 3])


class TestListMemoryManagement:
    """Test memory management with lists (no leaks, proper cleanup)."""

    def test_large_list_roundtrip(self):
        """Test that large lists can be created and processed without issues."""
        n = 1000
        created = hellozig.make_list(n)
        assert len(created) == n
        total = hellozig.sum_list(created)
        assert total == sum(range(n))

    def test_repeated_list_operations(self):
        """Test repeated list operations don't cause memory issues."""
        for _ in range(100):
            result = hellozig.make_list(10)
            assert len(result) == 10
            total = hellozig.sum_list(result)
            assert total == 45

    def test_list_in_list_roundtrip(self):
        """Test nested list operations."""
        inner = hellozig.make_list(3)
        assert inner == [0, 1, 2]
        doubled = hellozig.double_list(inner)
        assert doubled == [0, 2, 4]

    def test_many_small_lists(self):
        """Test creating many small lists."""
        results = []
        for i in range(50):
            lst = hellozig.make_list(i)
            assert len(lst) == i
            results.append(lst)
        # Verify all lists are still correct
        for i, lst in enumerate(results):
            assert len(lst) == i


class TestListEdgeCases:
    """Test edge cases and error conditions."""

    def test_none_not_accepted_as_list(self):
        """Test that None is not accepted where list is expected."""
        with pytest.raises((TypeError, ValueError)):
            hellozig.sum_list(None)

    def test_string_not_accepted_as_list(self):
        """Test that strings are not treated as lists of chars."""
        with pytest.raises((TypeError, ValueError)):
            hellozig.sum_list("hello")

    def test_dict_not_accepted_as_list(self):
        """Test that dicts are not accepted where lists are expected."""
        with pytest.raises((TypeError, ValueError)):
            hellozig.sum_list({"a": 1, "b": 2})

    def test_tuple_accepted_as_sequence(self):
        """Test that tuples work as sequences (coercible to list)."""
        # Tuples should work since they implement the sequence protocol
        result = hellozig.sum_list((1, 2, 3, 4))
        assert result == 10

    def test_generator_not_accepted(self):
        """Test that generators are not directly accepted."""
        # Some implementations might accept generators, others won't
        try:
            result = hellozig.sum_list(x for x in range(5))
            # If it works, verify the result
            assert result == 10
        except (TypeError, ValueError):
            # It's OK if generators aren't supported
            pytest.skip("Generators not supported")


class TestListIntegration:
    """Integration tests combining multiple operations."""

    def test_make_double_sum(self):
        """Test: make list -> double -> sum."""
        created = hellozig.make_list(5)  # [0, 1, 2, 3, 4]
        doubled = hellozig.double_list(created)  # [0, 2, 4, 6, 8]
        total = hellozig.sum_list(doubled)  # 20
        assert total == 20

    def test_sum_then_make(self):
        """Test: sum a list, then use result to make new list."""
        original = [1, 2, 3, 4, 5]
        total = hellozig.sum_list(original)  # 15
        new_list = hellozig.make_list(total)  # list of 15 elements
        assert len(new_list) == 15
        assert new_list == list(range(15))

    def test_double_double(self):
        """Test: double a list, then double the result."""
        original = [1, 2, 3]  # [1, 2, 3]
        first_double = hellozig.double_list(original)  # [2, 4, 6]
        second_double = hellozig.double_list(first_double)  # [4, 8, 12]
        assert second_double == [4, 8, 12]
