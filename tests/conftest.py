import subprocess
import sys
import os

def build_test_modules():
    result = subprocess.run(["zig", "build", f"-Dpython_prefix={sys.base_prefix}"], cwd=os.path.dirname(__file__) or ".", capture_output=True, text=True)
    if result.returncode != 0:
        raise RuntimeError(f"Zig build failed: {result.stderr}")

# Hook that runs before pytest collection
def pytest_configure(config):
    """Build test modules before pytest starts collecting tests."""
    print("building zig modules")
    build_test_modules()
