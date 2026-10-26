---
name: rdp-client-release
description: "Develop, prepare, publish, verify, or resume Open RDP Client for Ubuntu Touch releases to GitHub and OpenStore. Use for the rdp-client-ut.zzvvmm application and zzvvmm/open-rdp-client-utouch repository."
---

# RDP Client Release

Work in the Open RDP Client repository. Resolve its root from the current
checkout or this skill's real path, and confirm the manifest ID is
`rdp-client-ut.zzvvmm` and origin is the intended repository before mutations.
Read `docs/RELEASING.md` in that repository for the maintained human workflow,
commands, and artifact locations. Inspect current CI and config rather than
assuming this skill describes the latest implementation.

## Choose the requested scope

- For development, implement the requested change and run relevant checks;
  maintain an Unreleased note for changes worth announcing. Add regression
  tests when they verify
  the changed input/protocol behavior, rather than mirroring implementation.
- For a guide or preparation task, create reviewable notes, version updates,
  screenshots, packages, or instructions as requested. Do not infer permission
  to push tags or publish from a request to explain or prepare a release.
- For an explicit release request, carry out the requested GitHub/OpenStore
  publication using existing authorization. Do not repeatedly ask permission
  for the same authorized release. If credentials or a required choice are
  missing, complete independent preparation and ask only for that missing input.
- For a resumed release, inspect both remote states first and perform only
  missing steps. Existing tags/revisions may belong to a partially completed run.

## Release notes and readiness

The user wants release notes and a version tag whenever a release candidate is
ready. Treat them as required release deliverables, without asking a separate
confirmation for the already authorized tagging step. An explicit preparation-only
or no-tag request takes precedence. This preference does not by itself authorize
publishing new binaries to GitHub or OpenStore during an unrelated development task.

Keep useful pending changes in `docs/releases/unreleased.md`. When preparing a
candidate, inspect the diff and commits since the previous release, then write
`docs/releases/VERSION.md` with the concrete user-visible behavior, fixes,
compatibility changes, and known limitations that are actually established.
Include validation evidence accurately; distinguish offline/demo checks from
real-server or device tests. Omit empty template sections and internal workflow
history. Use the reviewed notes for both services. Once those changes ship,
remove them from Unreleased while retaining entries that have not shipped.

"Enough and ready" means a coherent completed change with no known blocking
regression, matching version fields, finalized release notes, a clean committed
candidate, successful required CI for that exact commit, and reviewed packages
for both architectures. Judge by these outcomes, not a minimum commit count,
elapsed time, or an arbitrary feature quota. If a gate is missing, finish the
authorized preparation that can satisfy it and report what remains before tagging.

When those gates pass, create an annotated `vVERSION` tag at the validated SHA
and push it within the user's tagging authorization. Verify the remote tag
resolves to that SHA. If a tag already exists, inspect and reuse it when it
matches, including an existing lightweight tag; never replace it just to change
its annotation. A different target is a conflict to resolve before proceeding.
When documenting a previously published release, recover its real notes and
existing tag without retagging it at a later documentation commit.

## Project invariants

Keep the package ID stable. Check all six versions with
`python3 scripts/release-version.py --check`; bump with the same script only
when requested. Choose a stable version newer than each published OpenStore
architecture. Store reviewed release notes in `docs/releases/VERSION.md`.

Use one clean, committed source revision for the tag and both packages. Match
CI's successful `headSha` to that revision; a green unrelated branch/run is not
release evidence. The current CI builds/tests on PRs and `main` pushes, without
automated publication. Do not add tag-triggered publishing or secrets/config
changes unless the task includes that automation.

Local architectures share Cargo directories: build amd64 then arm64 sequentially.
Require Rust tests, amd64 QML tests, and package review for both architectures.
Use device/real-server testing appropriate to the change and distinguish it
from an offline demo. Docker commands can outlive an interrupted tool session;
check active builds before launching competing ones.

Copy the exact versioned packages to `build/releases/VERSION/`, record the source
SHA and checksums, and publish those bytes to both services. Avoid broad `.click`
globs because build directories retain older releases. Rebuild and revalidate
if source changes. Never ship stale artifacts or skip a review failure to
work around a slow/repeated build.

## Publication and verification

Use an available connected GitHub tool when it supports the required operations;
otherwise use authenticated `gh` or the GitHub API. Create an annotated
`vVERSION` tag at the tested commit, push it, and create the GitHub Release with
both packages, checksums, source SHA, and notes. With `gh`, use `--verify-tag`
and `--notes-file`. Verify downloaded assets against the frozen local files.

For OpenStore revision uploads, prefer `clickable publish --arch ARCH` with
`OPENSTORE_API_KEY` from the environment. It selects the package from the build
directory, so compare it with the frozen artifact before publishing. Read
[references/openstore.md](references/openstore.md) when inspecting revisions,
updating screenshots/metadata, or resuming a partial upload. Run
`scripts/verify-openstore.py VERSION --packages-dir build/releases/VERSION` to
verify both public downloads, not just upload responses.

Use real native screenshots with isolated/demo data; retain existing images
when still accurate. Avoid exposing saved PCs, user accounts, credentials, or
unrelated desktop content. Native Lomiri rendering may need OpenGL backed by
Mesa; Qt Quick's `software` scenegraph can crash on Lomiri shapes. Do not treat
that capture-setup failure as proof the application itself is broken.

On timeout or error, re-read remote state before retrying. Stop blind retries
on permission/review rejection, unknown server state, or checksum/commit
mismatch. Never move a published tag, clobber a published asset, or replace a
published version's code as a routine recovery step. Resume a missing
architecture without repeating a successful one; use a new patch version for
code changes after publication.

Report the commit suggestion or created commit as applicable, version/tag,
release/listing links, architectures and screenshot status, checks performed,
and any remaining work. Claim full completion only after both requested
services and both architectures have been verified.
