#!/usr/bin/env python3
"""Check or update the six application version fields without changing dependencies."""

import argparse
import json
from pathlib import Path
import re
import sys


VERSION = r"(?:0|[1-9]\d*)\.(?:0|[1-9]\d*)\.(?:0|[1-9]\d*)"
FIELD = rf'(?P<version>{VERSION})'
FIELDS = {
    "Cargo.toml": rf'(?ms)^\[package\]\n(?:(?!^\[).)*?^version = "{FIELD}"',
    "Cargo.lock": rf'(?m)^name = "rdp-client-ut"\nversion = "{FIELD}"',
    "CMakeLists.txt": rf'project\(rdp-client-ut VERSION {FIELD} LANGUAGES CXX\)',
    "manifest.json.in": rf'"version":\s*"{FIELD}"',
    "qml/pages/SettingsPage.qml": rf'Version {FIELD} • License:',
    "po/rdp-client-ut.pot": rf'Project-Id-Version: rdp-client-ut\.zzvvmm {FIELD}\\n',
}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("version", nargs="?", help="New stable X.Y.Z version; omitted to check")
    parser.add_argument("--check", action="store_true", help="Check consistency without writing")
    parser.add_argument("--expect", help="Also require this version when checking")
    args = parser.parse_args()
    if args.version and (args.check or args.expect):
        parser.error("Use a new version OR --check [--expect X.Y.Z]")
    for value in (args.version, args.expect):
        if value and not re.fullmatch(VERSION, value):
            parser.error("Versions must be stable X.Y.Z numbers without a v prefix")

    root = Path(__file__).resolve().parents[1]
    if json.loads((root / "manifest.json.in").read_text())["name"] != "rdp-client-ut.zzvvmm":
        raise ValueError("Unexpected application ID")

    fields = []
    for filename, pattern in FIELDS.items():
        path = root / filename
        content = path.read_text()
        matches = list(re.finditer(pattern, content))
        if len(matches) != 1:
            raise ValueError(f"Expected one application version in {filename}; found {len(matches)}")
        fields.append((path, content, matches[0]))

    versions = {match.group("version") for _, _, match in fields}
    if len(versions) != 1:
        details = ", ".join(f"{p.relative_to(root)}={m.group('version')}" for p, _, m in fields)
        raise ValueError("Version fields disagree: " + details)
    current = versions.pop()
    if args.expect and current != args.expect:
        raise ValueError(f"Expected {args.expect}, found {current}")
    if not args.version:
        print(f"Version {current} is consistent across all six files")
        return
    if tuple(map(int, args.version.split('.'))) <= tuple(map(int, current.split('.'))):
        raise ValueError(f"New version must be greater than {current}")

    # Validate every field before writing; replace only the application's version.
    for path, content, match in fields:
        start, end = match.span("version")
        path.write_text(content[:start] + args.version + content[end:])
    print(f"Updated all six version fields: {current} -> {args.version}")


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, KeyError) as error:
        sys.exit(str(error))
