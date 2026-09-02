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

if gh release view "$TAG" --repo "$REPO" >/dev/null 2>&1; then
  gh release upload "$TAG" --repo "$REPO" --clobber "$SRC"/qscanner-"${VERSION}".*.tar.gz "$SRC/SHA256SUMS"
else
  gh release create "$TAG" --repo "$REPO" --title "QScanner ${VERSION} (CNAPP demo build)" \
    --notes "This is a custom QScanner build with IaC scanning and MCP remediation tools for the CNAPP demo, built from an internal branch." \
    "$SRC"/qscanner-"${VERSION}".*.tar.gz "$SRC/SHA256SUMS"
fi
echo "Published $TAG to $REPO"
