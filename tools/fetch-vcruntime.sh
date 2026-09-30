#!/bin/bash
# Fetch Microsoft Visual C++ runtime DLLs for bundling with Madeira.
# Downloads VC_redist.x64.exe from Microsoft, extracts the 12 required DLLs,
# and places them in app/Madeira/x86_64-vcruntime/.
# These are Microsoft binaries, not redistributable under this project's license,
# so they are fetched at build time, not committed.
set -euxo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DEST="$REPO_ROOT/app/Madeira/x86_64-vcruntime"

DLLS=(
  concrt140.dll
  msvcp140.dll
  msvcp140_1.dll
  msvcp140_2.dll
  msvcp140_atomic_wait.dll
  msvcp140_codecvt_ids.dll
  vcamp140.dll
  vccorlib140.dll
  vcomp140.dll
  vcruntime140.dll
  vcruntime140_1.dll
  vcruntime140_threads.dll
)

mkdir -p "$DEST"

# Skip if all DLLs already present and non-empty
all_present=true
for dll in "${DLLS[@]}"; do
  if [ ! -s "$DEST/$dll" ]; then
    all_present=false
    break
  fi
done
if $all_present; then
  echo "All VC++ runtime DLLs already present in $DEST"
  exit 0
fi

# Ensure 7-Zip is available
if ! command -v 7zz >/dev/null 2>&1; then
  echo "Installing 7-Zip..."
  brew install sevenzip
fi

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

# Download from Microsoft's stable link
echo "Downloading VC_redist.x64.exe from Microsoft..."
curl -sL --max-time 300 -o "$TMPDIR/VC_redist.x64.exe" "https://aka.ms/vs/17/release/vc_redist.x64.exe"
test -s "$TMPDIR/VC_redist.x64.exe"

# Extract the exe, then extract CABs inside
echo "Extracting..."
7zz x "$TMPDIR/VC_redist.x64.exe" -o"$TMPDIR/vcredist" -y >/dev/null
# Find and extract all CAB files (layout varies by version)
find "$TMPDIR/vcredist" -iname "*.cab" -exec 7zz x {} -o"$TMPDIR/cabs" -y \; >/dev/null

# Copy the 12 DLLs (case-insensitive match)
found=0
for dll in "${DLLS[@]}"; do
  src=$(find "$TMPDIR/cabs" "$TMPDIR/vcredist" -iname "$dll" -type f 2>/dev/null | head -1)
  if [ -n "$src" ]; then
    cp "$src" "$DEST/$dll"
    found=$((found + 1))
    echo "  $dll"
  else
    echo "WARNING: $dll not found in extracted files"
  fi
done

echo "Found $found/${#DLLS[@]} DLLs"

# Verify all present
missing=0
for dll in "${DLLS[@]}"; do
  if [ ! -s "$DEST/$dll" ]; then
    echo "ERROR: Missing $dll"
    missing=$((missing + 1))
  fi
done

if [ $missing -gt 0 ]; then
  echo "ERROR: $missing DLLs missing"
  exit 1
fi

echo "All VC++ runtime DLLs ready in $DEST"
