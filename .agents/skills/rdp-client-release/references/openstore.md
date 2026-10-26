# OpenStore operations for this app

Application: `rdp-client-ut.zzvvmm`.
Listing: <https://open-store.io/app/rdp-client-ut.zzvvmm/>.
Source: <https://github.com/zzvvmm/open-rdp-client-utouch>.
Support: <https://github.com/zzvvmm/open-rdp-client-utouch/issues>.

## Read and publish revisions

Public metadata: `GET https://open-store.io/api/v3/apps/rdp-client-ut.zzvvmm`.
The JSON wrapper contains `success`, `data`, and `message`. Inspect
`data.revisions`, filtering by version, architecture, channel, and framework.
For this app use architectures `amd64`/`arm64`, channel `focal`, and framework
`ubuntu-touch-24.04-1.x`. The channel name does not mean the package targets
20.04: Clickable uses `focal` for new releases including Noble.

Prefer the installed Clickable uploader. It reads `OPENSTORE_API_KEY` without
putting the key into shell arguments. Never print the key or an authenticated
request URL. If using a direct API request, load credentials in-process, avoid
verbose HTTP logging, and redact exception URLs.

Revision endpoint: `POST /api/v3/manage/rdp-client-ut.zzvvmm/revision`.
Authentication uses the `apikey` query parameter. Multipart fields:

| Field | Value |
| --- | --- |
| `file` | The exact reviewed architecture-specific `.click` binary |
| `channel` | `focal` |
| `changelog` | The same version's reviewed release notes |

Read and verify remote state after an ambiguous response before another POST.
If that architecture/version exists, compare its SHA-512 with the frozen local
file. An identical revision is success; different bytes require investigation.
Do not upload another version simply to bypass a duplicate-version error.

`scripts/verify-openstore.py` in the repository verifies the published current
version, both revisions, server-provided SHA-512 values, and actual public
downloads against local files. It uses `requests` from the Clickable Python
environment and needs no API key. Inspect `download_url`, `download_sha512`,
`revision`, and `framework` when diagnosing a mismatch.

## Screenshot and metadata updates

The management UI is suitable for an occasional update. For API automation,
first read authenticated metadata using
`GET /api/v3/manage/rdp-client-ut.zzvvmm?apikey=...` and save the original public
listing fields under ignored `build/` before mutation.

`PUT /api/v3/manage/rdp-client-ut.zzvvmm` accepts multipart form data:

- `screenshots`: a JSON array of existing screenshot URLs to retain, in order.
- `screenshot_files`: repeated file parts for new PNG/JPG/JPEG images.
- `keywords`: preserve the existing comma-separated keywords.
- `published`, `nsfw`, source/support/donation links, and other metadata: retain
  the current values unless the task calls for changes.

There is a five-image limit across retained and newly uploaded images. Re-read
current metadata immediately before the PUT and compare it with the snapshot
used to prepare the update. If it changed, reconcile rather than overwriting
someone else's changes.

Omitting `screenshots` can remove every existing screenshot; omitting
`keywords` can clear keywords. This is why a minimal PUT with only new image
parts is unsafe. Sending `screenshots=[]` deliberately removes existing images;
use it only when replacement/removal is part of the request. Retained images
plus new files should stay within the limit, or excess files may be discarded.

After updating, verify the public metadata and load all image URLs on the
listing. The server can optimize PNG encoding: file hashes may change while
image dimensions and pixels remain correct. Do not demand byte-identical
screenshot PNGs. This differs from release binaries, whose checksums must match.

Reference implementation, to recheck if the API behavior changes:

- [Clickable publish implementation](https://gitlab.com/clickable/clickable/-/blob/master/clickable/commands/publish.py).
- [OpenStore management API](https://github.com/UbuntuOpenStore/openstore-api/blob/master/src/api/manage.ts).
- [Metadata and screenshot handling](https://github.com/UbuntuOpenStore/openstore-api/blob/master/src/db/package/methods.ts).
