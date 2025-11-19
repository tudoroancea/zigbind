import pytest
import sys
import os

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "zig-out", "lib"))


@pytest.fixture(scope="session")
def test_mod():
    """Load test_containers module after build."""
    import importlib.util
    lib_path = os.path.join(os.path.dirname(__file__), "zig-out", "lib")
    spec = importlib.util.spec_from_file_location("test_containers", os.path.join(lib_path, "test_containers.abi3.so"))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod



class TestListBasics:
    def test_sum_empty(self, test_mod):
        assert test_mod.sum_list([]) == 0

    def test_sum_single(self, test_mod):
        assert test_mod.sum_list([42]) == 42

    def test_sum_multiple(self, test_mod):
        assert test_mod.sum_list([1, 2, 3, 4, 5]) == 15

    def test_sum_negative(self, test_mod):
        assert test_mod.sum_list([-5, 10, -3, 8]) == 10


class TestListReturns:
    def test_make_list_zero(self, test_mod):
        assert test_mod.make_list(0) == []

    def test_make_list_small(self, test_mod):
        assert test_mod.make_list(5) == [0, 1, 2, 3, 4]

    def test_make_list_large(self, test_mod):
        result = test_mod.make_list(100)
        assert result == list(range(100))


class TestListTransformations:
    def test_double_empty(self, test_mod):
        assert test_mod.double_list([]) == []

    def test_double_single(self, test_mod):
        assert test_mod.double_list([5]) == [10]

    def test_double_multiple(self, test_mod):
        assert test_mod.double_list([1, 2, 3, 4, 5]) == [2, 4, 6, 8, 10]

    def test_double_negatives(self, test_mod):
        assert test_mod.double_list([-5, -2, 0, 3]) == [-10, -4, 0, 6]


class TestListErrors:
    def test_wrong_element_type(self, test_mod):
        with pytest.raises((TypeError, ValueError)):
            test_mod.sum_list(["a", "b", "c"])

    def test_mixed_types(self, test_mod):
        with pytest.raises((TypeError, ValueError)):
            test_mod.sum_list([1, 2.5, 3])

    def test_wrong_container_type(self, test_mod):
        with pytest.raises((TypeError, ValueError)):
            test_mod.sum_list({"a": 1})


class TestListIntegration:
    def test_make_double_sum(self, test_mod):
        created = test_mod.make_list(5)
        doubled = test_mod.double_list(created)
        total = test_mod.sum_list(doubled)
        assert total == 20

    def test_sum_then_make(self, test_mod):
        original = [1, 2, 3, 4, 5]
        total = test_mod.sum_list(original)
        new_list = test_mod.make_list(total)
        assert len(new_list) == 15
        assert new_list == list(range(15))

    def test_double_double(self, test_mod):
        original = [1, 2, 3]
        first = test_mod.double_list(original)
        second = test_mod.double_list(first)
        assert second == [4, 8, 12]
