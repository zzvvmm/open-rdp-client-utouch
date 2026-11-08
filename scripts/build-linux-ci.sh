#!/bin/sh
set -eu
flavor=${1:?Usage: build-linux-ci.sh ubuntu24|debian13}
case "$flavor" in ubuntu24|debian13) ;; *) echo "Unsupported build flavor" >&2; exit 1;; esac
build_dir="build/linux-$flavor"
python3 scripts/release-version.py --check
cmake -S . -B "$build_dir" -G Ninja -DOPEN_RDP_PLATFORM=linux -DCMAKE_BUILD_TYPE=Release
cmake --build "$build_dir" -j2
xvfb-run -a ctest --test-dir "$build_dir" --output-on-failure
cpack --config "$build_dir/CPackConfig.cmake" -G DEB
desktop-file-validate linux/packaging/open-rdp-client.desktop
