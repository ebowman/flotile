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

fail() { echo "error: $*" >&2; exit 1; }

# Highest v* release tag on origin other than $1 (empty if none). Uses origin,
# not local tags: gh release create makes tags on origin only.
resolve_prev_tag() {
    local tag="$1" refs prev
    refs="$(git ls-remote --tags origin 'refs/tags/v*')" || fail "cannot query tags on origin"
    prev="$(printf '%s\n' "${refs}" | awk '{print $2}' | sed 's|^refs/tags/||' \
        | grep -v '\^{}$' | grep -E '^v[0-9]+(\.[0-9]+){0,3}$' | grep -vxF "${tag}" \
        | sed 's/^v//' | sort -t. -k1,1n -k2,2n -k3,3n -k4,4n | tail -n 1 || true)"
    [ -z "${prev}" ] || printf 'v%s\n' "${prev}"
}

# write_release_notes OWNER REPO VERSION TAG SHA256 NOTES_FILE
write_release_notes() {
    local owner="$1" repo="$2" version="$3" tag="$4" sha="$5" out="$6"
    local prev bullets="" extra=""
    prev="$(resolve_prev_tag "${tag}")"
    if [ -n "${prev}" ]; then
        if ! git rev-parse -q --verify "refs/tags/${prev}" >/dev/null; then
            git fetch --quiet origin "refs/tags/${prev}:refs/tags/${prev}" \
                || fail "cannot fetch previous tag ${prev} from origin"
        fi
        bullets="$(git log --no-merges --format='%s' "${prev}..HEAD" \
            | grep -vE '^(beads:|Bump version|Merge )' \
            | sed -E 's/^FloTile-[a-z0-9.]+: //; s/^/- /' || true)"
    fi
    if [ -n "${RELEASE_NOTES_EXTRA:-}" ]; then
        [ -f "${RELEASE_NOTES_EXTRA}" ] && [ -r "${RELEASE_NOTES_EXTRA}" ] \
            || fail "RELEASE_NOTES_EXTRA '${RELEASE_NOTES_EXTRA}' is not a readable file"
        extra="$(cat "${RELEASE_NOTES_EXTRA}")"
    fi
    {
        echo "# FlöTile ${version}"
        echo
        echo "SHA-256 of FloTile-${version}.dmg: \`${sha}\`"
        if [ -n "${bullets}" ] || [ -n "${extra}" ]; then
            echo
            echo "## What's new"
            if [ -n "${extra}" ]; then
                echo
                printf '%s\n' "${extra}"
            fi
            if [ -n "${bullets}" ]; then
                echo
                printf '%s\n' "${bullets}"
            fi
        fi
        echo
        echo "## Install"
        echo
        echo "1. Open the DMG and drag FlöTile to Applications."
        echo "2. Launch it and grant Accessibility access when prompted on first click."
        if [ -n "${prev}" ]; then
            echo
            echo "Full changelog: https://github.com/${owner}/${repo}/compare/${prev}...${tag}"
        fi
    } > "${out}"
}

# Sourcing (e.g. from a test harness) defines the functions only.
[ "${BASH_SOURCE[0]}" = "$0" ] || return 0

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
write_release_notes "${OWNER}" "${REPO}" "${VERSION}" "${TAG}" "${SHA256}" "${NOTES_FILE}"

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
