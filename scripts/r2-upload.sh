#!/bin/bash
# Uploads Llamastat installers to Cloudflare R2 with the same layout the Release workflow uses:
#   releases/<version>/<versioned files>   and   latest/<files without version>
#
# Usage:
#   scripts/r2-upload.sh <version> <dir-with-installers>    # e.g. local builds
#   scripts/r2-upload.sh <version> --from-github             # assets of the GitHub release <version>
#
# Needs the AWS CLI (R2 is S3-compatible) and these env vars:
#   R2_ACCOUNT_ID, R2_ACCESS_KEY_ID, R2_SECRET_ACCESS_KEY, R2_BUCKET
set -euo pipefail

VERSION="${1:?usage: r2-upload.sh <version> <dir|--from-github>}"
SOURCE="${2:?usage: r2-upload.sh <version> <dir|--from-github>}"
: "${R2_ACCOUNT_ID:?set R2_ACCOUNT_ID}" "${R2_ACCESS_KEY_ID:?set R2_ACCESS_KEY_ID}"
: "${R2_SECRET_ACCESS_KEY:?set R2_SECRET_ACCESS_KEY}" "${R2_BUCKET:?set R2_BUCKET}"
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

aws s3 cp "$WORK/files" "s3://$R2_BUCKET/releases/$VERSION/" --recursive --endpoint-url "$ENDPOINT"

# Stable names for download links: drop the version from file names.
mkdir -p "$WORK/latest"
for f in "$WORK/files"/*; do
  name=$(basename "$f" | sed -E -e 's/_[0-9]+\.[0-9]+\.[0-9]+//' -e 's/-[0-9]+\.[0-9]+\.[0-9]+-[0-9]+//')
  /bin/cp "$f" "$WORK/latest/$name"
done
aws s3 sync "$WORK/latest" "s3://$R2_BUCKET/latest/" --delete --endpoint-url "$ENDPOINT"

echo "==> Uploaded to s3://$R2_BUCKET/releases/$VERSION/ and latest/"
aws s3 ls "s3://$R2_BUCKET/latest/" --endpoint-url "$ENDPOINT"
