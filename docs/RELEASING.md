# Development and release guide

Linux desktop build/package instructions and acceptance checks are in [LINUX.md](LINUX.md). CI builds and tests Ubuntu 24.04 and Debian 13 `.deb` artifacts and publishes them to GitHub Releases on stable version tags. Desktop uses manual package upgrades; the OpenStore publication steps below apply to Ubuntu Touch. Run commands from the repository root.

Use one version, one source commit, and the same two `.click` files for GitHub
and OpenStore. The commands below run from the repository root. `0.1.4` is an
example next version; check the repository and both services before choosing it.
Run each stage separately and stop if a command fails; this guide is not an
unattended shell script.

```text
feature branch → implement → test → pull request → main
release branch → version + notes + screenshots → pull request → main
green CI for that commit → build and test packages → tag
GitHub Release + both .click files → OpenStore arm64 + amd64 → verify downloads
```

## 1. Set up the tools

You need Git, Rust/Cargo, Python 3, Docker, Clickable, and GitHub CLI (`gh`).
ADB is useful for testing on an Ubuntu Touch device. This project uses Qt 5.15,
framework `ubuntu-touch-24.04-1.x`, and package ID `rdp-client-ut.zzvvmm`.

This workstation already has a Clickable virtual environment:

```bash
source ../click-env/bin/activate
clickable --version
docker info
gh auth status
```

On another machine, create an environment with `python3 -m venv ../click-env`,
activate it, and install `clickable-ut` with pip. Install GitHub CLI using its
[official instructions](https://cli.github.com/) and run `gh auth login` if needed.
The previous release used Clickable 8.10.0; inspect the current framework and
tool support before upgrading.

For OpenStore, use the existing `OPENSTORE_API_KEY` environment variable or load
the key from your secret manager. For an interactive shell, these commands read
it without displaying it:

```bash
read -r -s OPENSTORE_API_KEY
export OPENSTORE_API_KEY
```

Press Enter after entering the key. Keep it out of source files, release notes,
screenshots, logs, and command-line arguments. GitHub authentication and the
OpenStore key are separate credentials.

## 2. Develop on a branch

```bash
git switch main
git pull --ff-only origin main
git switch -c fix/describe-the-change
```

Implement the change, then run checks appropriate to it:

```bash
cargo test --locked
clickable build --config ubuntu-touch/clickable.yaml --arch amd64 --non-interactive
clickable test --config ubuntu-touch/clickable.yaml --arch amd64 --non-interactive
git diff --check
```

For UI/input changes, check the native app, including the demo session, pointer
controls, keyboard show/hide behavior, shortcuts, and portrait/landscape layouts.
For protocol changes, test a real RDP connection as well; the offline demo does
not prove server interoperability.

Review and stage your changed files (`git add -p` for tracked files; stage new
files explicitly), commit with `fix: ...` or `feat: ...`, push the branch, and
open a pull request to `main`. For example:

```bash
git commit -m "fix(input): describe the user-visible fix"
git push -u origin HEAD
gh pr create --base main --fill
```

Wait for CI and merge the PR using the repository's normal review process.
The current [CI workflow](../.github/workflows/ci.yml) runs Rust tests, builds
amd64 and arm64 packages, and runs QML tests on amd64. It also builds and tests
both Linux distributions. The amd64 Ubuntu Touch test command also launches the
installed native frontend with isolated demo data. Review the `ui-ubuntu-touch`,
`ui-linux-ubuntu24`, and `ui-linux-debian13` screenshot artifacts for visual changes.
Use the [PC library guide](PC_LIBRARY.md) for the new profile/session workflows.
PRs and pushes to `main` produce CI artifacts. Pushing
a stable `vX.Y.Z` tag runs all checks and then publishes the tested Linux `.deb`
files to a GitHub Release. Ubuntu Touch `.click` and OpenStore publication
continue through the manual steps below.

## 3. Prepare the release commit

Keep release-worthy changes in `docs/releases/unreleased.md` during development.
When preparing a candidate, turn its completed entries into
`docs/releases/VERSION.md`, checking them against the actual diff and commits
since the previous release. Retain pending entries until they ship. The
[v0.1.3 notes](releases/0.1.3.md) provide a completed example.

A release is ready when its intended change is complete, there are no known
blocking regressions, all six versions agree, notes are finalized, the candidate
is clean and committed, CI passes for that exact commit, and both packages pass
review. There is no minimum number of commits or features. A complete bug fix
can be enough for a patch release.

The release skill should write the notes and create/push the tag once these
conditions hold under the user's tagging instruction. A separate confirmation
for that tagging step is unnecessary. Preparation-only requests keep external
steps pending; publishing binaries still follows the requested release scope.

Check existing versions/tags first. Use a patch bump for a compatible bug fix
and a minor bump for a compatible feature; choose a major bump for a breaking
change. The version must be newer than the published version for each OpenStore
architecture. Preserve the package ID so saved user data remains associated with
the application.

```bash
git switch main
git pull --ff-only origin main
git fetch origin --tags
git tag --list
gh release list
curl --fail --silent --show-error https://open-store.io/api/v3/apps/rdp-client-ut.zzvvmm
python3 scripts/release-version.py --check

RELEASE_VERSION=0.1.4
RELEASE_TAG="v$RELEASE_VERSION"
git switch -c "release/$RELEASE_VERSION"
python3 scripts/release-version.py "$RELEASE_VERSION"
```

The version helper updates only these six application fields:

| File | Version field |
| --- | --- |
| `open-rdp-client/Cargo.toml` | Shared Rust package version |
| `Cargo.lock` | `rdp-client-ut` package version |
| `CMakeLists.txt` | Project version |
| `ubuntu-touch/packaging/manifest.json.in` | Click package version |
| `ubuntu-touch/qml/pages/SettingsPage.qml` | About text |
| `ubuntu-touch/po/rdp-client-ut.pot` | Translation project header |

It does not regenerate dependency versions. If the fields disagree, inspect and
repair the mismatch before bumping.

Write `docs/releases/$RELEASE_VERSION.md` with user-visible changes, relevant
fixes, and known limitations. Create `docs/releases/` if necessary. These notes
will be used by both services. Refresh `open-rdp-client/assets/screenshots/` when the visible UI
changes; use real native captures, isolated/demo data, and no credentials. There
can be at most five OpenStore screenshots. Existing screenshots can stay in
place when they still represent the app accurately.

```bash
python3 scripts/release-version.py --check --expect "$RELEASE_VERSION"
cargo test --locked
git diff --check
git diff
git add open-rdp-client/Cargo.toml Cargo.lock CMakeLists.txt ubuntu-touch/packaging/manifest.json.in
git add ubuntu-touch/qml/pages/SettingsPage.qml ubuntu-touch/po/rdp-client-ut.pot
git add "docs/releases/$RELEASE_VERSION.md"
```

Stage any intentionally changed screenshots too. Then commit and open the
release PR:

```bash
git commit -m "chore(release): prepare v$RELEASE_VERSION"
git push -u origin "release/$RELEASE_VERSION"
gh pr create --base main --fill
```

Merge after CI succeeds. Do not publish merely because this guide or the skill
was created; publication is a separate requested action.

## 4. Build the final commit and freeze the artifacts

After the release PR is merged:

```bash
git switch main
git pull --ff-only origin main
test -z "$(git status --porcelain)"
RELEASE_SHA="$(git rev-parse HEAD)"
python3 scripts/release-version.py --check --expect "$RELEASE_VERSION"

gh run list --workflow ci.yml --branch main --commit "$RELEASE_SHA" --event push
```

Select the run ID for that exact commit and watch it with
`gh run watch RUN_ID --exit-status` (replace `RUN_ID` with the displayed numeric
ID). If no run exists, investigate the workflow trigger before publishing.
Check all jobs, including both architecture builds.

Build sequentially in one checkout: each architecture has its own Cargo target directory under its CMake build,
while `build/cargo-home` holds the shared registry cache. CI's matrix uses separate runners.

```bash
cargo test --locked
clickable build --config ubuntu-touch/clickable.yaml --arch amd64 --non-interactive
clickable test --config ubuntu-touch/clickable.yaml --arch amd64 --non-interactive
clickable build --config ubuntu-touch/clickable.yaml --arch arm64 --non-interactive
```

`clickable build` normally includes package review. If you package outside that
command or use downloaded artifacts, run `clickable review --config ubuntu-touch/clickable.yaml --arch ARCH PATH`
for each package and inspect its manifest and architecture. Never bypass a
review failure to ship a release.

On a connected test device, install and launch the arm64 build when appropriate:

```bash
clickable install --config ubuntu-touch/clickable.yaml --arch arm64
clickable launch --config ubuntu-touch/clickable.yaml --arch arm64
```

Test the changed behavior and basic connection/session controls. Record whether
validation used the offline demo, a real server, a device, or desktop rendering.

Freeze the exact packages that will be published:

```bash
RELEASE_DIR="build/releases/$RELEASE_VERSION"
mkdir -p "$RELEASE_DIR"
cp "build/x86_64-linux-gnu/app/rdp-client-ut.zzvvmm_${RELEASE_VERSION}_amd64.click" "$RELEASE_DIR/"
cp "build/aarch64-linux-gnu/app/rdp-client-ut.zzvvmm_${RELEASE_VERSION}_arm64.click" "$RELEASE_DIR/"
git rev-parse HEAD > "$RELEASE_DIR/RELEASE_COMMIT"
(
  cd "$RELEASE_DIR"
  shasum -a 256 "rdp-client-ut.zzvvmm_${RELEASE_VERSION}_amd64.click" \
    "rdp-client-ut.zzvvmm_${RELEASE_VERSION}_arm64.click" > SHA256SUMS
)
```

Use exact filenames. The build folders retain older versions; a broad `*.click`
glob can upload the wrong version. Keep source and packages fixed after this
point. If you change source, repeat the affected validation and rebuild before
tagging or uploading.

## 5. Publish the GitHub Release

Check that the source is still clean and unchanged, then create an annotated tag
at the tested commit:

```bash
test -z "$(git status --porcelain)"
test "$(git rev-parse HEAD)" = "$RELEASE_SHA"
git tag -a "$RELEASE_TAG" "$RELEASE_SHA" -m "Open RDP Client $RELEASE_TAG"
git push origin "$RELEASE_TAG"
```

Wait for the tag's **Build, Test & Release** workflow to succeed. It checks that
the tag matches the application version and `docs/releases/VERSION.md` exists,
builds/tests all platforms, and creates or extends the GitHub Release using those
notes. The release job uses the built-in `GITHUB_TOKEN` with `contents: write`;
no additional publication secret is needed.

The Linux release assets are:

- `open-rdp-client_VERSION_ubuntu24_amd64.deb`
- `open-rdp-client_VERSION_debian13_amd64.deb`
- `SHA256SUMS-linux`, covering both packages and `LINUX_RELEASE_COMMIT`
- `LINUX_RELEASE_COMMIT`, containing the tested source SHA

The workflow validates package identity/version/architecture, verifies the remote
tag still resolves to the tested SHA, and downloads the uploaded assets to check
their bytes. Existing assets must match before any missing files are uploaded.
Rerun a failed publication job to resume with that run's original artifacts;
rebuilding the whole run may produce different package bytes, which are rejected
if they conflict with existing assets. Existing release notes and draft/published
status are preserved when attaching to a release.

Once the automated Linux publication succeeds, attach the frozen Ubuntu Touch
files to the existing release:

```bash
gh release upload "$RELEASE_TAG" \
  "$RELEASE_DIR/rdp-client-ut.zzvvmm_${RELEASE_VERSION}_amd64.click" \
  "$RELEASE_DIR/rdp-client-ut.zzvvmm_${RELEASE_VERSION}_arm64.click" \
  "$RELEASE_DIR/SHA256SUMS" "$RELEASE_DIR/RELEASE_COMMIT"
```

The automation uses `--verify-tag` when creating a release, so it cannot create a
new tag at another commit. If the tag/release already exists, inspect it and
resume missing steps;
do not move a published tag or overwrite a published asset casually.
Resolve an existing tag with `git rev-parse "$RELEASE_TAG^{commit}"` and compare
it with the validated source SHA. An existing matching lightweight tag is valid;
do not replace it merely to add an annotation. Documentation written after a
release should refer to its original tag and commit.

Verify the release and downloaded assets:

```bash
gh release view "$RELEASE_TAG" --json url,tagName,isDraft,assets
VERIFY_DIR="$(mktemp -d)"
gh release download "$RELEASE_TAG" --dir "$VERIFY_DIR"
cmp "$RELEASE_DIR/RELEASE_COMMIT" "$VERIFY_DIR/RELEASE_COMMIT"
cmp "$RELEASE_DIR/SHA256SUMS" "$VERIFY_DIR/SHA256SUMS"
cmp "$RELEASE_DIR/RELEASE_COMMIT" "$VERIFY_DIR/LINUX_RELEASE_COMMIT"
(
  cd "$VERIFY_DIR"
  shasum -a 256 --check SHA256SUMS
  shasum -a 256 --check SHA256SUMS-linux
)
```

## 6. Publish both OpenStore revisions

The app already exists at
[OpenStore](https://open-store.io/app/rdp-client-ut.zzvvmm/). Clickable uploads the
package for the selected architecture from its build directory. Confirm those
files still match the frozen GitHub assets; do not rebuild between services:

```bash
cmp "build/x86_64-linux-gnu/app/rdp-client-ut.zzvvmm_${RELEASE_VERSION}_amd64.click" \
  "$RELEASE_DIR/rdp-client-ut.zzvvmm_${RELEASE_VERSION}_amd64.click"
cmp "build/aarch64-linux-gnu/app/rdp-client-ut.zzvvmm_${RELEASE_VERSION}_arm64.click" \
  "$RELEASE_DIR/rdp-client-ut.zzvvmm_${RELEASE_VERSION}_arm64.click"

clickable publish --config ubuntu-touch/clickable.yaml --arch amd64 --non-interactive -- "$(cat "docs/releases/$RELEASE_VERSION.md")"
clickable publish --config ubuntu-touch/clickable.yaml --arch arm64 --non-interactive -- "$(cat "docs/releases/$RELEASE_VERSION.md")"

python3 scripts/verify-openstore.py "$RELEASE_VERSION" --packages-dir "$RELEASE_DIR"
```

The verifier checks the published version, both `focal` channel revisions with
the Noble framework, the store's SHA-512 values, and both actual public downloads
against the frozen local packages. Run it in the Clickable Python environment.

Screenshots and listing links are separate metadata; `clickable publish` only
uploads a revision/changelog. Use the OpenStore management page to update them.
For programmatic metadata updates, the skill's
[OpenStore reference](../.agents/skills/rdp-client-release/references/openstore.md)
explains how to retain existing screenshots and keywords. Check that images load
on the public listing and that source/support links remain correct.
Once the intended release is verified on both services, remove its shipped
entries from `docs/releases/unreleased.md`; preserve any work still pending.

## 7. Recover from a partial release

GitHub and OpenStore are separate systems, and OpenStore publishes each
architecture separately. There is no atomic cross-service publish.

- If an upload times out, inspect the release/revisions before retrying: the
  server may already have accepted it.
- If only one architecture is published, verify its checksum and upload only
  the missing architecture with the same version and notes.
- If GitHub succeeded but OpenStore failed, retain the tag and assets, fix the
  blocking issue, and resume OpenStore publication from those same files.
- If a published binary needs a code fix, prepare a new patch version. Do not
  repoint an existing release tag or reuse a published version for different code.
- Stop publication on failed tests/review, mismatched commits/checksums,
  rejected permissions, or unclear server state. Resolve the cause before
  another mutation; report exactly which service/architecture succeeded.

## Use the release skill

The versioned skill is
[`.agents/skills/rdp-client-release/SKILL.md`](../.agents/skills/rdp-client-release/SKILL.md).
Codex discovers repo skills from `.agents/skills`; see the
[official skill discovery documentation](https://learn.chatgpt.com/docs/build-skills).
A compatibility link was also installed at
`~/.codex/skills/rdp-client-release` on this workstation.

Example requests:

```text
Use $rdp-client-release to implement this keyboard fix and prepare a release.
Use $rdp-client-release to prepare version 0.1.4 without publishing.
Use $rdp-client-release to release version 0.1.4 to GitHub and OpenStore.
Use $rdp-client-release to resume the missing arm64 upload for version 0.1.4.
```

The checked-in skill travels with this repository. For user-wide discovery
outside this checkout in current Codex, an optional link uses `~/.agents/skills`:

```bash
mkdir -p "$HOME/.agents/skills"
ln -s "$PWD/.agents/skills/rdp-client-release" "$HOME/.agents/skills/rdp-client-release"
```

If the destination already exists, inspect it before replacing it. Repo and
user copies with the same name can both appear in selectors, so the repo copy
alone is usually sufficient for this project. Codex detects skill changes
automatically; restart Codex if an update is not visible.

## Official references

- [Clickable publishing and automatic review](https://clickable-ut.dev/en/latest/getting-started.html).
- [GitHub CLI release creation](https://cli.github.com/manual/gh_release_create).
- [GitHub release management](https://docs.github.com/en/repositories/releasing-projects-on-github/managing-releases-in-a-repository).

GitHub Actions references: [tag filters and token permissions](https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-syntax), [release creation](https://cli.github.com/manual/gh_release_create), and [asset uploads](https://cli.github.com/manual/gh_release_upload).
