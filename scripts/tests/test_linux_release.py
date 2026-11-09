import importlib.util
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest
from unittest import mock

SPEC = importlib.util.spec_from_file_location("linux_release", Path(__file__).parents[1] / "linux-release.py")
release = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(release)
VERSION = "1.2.3"
TAG = "v1.2.3"
SHA = "a" * 40


class ReleaseTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.inputs = self.root / "artifacts"
        self.output = self.root / "release"
        for flavor in release.FLAVORS:
            directory = self.inputs / f"linux-{flavor}-amd64"
            directory.mkdir(parents=True)
            (directory / f"open-rdp-client_{VERSION}_amd64.deb").write_bytes(flavor.encode())

    def prepare(self):
        fields = ["Package: open-rdp-client", f"Version: {VERSION}", "Architecture: amd64"]
        with mock.patch.object(release, "package_metadata", return_value=fields):
            release.stage(self.inputs, self.output, VERSION, SHA)

    def test_stages_distinct_distro_packages_and_verified_checksums(self):
        self.prepare()
        names = release.package_names(VERSION)
        self.assertNotEqual(names[0], names[1])
        self.assertEqual((self.output / names[0]).read_bytes(), b"ubuntu24")
        self.assertEqual((self.output / names[1]).read_bytes(), b"debian13")
        self.assertEqual((self.output / release.COMMIT_FILE).read_text(), SHA + "\n")
        for line in (self.output / release.CHECKSUM_FILE).read_text().splitlines():
            checksum, name = line.split("  ")
            self.assertEqual(checksum, release.digest(self.output / name))

    def test_missing_or_wrong_package_fails_before_staging(self):
        fields = ["Package: open-rdp-client", "Version: 9.9.9", "Architecture: amd64"]
        with mock.patch.object(release, "package_metadata", return_value=fields):
            with self.assertRaisesRegex(ValueError, "Unexpected package metadata"):
                release.stage(self.inputs, self.output, VERSION, SHA)
        self.assertFalse(self.output.exists())
        shutil.rmtree(self.inputs)
        with self.assertRaisesRegex(ValueError, "Missing tested package"):
            release.stage(self.inputs, self.output, VERSION, SHA)
        self.assertFalse(self.output.exists())

    def test_release_tags_must_be_stable_versions(self):
        self.assertEqual(release.tag_version(TAG), VERSION)
        for invalid in ("main", "v1.2.3-rc1", "v01.2.3", "v1.2", "v1.2.3/extra"):
            with self.subTest(tag=invalid), self.assertRaises(ValueError):
                release.tag_version(invalid)

    def test_tag_version_notes_and_commit_are_required(self):
        manifest = self.root / "ubuntu-touch/packaging/manifest.json.in"
        manifest.parent.mkdir(parents=True)
        manifest.write_text('{"version":"1.2.3"}')
        with mock.patch.object(release, "ROOT", self.root):
            with self.assertRaisesRegex(ValueError, "does not match"):
                release.validate_source("v2.0.0")
            with self.assertRaisesRegex(ValueError, "notes are missing"):
                release.validate_source(TAG)
            notes = self.root / f"docs/releases/{VERSION}.md"
            notes.parent.mkdir(parents=True)
            notes.write_text("Release notes")
            with mock.patch.object(release.subprocess, "run"), mock.patch.object(release, "run", side_effect=[SHA, "b" * 40]):
                with self.assertRaisesRegex(ValueError, "does not match the release tag"):
                    release.validate_source(TAG)
            with mock.patch.object(release.subprocess, "run"), mock.patch.object(release, "run", return_value=SHA):
                self.assertEqual(release.validate_source(TAG), (VERSION, SHA))

    def fake_github(self, existing=None, remote_sha=SHA, list_error=False):
        assets = dict(existing or {})
        mutations = []

        def api(repo, endpoint, *args):
            if endpoint.startswith("git/ref/tags/"):
                return {"object": {"type": "tag", "sha": "annotated-tag"}}
            if endpoint == "git/tags/annotated-tag":
                return {"object": {"type": "commit", "sha": remote_sha}}
            if list_error:
                raise subprocess.CalledProcessError(1, ["gh", "api"])
            return [[{"tag_name": TAG, "assets": [{"name": name} for name in assets]}]] if existing is not None else [[]]

        def gh(repo, *args):
            if args[1] == "download":
                name = args[args.index("--pattern") + 1]
                destination = Path(args[args.index("--dir") + 1])
                (destination / name).write_bytes(assets[name])
            elif args[1] in ("create", "upload"):
                mutations.append(args)
                paths = args[3:args.index("--verify-tag")] if args[1] == "create" else args[3:]
                for path in paths:
                    path = Path(path)
                    assets[path.name] = path.read_bytes()
            return "https://github.com/example/repo/releases/tag/" + TAG

        return api, gh, mutations, assets

    def publish(self, existing=None, **options):
        api, gh, mutations, assets = self.fake_github(existing, **options)
        with mock.patch.object(release, "api", side_effect=api), mock.patch.object(release, "gh", side_effect=gh), mock.patch("builtins.print"):
            release.publish("example/repo", TAG, self.output, VERSION, SHA)
        return mutations, assets

    def test_new_release_uses_existing_tag_and_notes_then_verifies_downloads(self):
        self.prepare()
        mutations, assets = self.publish()
        self.assertEqual(len(mutations), 1)
        self.assertEqual(mutations[0][:3], ("release", "create", TAG))
        self.assertIn("--verify-tag", mutations[0])
        self.assertIn("--notes-file", mutations[0])
        self.assertNotIn("--clobber", mutations[0])
        self.assertEqual(len(assets), 4)

    def test_existing_identical_assets_are_not_uploaded_again(self):
        self.prepare()
        existing = {path.name: path.read_bytes() for path in self.output.iterdir()}
        mutations, _ = self.publish(existing)
        self.assertEqual(mutations, [])

    def test_partial_release_uploads_only_missing_assets(self):
        self.prepare()
        first = self.output / release.package_names(VERSION)[0]
        mutations, assets = self.publish({first.name: first.read_bytes(), "phone.click": b"keep"})
        self.assertEqual(len(mutations), 1)
        self.assertEqual(mutations[0][:3], ("release", "upload", TAG))
        self.assertNotIn(str(first), mutations[0])
        self.assertEqual(assets["phone.click"], b"keep")
        self.assertEqual(len(assets), 5)

    def test_existing_conflict_or_different_manual_source_fails_before_upload(self):
        self.prepare()
        for existing in ({release.package_names(VERSION)[0]: b"different"}, {"RELEASE_COMMIT": b"different source"}):
            api, gh, mutations, _ = self.fake_github(existing)
            with mock.patch.object(release, "api", side_effect=api), mock.patch.object(release, "gh", side_effect=gh):
                with self.assertRaises(ValueError):
                    release.publish("example/repo", TAG, self.output, VERSION, SHA)
            self.assertEqual(mutations, [])

    def test_remote_failure_or_moved_tag_never_creates_release(self):
        self.prepare()
        for options in ({"remote_sha": "b" * 40}, {"list_error": True}):
            api, gh, mutations, _ = self.fake_github(**options)
            with mock.patch.object(release, "api", side_effect=api), mock.patch.object(release, "gh", side_effect=gh):
                with self.assertRaises((ValueError, subprocess.CalledProcessError)):
                    release.publish("example/repo", TAG, self.output, VERSION, SHA)
            self.assertEqual(mutations, [])

    def test_corrupt_download_fails_publication_verification(self):
        self.prepare()
        api, gh, _, _ = self.fake_github()

        def corrupted_download(repo, *args):
            result = gh(repo, *args)
            if args[1] == "download":
                directory = Path(args[args.index("--dir") + 1])
                name = args[args.index("--pattern") + 1]
                (directory / name).write_bytes(b"corrupt download")
            return result

        with mock.patch.object(release, "api", side_effect=api), mock.patch.object(release, "gh", side_effect=corrupted_download):
            with self.assertRaisesRegex(ValueError, "Published asset verification failed"):
                release.publish("example/repo", TAG, self.output, VERSION, SHA)

    def test_corrupt_bundle_fails_before_remote_calls(self):
        self.prepare()
        (self.output / release.package_names(VERSION)[0]).write_bytes(b"corrupt")
        with mock.patch.object(release, "api") as api:
            with self.assertRaisesRegex(ValueError, "checksums"):
                release.publish("example/repo", TAG, self.output, VERSION, SHA)
        api.assert_not_called()


if __name__ == "__main__":
    unittest.main()
