#!/usr/bin/env python3
"""Verify the live OpenStore release and both downloads against local .click files.

Run with the Python environment containing Clickable (which supplies requests).
"""

import argparse
import hashlib
from pathlib import Path
import sys

import requests


APP_ID = "rdp-client-ut.zzvvmm"
PUBLIC_API = f"https://open-store.io/api/v3/apps/{APP_ID}"


def digest_file(path):
    result = hashlib.sha512()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            result.update(chunk)
    return result.hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("version")
    parser.add_argument("--packages-dir", required=True, type=Path)
    args = parser.parse_args()
    with requests.get(PUBLIC_API, timeout=(10, 30)) as response:
        response.raise_for_status()
        payload = response.json()
    if not payload.get("success"):
        raise ValueError("OpenStore metadata request was unsuccessful")
    data = payload["data"]
    if not data["published"] or data["version"] != args.version:
        raise ValueError(f"Expected published latest version {args.version}; found {data['version']}")

    for arch in ("amd64", "arm64"):
        revisions = [r for r in data["revisions"] if r["version"] == args.version
                     and r["architecture"] == arch and r["channel"] == "focal"
                     and r["framework"] == "ubuntu-touch-24.04-1.x"]
        if len(revisions) != 1:
            raise ValueError(f"Expected one {args.version} revision for {arch}; found {len(revisions)}")
        revision = revisions[0]
        package = args.packages_dir / f"{APP_ID}_{args.version}_{arch}.click"
        local_hash = digest_file(package)
        if revision["download_sha512"] != local_hash:
            raise ValueError(f"{arch}: store checksum differs from {package}")
        downloaded_hash = hashlib.sha512()
        with requests.get(revision["download_url"], stream=True, timeout=(10, 60)) as download:
            download.raise_for_status()
            for chunk in download.iter_content(1024 * 1024):
                downloaded_hash.update(chunk)
        if downloaded_hash.hexdigest() != local_hash:
            raise ValueError(f"{arch}: public download differs from local package")
        print(f"Verified {arch} {args.version}: revision {revision['revision']}, SHA-512 matches")
    print(f"Screenshots: {len(data['screenshots'])}")
    print(f"Listing: https://open-store.io/app/{APP_ID}/")


if __name__ == "__main__":
    try:
        main()
    except requests.RequestException as error:
        sys.exit("OpenStore request failed: " + type(error).__name__)
    except (OSError, ValueError, KeyError) as error:
        sys.exit(str(error))
