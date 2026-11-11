#!/bin/sh
# Prepare a relocatable CPython runtime inside build/. No system Python packages are changed.
set -eu
cd "$(dirname "$0")"
mkdir -p build
if ! command -v uv >/dev/null 2>&1; then
    python3 -m venv build/uv-bootstrap
    build/uv-bootstrap/bin/python -m pip install 'uv==0.13.1'
    uv_cmd="$PWD/build/uv-bootstrap/bin/uv"
else
    uv_cmd=$(command -v uv)
fi
"$uv_cmd" python install 3.13.16 --install-dir "$PWD/build/astronomy-python" --no-bin --no-registry --cache-dir "$PWD/build/uv-cache"
base=$(find build/astronomy-python -maxdepth 1 -type d -name 'cpython-3.13.16-*' | head -n 1)
[ -n "$base" ] || { echo 'Portable Python installation not found' >&2; exit 1; }
if [ ! -f build/astronomy-runtime/.portable-astronomy ]; then
    rm -rf build/astronomy-runtime
    cp -R "$base" build/astronomy-runtime
    touch build/astronomy-runtime/.portable-astronomy
fi
"$uv_cmd" pip install --python "$PWD/build/astronomy-runtime/bin/python3" --system --break-system-packages --cache-dir "$PWD/build/uv-cache" -r Resources/Astronomy/requirements.txt
mkdir -p build/astronomy-data
kernel="build/astronomy-data/de440s.bsp"
expected="c1c7feeab882263fc493a9d5a5b2ddd71b54826cdf65d8d17a76126b260a49f2"
if [ ! -f "$kernel" ]; then
    curl --fail --location --retry 2 --output "$kernel.download" https://naif.jpl.nasa.gov/pub/naif/generic_kernels/spk/planets/de440s.bsp
    mv "$kernel.download" "$kernel"
fi
actual=$(shasum -a 256 "$kernel" | awk '{ print $1 }')
[ "$actual" = "$expected" ] || { echo 'JPL DE440s checksum mismatch; remove build/astronomy-data/de440s.bsp and rerun.' >&2; exit 1; }
build/astronomy-runtime/bin/python3 -I Resources/Astronomy/engine.py --registry > Resources/Astronomy/methods.json
build/astronomy-runtime/bin/python3 -I Resources/Astronomy/write_reference.py
printf '%s\n' 'Astronomy runtime and registry ready.'
