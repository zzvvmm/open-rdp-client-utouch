#!/usr/bin/env python3
"""Build the pure-Rust IronRDP backend static library for the target Ubuntu Touch architecture."""
import os
import subprocess
import sys

target_dir, rust_target, cxx_compiler = sys.argv[1:4]
env = dict(os.environ)
env.pop("MAKEFLAGS", None)
env.pop("CARGO_MAKEFLAGS", None)
env.pop("MFLAGS", None)
env["CARGO_TARGET_DIR"] = target_dir
env["PKG_CONFIG_ALLOW_CROSS"] = "1"

# Ensure /opt/rust/cargo/bin is on PATH inside Clickable containers
opt_rust_bin = "/opt/rust/cargo/bin"
if os.path.isdir(opt_rust_bin):
    env["PATH"] = opt_rust_bin + os.pathsep + env.get("PATH", "")

cc_compiler = cxx_compiler.replace("g++", "gcc").replace("clang++", "clang")
if cc_compiler.endswith("/c++"):
    cc_compiler = cc_compiler[:-3] + "cc"

target_underscored = rust_target.replace("-", "_")
target_upper = target_underscored.upper()
env[f"CC_{target_underscored}"] = cc_compiler
env[f"CXX_{target_underscored}"] = cxx_compiler
env[f"CARGO_TARGET_{target_upper}_LINKER"] = cc_compiler

cmd = [
    "cargo",
    "build",
    "--locked",
    "--release",
    "--lib",
    "--target",
    rust_target,
]
subprocess.run(cmd, env=env, check=True)
