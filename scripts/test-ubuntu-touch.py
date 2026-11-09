#!/usr/bin/env python3
"""Run Lomiri regressions and the shared component tests in Clickable."""
import subprocess
from pathlib import Path

for suite in ("ubuntu-touch/tests/qml", "open-rdp-client/tests/qml"):
    subprocess.run([
        "qmltestrunner", "-import", "open-rdp-client/qml", "-import",
        "ubuntu-touch/tests/qml/mocks", "-input", suite,
    ], check=True)

# Exercise packaged resources with the real Qt 5 frontend, independently of the
# QML test bridge. Clickable has already provided Xvfb and Mesa for this command.
executable = Path("build/x86_64-linux-gnu/app/install/rdp-client-ut").resolve()
if not executable.is_file():
    raise SystemExit("Build the amd64 Click package before running installed UI checks")
for theme, layout, size, name in (
    ("dark", "grid", "390x844", "dark-portrait"),
    ("light", "grid", "390x844", "light-portrait"),
    ("dark", "grid", "820x450", "dark-landscape"),
    ("light", "list", "390x844", "light-list"),
    ("light", "list", "390x844", "large-text"),
):
    command = [
        "python3", "scripts/smoke-linux.py", "--executable", str(executable),
        "--platform", "ubuntu-touch", "--theme", theme, "--layout", layout,
        "--size", size, "--library-fixture", "--snapshot-prefix",
        f"build/ui/ubuntu-touch/{name}",
    ]
    if name == "large-text":
        command += ["--font-scale", "1.5"]
    subprocess.run(command, check=True)
