#!/usr/bin/env python3
"""Run Lomiri regressions and the shared component tests in Clickable."""
import subprocess

for suite in ("ubuntu-touch/tests/qml", "open-rdp-client/tests/qml"):
    subprocess.run([
        "qmltestrunner", "-import", "open-rdp-client/qml", "-import",
        "ubuntu-touch/tests/qml/mocks", "-input", suite,
    ], check=True)
