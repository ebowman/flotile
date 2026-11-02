#!/bin/bash
# Publishes the notarized DMG as a GitHub release and writes the update manifest.
#
# Usage: scripts/publish-release.sh [--dry-run]
#
# --dry-run runs every precondition, writes build/appcast.json and
# build/release-notes.md, prints the manifest and the exact gh command, and
# creates nothing.
#
# PUBLISH_SKIP_CLEAN_TREE_CHECK=1 skips the clean-tree precondition, and is
# honoured ONLY with --dry-run. NEVER use it for a real release.

set -euo pipefail

DRY_RUN=0
case "${1:-}" in
    "") ;;
    --dry-run) DRY_RUN=1 ;;
    *) echo "Usage: $(basename "$0") [--dry-run]" >&2; exit 1 ;;
esac
[ "$#" -le 1 ] || { echo "Usage: $(basename "$0") [--dry-run]" >&2; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(git -C "${SCRIPT_DIR}" rev-parse --show-toplevel)"
cd "${REPO_ROOT}"

fail() { echo "error: $*" >&2; exit 1; }

# 1. origin remote -> OWNER/REPO
ORIGIN_URL="$(git remote get-url origin 2>/dev/null)" || fail "no git remote named 'origin'"
if [[ "${ORIGIN_URL}" =~ ^git@github\.com:([^/]+)/([^/]+)$ ]] \
    || [[ "${ORIGIN_URL}" =~ ^ssh://git@github\.com/([^/]+)/([^/]+)$ ]] \
    || [[ "${ORIGIN_URL}" =~ ^https://([^@/]+@)?github\.com/([^/]+)/([^/]+)$ ]]; then
    OWNER="${BASH_REMATCH[$((${#BASH_REMATCH[@]} - 2))]}"
    REPO="${BASH_REMATCH[$((${#BASH_REMATCH[@]} - 1))]}"
    REPO="${REPO%.git}"
else
    fail "cannot parse OWNER/REPO from origin URL '${ORIGIN_URL}'"
fi
[ -n "${OWNER}" ] && [ -n "${REPO}" ] || fail "empty OWNER/REPO parsed from '${ORIGIN_URL}'"

# 2. version from the built bundle
VERSION="$("${SCRIPT_DIR}/read-app-version.sh" short)" || fail "cannot read version from built bundle (run make release-build)"
[ -n "${VERSION}" ] || fail "built bundle reported an empty version"

# 3. clean working tree
if [ "${PUBLISH_SKIP_CLEAN_TREE_CHECK:-}" = "1" ] && [ "${DRY_RUN}" = "1" ]; then
    echo "warning: skipping clean-tree check (dry run only; never for a real release)" >&2
elif [ -n "$(git status --porcelain)" ]; then
    fail "working tree is not clean; a release must describe an exact commit (commit or stash changes)"
fi

# 4. tag absent locally and on origin
TAG="v${VERSION}"
if git rev-parse -q --verify "refs/tags/${TAG}" >/dev/null; then
    fail "tag ${TAG} already exists locally"
fi
REMOTE_TAGS="$(git ls-remote --tags origin "refs/tags/${TAG}")" || fail "cannot query tags on origin"
[ -z "${REMOTE_TAGS}" ] || fail "tag ${TAG} already exists on origin"

# 5. DMG exists, Gatekeeper-accepted, stapled
DMG="build/FloTile-${VERSION}.dmg"
[ -f "${DMG}" ] || fail "DMG not found at ${DMG} (run make dmg && make notarize)"
spctl -a -t open --context context:primary-signature "${DMG}" 2>/dev/null \
    || fail "${DMG} does not pass spctl Gatekeeper assessment (notarize it)"
xcrun stapler validate "${DMG}" >/dev/null 2>&1 \
    || fail "${DMG} has no valid stapled notarization ticket"

# Manifest
SHA256="$(shasum -a 256 "${DMG}" | awk '{print $1}')"
[ -n "${SHA256}" ] || fail "could not compute sha256 of ${DMG}"
MANIFEST="build/appcast.json"
NOTES_FILE="build/release-notes.md"
BASE="https://github.com/${OWNER}/${REPO}/releases"

python3 - "${MANIFEST}" "${VERSION}" "${BASE}/tag/${TAG}" "${BASE}/download/${TAG}/FloTile-${VERSION}.dmg" "${SHA256}" <<'PY'
import json, sys
path, version, notes, url, sha = sys.argv[1:6]
with open(path, "w") as f:
    json.dump({"latestVersion": version, "notes": notes, "dmgURL": url, "dmgSHA256": sha}, f, indent=2)
    f.write("\n")
PY
python3 - "${MANIFEST}" <<'PY' || fail "generated ${MANIFEST} failed validation"
import json, sys
d = json.load(open(sys.argv[1]))
assert sorted(d) == ["dmgSHA256", "dmgURL", "latestVersion", "notes"], d
assert all(isinstance(v, str) and v for v in d.values()), d
assert len(d["dmgSHA256"]) == 64
PY

# Release notes
PREV_TAG="$(git describe --tags --abbrev=0 2>/dev/null || true)"
{
    echo "# FlöTile ${VERSION}"
    echo
    echo "SHA-256 of FloTile-${VERSION}.dmg: \`${SHA256}\`"
    echo
    echo "## Install"
    echo
    echo "1. Open the DMG and drag FlöTile to Applications."
    echo "2. Launch it and grant Accessibility access when prompted on first click."
    if [ -n "${PREV_TAG}" ]; then
        echo
        echo "Full changelog: https://github.com/${OWNER}/${REPO}/compare/${PREV_TAG}...${TAG}"
    fi
} > "${NOTES_FILE}"

GH_CMD=(gh release create "${TAG}" "${DMG}" "${MANIFEST}" --title "FlöTile ${VERSION}" --notes-file "${NOTES_FILE}" --repo "${OWNER}/${REPO}")
MANIFEST_URL="https://github.com/${OWNER}/${REPO}/releases/latest/download/appcast.json"

if [ "${DRY_RUN}" = "1" ]; then
    echo "DRY RUN: nothing will be created."
    echo "--- ${MANIFEST} ---"
    cat "${MANIFEST}"
    echo "--- command ---"
    printf '%q ' "${GH_CMD[@]}"; echo
    echo "Manifest URL would be: ${MANIFEST_URL}"
    exit 0
fi

"${GH_CMD[@]}"
echo "Release: ${BASE}/tag/${TAG}"
echo "Manifest URL: ${MANIFEST_URL}"
