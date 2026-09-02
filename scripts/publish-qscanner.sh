#!/usr/bin/env bash
# Publish locally built qscanner tarballs as a GitHub release on nelssec/cnapp-demo.
# Usage: scripts/publish-qscanner.sh <version>   (e.g. 5.3.0-cnapp2)
set -euo pipefail

VERSION="${1:?version required, e.g. 5.3.0-cnapp2}"
SRC="${SRC:-/Users/anelson/git_base/qscanner-develop/output/release}"
REPO="nelssec/cnapp-demo"
TAG="qscanner-${VERSION}"

for f in "$SRC/qscanner-${VERSION}.darwin-arm64.tar.gz" "$SRC/qscanner-${VERSION}.linux-amd64.tar.gz" "$SRC/SHA256SUMS"; do
  [[ -f "$f" ]] || { echo "missing $f (run scripts/build-release.sh in qscanner-develop first)"; exit 1; }
done

# Create the release without assets first, then upload each asset with retries: the GitHub
# uploads endpoint intermittently drops large (~65 MB) uploads with "tls: bad record MAC".
if ! gh release view "$TAG" --repo "$REPO" >/dev/null 2>&1; then
  gh release create "$TAG" --repo "$REPO" --title "QScanner ${VERSION} (CNAPP demo build)" \
    --notes "This is a custom QScanner build with IaC scanning (with a CIS / Pod Security Standards / Kubescape / Qualys KSPM and IaC control crosswalk) and MCP remediation tools for the CNAPP demo, built from an internal branch."
fi
for f in "$SRC/qscanner-${VERSION}.darwin-arm64.tar.gz" "$SRC/qscanner-${VERSION}.linux-amd64.tar.gz" "$SRC/SHA256SUMS"; do
  for attempt in 1 2 3 4 5; do
    if gh release upload "$TAG" --repo "$REPO" --clobber "$f"; then
      break
    fi
    if [[ $attempt -eq 5 ]]; then echo "upload failed after 5 attempts: $f" >&2; exit 1; fi
    echo "upload of $(basename "$f") failed (attempt $attempt), retrying..." >&2
    sleep 5
  done
done
echo "Published $TAG to $REPO"
