# Zigbind

```bash
# build python bindings from zig code
zig build -Dpython_prefix=$(uv run --no-project python -c 'import sys; print(sys.base_prefix)')
# call the bindings from a python script
PYTHONPATH=./zig-out/lib uv run --no-project demo.py
```
