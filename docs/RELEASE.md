# Releases

Two workflows in `.github/workflows/`:

- **CI** (`ci.yml`): on every push to `main` and on PRs, type-checks the UI and runs the Rust tests on Linux, macOS and Windows.
- **Release** (`release.yml`): on a `v*` tag (or "Run workflow" by hand), builds installers for every platform,
  attaches them to a **draft** GitHub Release. Publishing the release is what makes the download page show it.

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

## Download page (GitHub Pages)

`site/index.html` is the landing/download page at **https://llamastat.perseusoft.tech** (EN/ES, picks the visitor's OS).
It asks the GitHub API for the latest published release and links its assets directly; until that answers (or if it
fails) every link points at the releases page. Draft releases are invisible to it, so publish the draft to ship. `.github/workflows/pages.yml` publishes it on every push to `main` that touches
`site/` or the screenshots in `docs/`. One-time setup:

1. **Cloudflare DNS (perseusoft.tech)**: `CNAME llamastat → perseusoft.github.io` (DNS only / grey cloud, so GitHub can
   issue the certificate; proxying can be turned on afterwards).
2. Run the *Pages* workflow once (it enables Pages on the repo), then in **Settings → Pages** confirm the custom domain
   `llamastat.perseusoft.tech` and tick *Enforce HTTPS* once the certificate is ready.

## macOS signing (optional)

Without signing, users have to right-click → Open the first time. To sign and notarize, add these secrets
(tauri-action picks them up): `APPLE_CERTIFICATE` (base64 `.p12` of a *Developer ID Application* certificate),
`APPLE_CERTIFICATE_PASSWORD`, `APPLE_SIGNING_IDENTITY`, `APPLE_ID`, `APPLE_PASSWORD` (app-specific password) and
`APPLE_TEAM_ID`. See https://tauri.app/distribute/sign/macos/.

Windows builds are unsigned too (SmartScreen shows "More info → Run anyway"); signing needs a code-signing certificate,
see https://tauri.app/distribute/sign/windows/.
