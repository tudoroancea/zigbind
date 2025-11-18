"""
Test suite for zigbind ergonomic function API.
Tests type conversion, error handling, and basic function bindings.
"""

import pytest
import sys
import os

# Add hellozig to path
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "examples", "hellozig", "zig-out", "lib"))

import hellozig


class TestBasicTypes:
    """Test basic type conversions."""

    def test_no_args_string_return(self):
        """Test function with no arguments returning string."""
        result = hellozig.hello()
        assert result == "Hello from Zig!"
        assert isinstance(result, str)

    def test_string_parameter(self):
        """Test function with string parameter."""
        result = hellozig.greet("Python")
        assert result == "Python"
        assert isinstance(result, str)

    def test_empty_string(self):
        """Test empty string handling."""
        result = hellozig.greet("")
        assert result == ""

    def test_unicode_string(self):
        """Test Unicode string handling."""
        result = hellozig.greet("世界")  # "World" in Chinese
        assert result == "世界"


class TestNumericTypes:
    """Test numeric type conversions."""

    def test_int_addition(self):
        """Test integer parameters and return."""
        result = hellozig.add(5, 3)
        assert result == 8
        assert isinstance(result, int)

    def test_int_negative(self):
        """Test negative integers."""
        result = hellozig.add(-5, 3)
        assert result == -2

    def test_int_zero(self):
        """Test zero."""
        result = hellozig.add(0, 0)
        assert result == 0

    def test_float_multiplication(self):
        """Test float parameters and return."""
        result = hellozig.multiply(3.14, 2.0)
        assert abs(result - 6.28) < 1e-10
        assert isinstance(result, float)

    def test_float_from_int(self):
        """Test that integers can be passed to float parameters."""
        result = hellozig.multiply(3, 2)
        assert result == 6.0


class TestBooleans:
    """Test boolean type conversions."""

    def test_is_positive_true(self):
        """Test boolean return - true case."""
        result = hellozig.is_positive(5)
        assert result is True
        assert isinstance(result, bool)

    def test_is_positive_false(self):
        """Test boolean return - false case."""
        result = hellozig.is_positive(-3)
        assert result is False

    def test_is_positive_zero(self):
        """Test boolean return - zero."""
        result = hellozig.is_positive(0)
        assert result is False


class TestErrorHandling:
    """Test error propagation from Zig to Python."""

    def test_error_union_normal_case(self):
        """Test error union function with valid input."""
        result = hellozig.divide(10.0, 2.0)
        assert result == 5.0

    def test_error_union_error_case(self):
        """Test error union function that raises exception."""
        with pytest.raises(ValueError):
            hellozig.divide(10.0, 0.0)

    def test_error_message(self):
        """Test that error message is set."""
        try:
            hellozig.divide(10.0, 0.0)
            pytest.fail("Expected ValueError to be raised")
        except ValueError as e:
            # Error message should be set
            assert str(e) == "ValueError"


class TestEdgeCases:
    """Test edge cases and boundary conditions."""

    def test_very_long_string(self):
        """Test with a very long string."""
        long_str = "x" * 10000
        result = hellozig.greet(long_str)
        assert result == long_str
        assert len(result) == 10000

    def test_large_integers(self):
        """Test with large integers."""
        # i32 max is 2147483647
        result = hellozig.add(2147483647, 0)
        assert result == 2147483647

    def test_large_floats(self):
        """Test with large floats."""
        result = hellozig.multiply(1e100, 1e100)
        assert result == 1e200


class TestTypeErrors:
    """Test that type errors are properly raised."""

    def test_wrong_argument_count_too_few(self):
        """Test calling with too few arguments."""
        with pytest.raises(TypeError):
            hellozig.add(5)  # Missing second argument

    def test_wrong_argument_count_too_many(self):
        """Test calling with too many arguments."""
        with pytest.raises(TypeError):
            hellozig.add(5, 3, 2)  # Too many arguments

    def test_wrong_type_for_int(self):
        """Test passing wrong type to integer parameter."""
        with pytest.raises(TypeError):
            hellozig.add("not", "numbers")

    def test_wrong_type_for_string(self):
        """Test passing wrong type to string parameter."""
        with pytest.raises(TypeError):
            hellozig.greet(123)  # Should be string


if __name__ == "__main__":
    pytest.main([__file__, "-v"])
