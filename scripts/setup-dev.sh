#!/usr/bin/env bash
#
# setup-dev.sh — Install the libvlc xcframework locally and point
# Package.swift plus the Showcase app at repo-local sources, so `swift build`
# / `swift test` and local Showcase development work on a fresh clone.
#
# FORK NOTE (c0b1-dev/SwiftVLC-LGPL):
#   This script downloads from THIS fork's releases, not from upstream
#   harflabs/SwiftVLC. That is not cosmetic. The upstream binary ships the
#   `zvbi` teletext plugin, which is GPL-licensed and therefore incompatible
#   with App Store distribution. It also lacks this fork's libVLC patches —
#   most importantly 0004 ("adopted layer"), without which hardware decoding
#   via VideoToolbox and Picture-in-Picture cannot both work at once.
#   A build against the upstream binary succeeds and looks fine; the damage
#   only surfaces at App Review (GPL) and on device (grey PiP, hot phone).
#   Do not "fix" this by pointing REPO back at upstream.
#
# Usage:
#   ./scripts/setup-dev.sh                  # install latest release (or keep existing)
#   ./scripts/setup-dev.sh v0.3.0           # pin to a specific release tag
#   ./scripts/setup-dev.sh --force          # always re-download, even if Vendor/ exists
#   ./scripts/setup-dev.sh --skip-download  # only flip local references
#                                             (useful after ./scripts/build-libvlc.sh)
#
set -euo pipefail

REPO="c0b1-dev/SwiftVLC-LGPL"   # see FORK NOTE above — never upstream
XCFW_DIR="Vendor/libvlc.xcframework"
SHOWCASE_PROJECT="Showcase/SwiftVLCShowcase.xcodeproj/project.pbxproj"
ZIP_NAME="libvlc.xcframework.zip"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$ROOT_DIR"

# ── Args ──────────────────────────────────────────────────────────────────────

VERSION=""
FORCE=false
SKIP_DOWNLOAD=false

for arg in "$@"; do
  case "$arg" in
    --force)         FORCE=true ;;
    --skip-download) SKIP_DOWNLOAD=true ;;
    --help|-h)
      sed -n 's/^# \{0,1\}//p' "$0" | sed -n '/^Usage:/,/^$/p'
      exit 0 ;;
    -*)
      echo "Error: unknown flag '$arg'" >&2
      exit 1 ;;
    *)
      if [[ -n "$VERSION" ]]; then
        echo "Error: version already specified ('$VERSION'), got extra arg '$arg'" >&2
        exit 1
      fi
      VERSION="$arg" ;;
  esac
done

# ── Helpers ───────────────────────────────────────────────────────────────────

# Rewrite Package.swift's libvlc binaryTarget to local path form. Writes to a
# temp file and renames atomically so an interrupted write can't leave the
# manifest corrupted.
switch_package_to_local_path() {
  python3 - <<'PYEOF'
import os
import re
import sys
import tempfile

path = "Package.swift"
with open(path, "r") as f:
    text = f.read()

pattern = r'\.binaryTarget\(\s*name:\s*"libvlc"[^)]*\)'
replacement = '.binaryTarget(name: "libvlc", path: "Vendor/libvlc.xcframework")'
result, n = re.subn(pattern, replacement, text, count=1, flags=re.DOTALL)

if n == 0:
    print("ERROR: could not find libvlc binaryTarget in Package.swift", file=sys.stderr)
    sys.exit(1)
if result == text:
    # Already local path — nothing to do.
    sys.exit(0)

fd, tmp = tempfile.mkstemp(dir=".", prefix=".Package.swift.", suffix=".tmp")
try:
    with os.fdopen(fd, "w") as f:
        f.write(result)
    os.replace(tmp, path)
except Exception:
    if os.path.exists(tmp):
        os.unlink(tmp)
    raise
PYEOF
}

switch_showcase_to_local_package() {
  SHOWCASE_PROJECT="$SHOWCASE_PROJECT" python3 - <<'PYEOF'
import os
import re
import sys
import tempfile

path = os.environ["SHOWCASE_PROJECT"]

with open(path, "r") as f:
    text = f.read()

local_block = """/* Begin XCLocalSwiftPackageReference section */
\t\tBA000001 /* XCLocalSwiftPackageReference \"..\" */ = {
\t\t\tisa = XCLocalSwiftPackageReference;
\t\t\trelativePath = \"..\";
\t\t};
/* End XCLocalSwiftPackageReference section */"""

remote_pattern = re.compile(
    r'/\* Begin XCRemoteSwiftPackageReference section \*/\n'
    r'\t\tBA000001 /\* XCRemoteSwiftPackageReference "SwiftVLC" \*/ = \{\n'
    r'\t\t\tisa = XCRemoteSwiftPackageReference;\n'
    r'\t\t\trepositoryURL = "https://github.com/harflabs/SwiftVLC";\n'
    r'\t\t\trequirement = \{\n'
    r'\t\t\t\tkind = (?:upToNextMajorVersion|exactVersion);\n'
    r'\t\t\t\t(?:minimumVersion|version) = [0-9.]+;\n'
    r'\t\t\t\};\n'
    r'\t\t\};\n'
    r'/\* End XCRemoteSwiftPackageReference section \*/'
)

# Already local? Match structurally, not by exact text: Xcode rewrites
# `relativePath = "..";` to `relativePath = ..;` when it saves the project,
# and an exact-string check then mistakes an already-converted project for an
# unconverted one and fails.
already_local = re.search(
    r'isa = XCLocalSwiftPackageReference;\s*\n\s*relativePath = "?\.\."?;',
    text,
)
if already_local:
    result = text
else:
    result, n = remote_pattern.subn(local_block, text, count=1)
    if n == 0:
        print("ERROR: Showcase package reference block not found", file=sys.stderr)
        sys.exit(1)

result = result.replace(
    'BA000001 /* XCRemoteSwiftPackageReference "SwiftVLC" */',
    'BA000001 /* XCLocalSwiftPackageReference ".." */',
)

if result == text:
    sys.exit(0)

fd, tmp = tempfile.mkstemp(dir=".", prefix=".SwiftVLCShowcase.", suffix=".tmp")
try:
    with os.fdopen(fd, "w") as f:
        f.write(result)
    os.replace(tmp, path)
except Exception:
    if os.path.exists(tmp):
        os.unlink(tmp)
    raise
PYEOF
}

require_gh() {
  if ! command -v gh &>/dev/null; then
    echo "Error: GitHub CLI (gh) is required. Install with: brew install gh" >&2
    exit 1
  fi
  if ! gh auth status &>/dev/null; then
    echo "Error: not authenticated with gh. Run: gh auth login" >&2
    exit 1
  fi
}

# ── Decide whether to download ────────────────────────────────────────────────

if [[ "$SKIP_DOWNLOAD" == true ]]; then
  if [[ ! -d "$XCFW_DIR" ]]; then
    echo "Error: --skip-download passed but $XCFW_DIR does not exist." >&2
    echo "  Run ./scripts/build-libvlc.sh first, or omit --skip-download." >&2
    exit 1
  fi
  echo "Keeping existing xcframework at $XCFW_DIR (--skip-download)."
else
  NEED_DOWNLOAD=false
  if [[ ! -d "$XCFW_DIR" ]]; then
    NEED_DOWNLOAD=true
  elif [[ "$FORCE" == true ]]; then
    echo "Removing existing $XCFW_DIR (--force)..."
    rm -rf "$XCFW_DIR"
    NEED_DOWNLOAD=true
  else
    echo "Keeping existing xcframework at $XCFW_DIR (pass --force to re-download)."
  fi

  if [[ "$NEED_DOWNLOAD" == true ]]; then
    require_gh
    mkdir -p Vendor

    echo "Downloading $ZIP_NAME..."
    # The trailing * also picks up the .sha256 sidecar asset.
    if [[ -n "$VERSION" ]]; then
      gh release download "$VERSION" --repo "$REPO" --pattern "${ZIP_NAME}*" --dir Vendor/
    else
      gh release download --repo "$REPO" --pattern "${ZIP_NAME}*" --dir Vendor/
    fi

    # Verify before unpacking: a truncated download otherwise fails much later,
    # at link time or — worse — as a subtly broken framework.
    if [[ -f "Vendor/${ZIP_NAME}.sha256" ]]; then
      echo "Verifying checksum..."
      if ! (cd Vendor && shasum -a 256 -c "${ZIP_NAME}.sha256"); then
        echo "Error: checksum mismatch for $ZIP_NAME — download incomplete or asset replaced." >&2
        exit 1
      fi
      rm -f "Vendor/${ZIP_NAME}.sha256"
    else
      echo "Warning: no .sha256 asset alongside $ZIP_NAME — skipping verification." >&2
    fi

    echo "Extracting..."
    (cd Vendor && ditto -x -k "$ZIP_NAME" . && rm "$ZIP_NAME")
    echo "  Installed to $XCFW_DIR"

    # Fix duplicate symbols (json_parse_error/json_read) in the static library.
    # Two VLC plugins (ytdl, chromecast) each compile their own copy; the
    # Apple linker in Xcode 16+ treats duplicates as errors on Mac Catalyst.
    # For this fork's own release artefact this is a no-op — build-libvlc.sh
    # already applies it — and the script is idempotent (it only acts when it
    # actually finds more than one definition). Kept so that upstream or
    # hand-built archives still work.
    echo "Fixing duplicate symbols in static libraries..."
    "$SCRIPT_DIR/fix-duplicate-symbols.sh" "$XCFW_DIR"
  fi
fi

# ── Flip Package.swift to local path ──────────────────────────────────────────

echo "Pointing Package.swift at $XCFW_DIR..."
switch_package_to_local_path
echo "  Package.swift now uses local path."

echo "Pointing Showcase app at the local Swift package checkout..."
if switch_showcase_to_local_package; then
  echo "  Showcase now uses the repo-local package."
else
  # Not fatal: the engine is installed and Package.swift already points at it, so
  # consumers of this package are ready. Only the bundled demo app is affected.
  echo "  Warning: could not rewrite the Showcase project — open it manually if you need it." >&2
  echo "  (The package itself is set up; this does not affect apps that depend on it.)" >&2
fi

echo ""
echo "Done. Try:"
echo "  swift build"
echo "  swift test"
