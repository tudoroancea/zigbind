import pytest
import sys
import os

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "zig-out", "lib"))


@pytest.fixture(scope="session")
def test_mod():
    """Load test_functions module after build."""
    import importlib.util
    lib_path = os.path.join(os.path.dirname(__file__), "zig-out", "lib")
    spec = importlib.util.spec_from_file_location("test_functions", os.path.join(lib_path, "test_functions.abi3.so"))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


class TestBasicTypes:
    def test_string_return(self, test_mod):
        assert test_mod.hello() == "Hello from Zig!"

    def test_string_parameter(self, test_mod):
        assert test_mod.greet("Python") == "Python"
        assert test_mod.greet("") == ""
        assert test_mod.greet("世界") == "世界"


class TestNumericTypes:
    def test_int_add(self, test_mod):
        assert test_mod.add(5, 3) == 8
        assert test_mod.add(-5, 10) == 5
        assert test_mod.add(0, 0) == 0

    def test_float_multiply(self, test_mod):
        result = test_mod.multiply(2.5, 4.0)
        assert abs(result - 10.0) < 1e-10
        result = test_mod.multiply(5, 2)
        assert abs(result - 10.0) < 1e-10


class TestBooleans:
    def test_is_positive(self, test_mod):
        assert test_mod.is_positive(5) is True
        assert test_mod.is_positive(-3) is False
        assert test_mod.is_positive(0) is False


class TestErrorHandling:
    def test_divide_success(self, test_mod):
        result = test_mod.divide(10.0, 2.0)
        assert abs(result - 5.0) < 1e-10

    def test_divide_error(self, test_mod):
        with pytest.raises(ValueError):
            test_mod.divide(10.0, 0.0)


class TestEdgeCases:
    def test_large_string(self, test_mod):
        s = "x" * 10000
        assert test_mod.greet(s) == s

    # def test_large_integer(self, test_mod):
    #     assert test_mod.add(2**30, 2**30) == 2**31 - 1

    def test_large_float(self, test_mod):
        assert test_mod.multiply(1e100, 1e100) == 1e200


class TestTypeErrors:
    def test_wrong_arg_count_few(self, test_mod):
        with pytest.raises(TypeError):
            test_mod.add(5)

    def test_wrong_arg_count_many(self, test_mod):
        with pytest.raises(TypeError):
            test_mod.add(5, 3, 1)

    def test_wrong_type_int(self, test_mod):
        with pytest.raises(TypeError):
            test_mod.add("5", 3)

    def test_wrong_type_string(self, test_mod):
        with pytest.raises(TypeError):
            test_mod.greet(123)
