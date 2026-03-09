#!/bin/bash
# Build/rebuild onnxruntime from source (RelWithDebInfo, pybind, skip tests)

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

python3 "$DIR/tools/ci_build/build.py" \
    --build_dir "$DIR/build/Linux" \
    --config RelWithDebInfo \
    --skip_tests \
    --enable_pybind \
    "$@"
