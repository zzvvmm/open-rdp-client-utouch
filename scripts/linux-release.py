#!/usr/bin/env python3
"""Validate, stage, and publish tested Linux packages from a tagged CI run."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
FLAVORS = ("ubuntu24", "debian13")
COMMIT_FILE = "LINUX_RELEASE_COMMIT"
CHECKSUM_FILE = "SHA256SUMS-linux"


def run(*args):
    return subprocess.check_output(args, text=True, cwd=ROOT).strip()


def tag_version(tag):
    if not re.fullmatch(r"v(?:0|[1-9]\d*)\.(?:0|[1-9]\d*)\.(?:0|[1-9]\d*)", tag):
        raise ValueError("Release tags must be stable vX.Y.Z versions")
    return tag[1:]


def validate_source(tag=None):
    version = json.loads((ROOT / "ubuntu-touch/packaging/manifest.json.in").read_text())["version"]
    command = ["python3", "scripts/release-version.py", "--check"]
    if tag:
        expected = tag_version(tag)
        command += ["--expect", expected]
        if version != expected:
            raise ValueError(f"Tag {tag} does not match application version {version}")
        notes = ROOT / "docs/releases" / f"{version}.md"
        if not notes.is_file() or not notes.read_text().strip():
            raise ValueError(f"Release notes are missing or empty: {notes}")
    subprocess.run(command, check=True, cwd=ROOT)
    sha = run("git", "rev-parse", "HEAD")
    if tag and run("git", "rev-parse", "--verify", f"refs/tags/{tag}^{{commit}}") != sha:
        raise ValueError("The checked-out source does not match the release tag")
    return version, sha


def package_names(version):
    return [f"open-rdp-client_{version}_{flavor}_amd64.deb" for flavor in FLAVORS]


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def package_metadata(path):
    return run("dpkg-deb", "--field", str(path), "Package", "Version", "Architecture").splitlines()


def stage(artifacts, destination, version, sha):
    packages = []
    for flavor, name in zip(FLAVORS, package_names(version)):
        source = artifacts / f"linux-{flavor}-amd64" / f"open-rdp-client_{version}_amd64.deb"
        if not source.is_file():
            raise ValueError(f"Missing tested package: {source}")
        # dpkg-deb labels fields when more than one field is requested.
        fields = dict(line.split(": ", 1) for line in package_metadata(source))
        if fields != {"Package": "open-rdp-client", "Version": version, "Architecture": "amd64"}:
            raise ValueError(f"Unexpected package metadata in {source}: {fields}")
        packages.append((source, name))
    destination.mkdir(parents=True, exist_ok=True)
    for source, name in packages:
        shutil.copyfile(source, destination / name)
    (destination / COMMIT_FILE).write_text(sha + "\n")
    names = sorted(package_names(version) + [COMMIT_FILE])
    (destination / CHECKSUM_FILE).write_text("".join(f"{digest(destination / name)}  {name}\n" for name in names))


def gh(repo, *args):
    return run("gh", *args, "--repo", repo)


def api(repo, endpoint, *args):
    # gh api uses an explicit endpoint, rather than the release commands' --repo.
    return json.loads(run("gh", "api", f"repos/{repo}/{endpoint}", *args))


def verify_remote_tag(repo, tag, sha):
    obj = api(repo, f"git/ref/tags/{tag}")["object"]
    while obj["type"] == "tag":
        obj = api(repo, f"git/tags/{obj['sha']}")["object"]
    if obj["type"] != "commit" or obj["sha"] != sha:
        raise ValueError("The remote release tag no longer matches the tested source")


def download(repo, tag, name, destination):
    gh(repo, "release", "download", tag, "--pattern", name, "--dir", str(destination))
    return destination / name


def publish(repo, tag, directory, version, sha):
    names = sorted(package_names(version) + [COMMIT_FILE, CHECKSUM_FILE])
    files = [directory / name for name in names]
    if not all(path.is_file() for path in files):
        raise ValueError("The Linux release bundle is incomplete")
    if (directory / COMMIT_FILE).read_text().strip() != sha:
        raise ValueError("The Linux release bundle has a different source commit")
    expected = "".join(f"{digest(directory / name)}  {name}\n" for name in sorted(package_names(version) + [COMMIT_FILE]))
    if (directory / CHECKSUM_FILE).read_text() != expected:
        raise ValueError("The Linux release checksums do not match the staged files")
    verify_remote_tag(repo, tag, sha)
    pages = api(repo, "releases?per_page=100", "--paginate", "--slurp")
    release = next((release for page in pages for release in page if release["tag_name"] == tag), None)
    if release:
        existing = {asset["name"] for asset in release["assets"]}
        with tempfile.TemporaryDirectory() as temporary:
            temporary = Path(temporary)
            # Preserve the source recorded by the manual Ubuntu Touch workflow too.
            if "RELEASE_COMMIT" in existing:
                recorded = download(repo, tag, "RELEASE_COMMIT", temporary).read_text().strip()
                if recorded != sha:
                    raise ValueError("The existing release records a different source commit")
            for path in files:
                if path.name in existing:
                    remote = download(repo, tag, path.name, temporary)
                    if digest(remote) != digest(path):
                        raise ValueError(f"Existing release asset differs: {path.name}; refusing to replace it")
        missing = [str(path) for path in files if path.name not in existing]
        if missing:
            gh(repo, "release", "upload", tag, *missing)
    else:
        gh(repo, "release", "create", tag, *map(str, files), "--verify-tag", "--target", sha,
           "--title", f"Open RDP Client {tag}", "--notes-file", str(ROOT / "docs/releases" / f"{version}.md"))
    # Verify downloaded bytes, including on a resumed upload. Never use --clobber.
    with tempfile.TemporaryDirectory() as temporary:
        temporary = Path(temporary)
        for path in files:
            remote = download(repo, tag, path.name, temporary)
            if digest(remote) != digest(path):
                raise ValueError(f"Published asset verification failed: {path.name}")
    print(gh(repo, "release", "view", tag, "--json", "url", "--jq", ".url"))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    validate = commands.add_parser("validate")
    validate.add_argument("--tag", default="")
    prepare = commands.add_parser("stage")
    prepare.add_argument("--tag", required=True)
    prepare.add_argument("--artifacts", required=True, type=Path)
    prepare.add_argument("--output", required=True, type=Path)
    upload = commands.add_parser("publish")
    upload.add_argument("--tag", required=True)
    upload.add_argument("--repo", required=True)
    upload.add_argument("--assets", required=True, type=Path)
    args = parser.parse_args()
    version, sha = validate_source(args.tag)
    if args.command == "validate":
        if os.environ.get("GITHUB_OUTPUT"):
            with open(os.environ["GITHUB_OUTPUT"], "a") as output:
                output.write(f"version={version}\nsource_sha={sha}\n")
    elif args.command == "stage":
        stage(args.artifacts.resolve(), args.output.resolve(), version, sha)
    else:
        publish(args.repo, args.tag, args.assets.resolve(), version, sha)


if __name__ == "__main__":
    main()
