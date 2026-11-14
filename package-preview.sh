#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
if [ "$#" -ne 1 ]; then
  echo 'Usage: bash package-preview.sh NEW_OUTPUT_DIRECTORY' >&2
  exit 2
fi
output="$1"
if [ -e "$output" ]; then
  echo 'Output directory already exists; choose a new path.' >&2
  exit 1
fi
bash build.sh
mkdir -p "$output"
output="$(cd "$output" && pwd)"
/usr/bin/ditto -c -k --keepParent UsageEdge.app "$output/UsageEdge-macOS-preview.zip"
/usr/bin/ditto -c -k --keepParent Windows "$output/UsageEdge-Windows-preview.zip"
unzip -tqq "$output/UsageEdge-macOS-preview.zip"
unzip -tqq "$output/UsageEdge-Windows-preview.zip"
(cd "$output" && shasum -a 256 UsageEdge-macOS-preview.zip UsageEdge-Windows-preview.zip > SHA256SUMS && shasum -a 256 -c SHA256SUMS)
echo "Preview artifacts: $output"
echo 'macOS artifact is ad-hoc signed and is not notarized.'
