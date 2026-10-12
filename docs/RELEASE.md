# Releases

Two workflows in `.github/workflows/`:

- **CI** (`ci.yml`): on every push to `main` and on PRs, type-checks the UI and runs the Rust tests on Linux, macOS and Windows.
- **Release** (`release.yml`): on a `v*` tag (or "Run workflow" by hand), builds installers for every platform,
  attaches them to a **draft** GitHub Release, and mirrors them to Cloudflare R2 if it's configured.

| Job | Runner | Output |
|---|---|---|
| macos-universal | `macos-latest` | `.dmg` (Apple Silicon + Intel) |
| linux-x64 | `ubuntu-22.04` | `.deb`, `.rpm`, `.AppImage` |
| linux-arm64 | `ubuntu-22.04-arm` | `.deb`, `.rpm`, `.AppImage` |
| windows-x64 | `windows-latest` | `.msi`, `-setup.exe` |
| windows-arm64 | `windows-latest` (cross-compiled) | `-setup.exe` (WiX can't build ARM64 MSIs) |

Linux is built on Ubuntu 22.04 so the binaries run on glibc 2.35 and newer.

> `ubuntu-22.04-arm` runners are free for public repos. While the repo is private they may need a paid plan; if the
> linux-arm64 job sits in "queued", that's why.

## Cutting a release

1. Bump the version in `app/package.json`, `app/src-tauri/Cargo.toml` and `app/src-tauri/tauri.conf.json`.
2. Commit, then tag and push:
   ```bash
   git tag v0.2.0 && git push origin v0.2.0
   ```
3. When the workflow finishes, review the draft release on GitHub and publish it.

## Cloudflare R2 (download mirror)

The `r2` job runs only when the repository **variable** `R2_BUCKET` is set. It uploads to:

- `releases/<tag>/…` – every file, versioned names.
- `latest/…` – same files with the version stripped (`Llamastat_universal.dmg`, `Llamastat_x64-setup.exe`,
  `llamastat_amd64.deb`, `llamastat.x86_64.rpm`…), so download links never change.

Setup:

1. **Cloudflare → R2 → Create bucket**, e.g. `llamastat-downloads`.
2. **R2 → Manage API tokens → Create API token** with *Object Read & Write* on that bucket. Copy the
   *Access Key ID*, *Secret Access Key* and your *Account ID*.
3. Make the files downloadable: bucket → **Settings → Custom Domains** (e.g. `downloads.perseussoft.com`), or enable the
   `r2.dev` public URL for testing.
4. **GitHub → Perseusoft/llamastat → Settings → Secrets and variables → Actions**:

   | Kind | Name | Value |
   |---|---|---|
   | Secret | `R2_ACCOUNT_ID` | Cloudflare account ID |
   | Secret | `R2_ACCESS_KEY_ID` | token access key |
   | Secret | `R2_SECRET_ACCESS_KEY` | token secret |
   | Variable | `R2_BUCKET` | `llamastat-downloads` |

5. Once a tagged release has been mirrored, point the README download table at
   `https://<your-domain>/latest/<file>`.

### Uploading by hand

`scripts/r2-upload.sh` uploads with the same layout, handy to try the bucket before the first tagged release or to
re-publish an existing GitHub release:

```bash
export R2_ACCOUNT_ID=... R2_ACCESS_KEY_ID=... R2_SECRET_ACCESS_KEY=... R2_BUCKET=llamastat-downloads
scripts/r2-upload.sh v0.2.0 app/src-tauri/target/release/bundle   # local builds
scripts/r2-upload.sh v0.2.0 --from-github                          # assets of the GitHub release
```

Folders are created on upload (R2 has no real folders, just key prefixes).

## macOS signing (optional)

Without signing, users have to right-click → Open the first time. To sign and notarize, add these secrets
(tauri-action picks them up): `APPLE_CERTIFICATE` (base64 `.p12` of a *Developer ID Application* certificate),
`APPLE_CERTIFICATE_PASSWORD`, `APPLE_SIGNING_IDENTITY`, `APPLE_ID`, `APPLE_PASSWORD` (app-specific password) and
`APPLE_TEAM_ID`. See https://tauri.app/distribute/sign/macos/.

Windows builds are unsigned too (SmartScreen shows "More info → Run anyway"); signing needs a code-signing certificate,
see https://tauri.app/distribute/sign/windows/.
