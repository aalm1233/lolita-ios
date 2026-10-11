#!/bin/bash
set -euo pipefail
preview_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
preview_source="$(mktemp "$preview_root/Tests/SourcePreviewExport.XXXXXX.swift")"
trap 'rm -f "$preview_source"' EXIT
cp "$preview_root/scripts/preview/SourcePreviewExport.swift" "$preview_source"
export LOLITA_PREVIEW_OUTPUT="$preview_root/.build/layout-previews"
cd "$preview_root"
swift test --skip-update --filter SourcePreviewExport/testExport
