#!/bin/bash
# Uploads Llamastat installers to Cloudflare R2 with the same layout the Release workflow uses:
#   <prefix>/<version>/<versioned files>, <prefix>/latest/<files without version> and <prefix>/latest.json
#
# Usage:
#   scripts/r2-upload.sh <version> <dir-with-installers>    # e.g. local builds
#   scripts/r2-upload.sh <version> --from-github             # assets of the GitHub release <version>
#
# Needs the AWS CLI (R2 is S3-compatible) and these env vars:
#   R2_ACCOUNT_ID, R2_ACCESS_KEY_ID, R2_SECRET_ACCESS_KEY, R2_BUCKET
#   optional: R2_PREFIX (default llamastat-releases), R2_PUBLIC_URL (default https://downloads.perseusoft.tech)
set -euo pipefail

VERSION="${1:?usage: r2-upload.sh <version> <dir|--from-github>}"
SOURCE="${2:?usage: r2-upload.sh <version> <dir|--from-github>}"
: "${R2_ACCOUNT_ID:?set R2_ACCOUNT_ID}" "${R2_ACCESS_KEY_ID:?set R2_ACCESS_KEY_ID}"
: "${R2_SECRET_ACCESS_KEY:?set R2_SECRET_ACCESS_KEY}" "${R2_BUCKET:?set R2_BUCKET}"
PREFIX="${R2_PREFIX:-llamastat-releases}"
PUBLIC_URL="${R2_PUBLIC_URL:-https://downloads.perseusoft.tech}"
command -v aws >/dev/null || { echo "Install the AWS CLI first (brew install awscli)"; exit 1; }

export AWS_ACCESS_KEY_ID="$R2_ACCESS_KEY_ID" AWS_SECRET_ACCESS_KEY="$R2_SECRET_ACCESS_KEY" AWS_DEFAULT_REGION=auto
ENDPOINT="https://$R2_ACCOUNT_ID.r2.cloudflarestorage.com"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

if [ "$SOURCE" = "--from-github" ]; then
  gh release download "$VERSION" -R Perseusoft/llamastat -D "$WORK/files"
else
  mkdir -p "$WORK/files"
  find "$SOURCE" -maxdepth 3 -type f \( -name '*.dmg' -o -name '*.deb' -o -name '*.rpm' -o -name '*.AppImage' \
    -o -name '*.msi' -o -name '*-setup.exe' \) -exec /bin/cp {} "$WORK/files/" \;
fi
ls -la "$WORK/files"
[ -n "$(ls -A "$WORK/files")" ] || { echo "No installers found"; exit 1; }

put() { # put <local> <key> [extra aws args...]
  local f="$1" key="$2"; shift 2
  aws s3 cp "$f" "s3://$R2_BUCKET/$key" --endpoint-url "$ENDPOINT" "$@"
}

for f in "$WORK/files"/*; do
  n=$(basename "$f")
  put "$f" "$PREFIX/$VERSION/$n" --content-disposition "attachment; filename=\"$n\""
done

# Stable names for download links: drop the version from file names.
for f in "$WORK/files"/*; do
  n=$(basename "$f" | sed -E -e 's/_[0-9]+\.[0-9]+\.[0-9]+//' -e 's/-[0-9]+\.[0-9]+\.[0-9]+-[0-9]+//')
  put "$f" "$PREFIX/latest/$n" --content-disposition "attachment; filename=\"$n\""
done

# Manifest for the download page.
FILES_DIR="$WORK/files" VERSION="$VERSION" BASE="$PUBLIC_URL/$PREFIX/$VERSION" python3 - <<'PY' > "$WORK/latest.json"
import json, os, datetime
base = os.environ["BASE"]
files = sorted(os.listdir(os.environ["FILES_DIR"]))
def pick(*parts):
    for f in files:
        if all(p in f for p in parts): return f"{base}/{f}"
assets = {
    "macos_universal_dmg": pick("universal", ".dmg"),
    "windows_x64_exe": pick("x64-setup.exe"), "windows_x64_msi": pick("x64", ".msi"),
    "windows_arm64_exe": pick("arm64-setup.exe"),
    "linux_x64_appimage": pick("amd64.AppImage"), "linux_x64_deb": pick("amd64.deb"), "linux_x64_rpm": pick("x86_64.rpm"),
    "linux_arm64_appimage": pick("aarch64.AppImage"), "linux_arm64_deb": pick("arm64.deb"), "linux_arm64_rpm": pick("aarch64.rpm"),
}
print(json.dumps({
    "version": os.environ["VERSION"],
    "date": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    "base_url": base,
    "files": [f"{base}/{f}" for f in files],
    "assets": {k: v for k, v in assets.items() if v},
}, indent=2))
PY
cat "$WORK/latest.json"
put "$WORK/latest.json" "$PREFIX/latest.json" --content-type application/json --cache-control "max-age=300"

echo "==> Uploaded to s3://$R2_BUCKET/$PREFIX/$VERSION/, latest/ and latest.json"
aws s3 ls "s3://$R2_BUCKET/$PREFIX/latest/" --endpoint-url "$ENDPOINT"
