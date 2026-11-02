#!/bin/bash
# Builds a Developer ID signed, hardened-runtime Release FloTile.app via
# xcodegen + xcodebuild.
#
# Usage: scripts/build-app.sh
# Output: build/FloTile.app (path printed on success). Idempotent: any stale
#         copy is removed first.
#
# Env: CODESIGN_IDENTITY  pin an identity (else auto-detected Developer ID)
#      ALLOW_ADHOC=1      permit ad-hoc "-" signing when no identity exists
#                         (local testing only; cannot be notarized and does
#                         not keep a stable Accessibility grant)
#
# xcodebuild overrides (see the invocation below for the rationale).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(git -C "${SCRIPT_DIR}" rev-parse --show-toplevel)"
cd "${REPO_ROOT}"

APP_NAME="FloTile"
TEAM_ID="Y5SB82BPYL"
BUILD_DIR="${REPO_ROOT}/build"
DERIVED="${REPO_ROOT}/.build/xcode-release"
LOG="${BUILD_DIR}/build-app.log"
APP_BUNDLE="${BUILD_DIR}/${APP_NAME}.app"

# VERSION file is the single source of truth -> MARKETING_VERSION.
VERSION_FILE="${REPO_ROOT}/VERSION"
if [ ! -f "${VERSION_FILE}" ]; then
    echo "error: VERSION file not found at ${VERSION_FILE}" >&2
    exit 1
fi
# Trim leading/trailing whitespace ONLY (not interior): `tr -d` would turn
# "1. 2.0" into a valid-looking "1.2.0" that the updater would not accept.
VERSION="$(<"${VERSION_FILE}")"
VERSION="${VERSION#"${VERSION%%[![:space:]]*}"}"
VERSION="${VERSION%"${VERSION##*[![:space:]]}"}"

# The updater's SemanticVersion fails CLOSED on anything but 1-4
# dot-separated non-negative integers (and Int overflow), which would
# silently stop offering updates; so refuse to build such a version.
if ! [[ "${VERSION}" =~ ^[0-9]+(\.[0-9]+){0,3}$ ]]; then
    echo "error: VERSION file contains an invalid version string: '${VERSION}'" >&2
    echo "       expected 1-4 dot-separated non-negative integers, e.g. 1.2.0" >&2
    exit 1
fi
IFS='.' read -r -a _components <<< "${VERSION}"
for _c in "${_components[@]}"; do
    if [ "${#_c}" -gt 18 ]; then
        echo "error: VERSION component '${_c}' is too large to parse as an integer (max 18 digits)." >&2
        exit 1
    fi
done
unset _components _c

# Monotonic build number from commit count; 0 if git metadata is unavailable.
BUILD_NUMBER="$(git -C "${REPO_ROOT}" rev-list --count HEAD 2>/dev/null || echo 0)"

# shellcheck source=lib/resolve-codesign-identity.sh
source "${SCRIPT_DIR}/lib/resolve-codesign-identity.sh"

if [ -z "${CODESIGN_IDENTITY}" ]; then
    if [ "${ALLOW_ADHOC:-}" = "1" ]; then
        CODESIGN_IDENTITY="-"
        echo "==> WARNING: no Developer ID Application identity found; ALLOW_ADHOC=1 set." >&2
        echo "    Building AD-HOC signed: the result CANNOT be notarized and will NOT keep" >&2
        echo "    a stable Accessibility grant across rebuilds. Local testing only." >&2
    else
        echo "error: no 'Developer ID Application' identity found (and CODESIGN_IDENTITY is unset)." >&2
        echo "       Install a Developer ID certificate, set CODESIGN_IDENTITY, or set" >&2
        echo "       ALLOW_ADHOC=1 for a local-only ad-hoc build." >&2
        exit 1
    fi
fi

for tool in xcodegen xcodebuild codesign; do
    if ! command -v "${tool}" >/dev/null 2>&1; then
        echo "error: required tool '${tool}' not found in PATH" >&2
        exit 1
    fi
done

mkdir -p "${BUILD_DIR}"
: > "${LOG}"

echo "==> Generating Xcode project..."
xcodegen generate --spec project.yml >>"${LOG}" 2>&1 || {
    echo "error: xcodegen failed; last log lines:" >&2
    tail -n 30 "${LOG}" >&2
    exit 1
}

# Overrides, all required (see settled-set notes in the bead report):
#  - MARKETING_VERSION / CURRENT_PROJECT_VERSION: VERSION file and git count.
#  - CODE_SIGN_STYLE=Manual + CODE_SIGN_IDENTITY: project default is Automatic,
#    which signs Release with "Apple Development"; Manual with the explicit
#    Developer ID identity is what reliably yields a Developer ID signature.
#  - DEVELOPMENT_TEAM: pinned so the team never drifts from the identity.
#  - OTHER_CODE_SIGN_FLAGS=--timestamp: secure timestamp, required by notarization.
#  - CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO: otherwise Xcode injects
#    com.apple.security.get-task-allow, which the notary service rejects.
#  - ENABLE_HARDENED_RUNTIME=YES: required by notarization (also set in project.yml,
#    repeated here so the script is self-sufficient).
echo "==> Building ${APP_NAME} ${VERSION} (build ${BUILD_NUMBER}) Release, signing with: ${CODESIGN_IDENTITY}"
if ! xcodebuild -project FloTile.xcodeproj -scheme "${APP_NAME}" -configuration Release \
        -derivedDataPath "${DERIVED}" build \
        MARKETING_VERSION="${VERSION}" \
        CURRENT_PROJECT_VERSION="${BUILD_NUMBER}" \
        CODE_SIGN_STYLE=Manual \
        CODE_SIGN_IDENTITY="${CODESIGN_IDENTITY}" \
        DEVELOPMENT_TEAM="${TEAM_ID}" \
        OTHER_CODE_SIGN_FLAGS="--timestamp" \
        ENABLE_HARDENED_RUNTIME=YES \
        CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO >>"${LOG}" 2>&1; then
    echo "error: xcodebuild failed (log: ${LOG}). Error lines:" >&2
    grep -E 'error:|\*\* BUILD FAILED' "${LOG}" | sort -u | head -n 10 >&2 || true
    echo "--- last log lines ---" >&2
    tail -n 15 "${LOG}" >&2
    exit 1
fi

PRODUCT="${DERIVED}/Build/Products/Release/${APP_NAME}.app"
if [ ! -d "${PRODUCT}" ]; then
    echo "error: built product not found at ${PRODUCT}" >&2
    exit 1
fi

rm -rf "${APP_BUNDLE}"
ditto "${PRODUCT}" "${APP_BUNDLE}"

echo "==> Verifying signature..."
codesign --verify --deep --strict --verbose=2 "${APP_BUNDLE}"
codesign -dvv "${APP_BUNDLE}" 2>&1 | grep -E 'Authority|TeamIdentifier|flags' || true

ENTITLEMENTS="$(codesign -d --entitlements :- "${APP_BUNDLE}" 2>/dev/null || true)"
echo "==> Entitlements:"
echo "${ENTITLEMENTS:-<none>}"
if printf '%s' "${ENTITLEMENTS}" | grep -q 'com.apple.security.app-sandbox'; then
    echo "error: ${APP_NAME}.app carries com.apple.security.app-sandbox; FloTile must NOT be sandboxed (Accessibility API)." >&2
    exit 1
fi

if printf '%s' "${ENTITLEMENTS}" | grep -q 'com.apple.security.get-task-allow'; then
    echo "error: ${APP_NAME}.app carries get-task-allow (debug entitlement); notarization would reject it." >&2
    exit 1
fi

echo "==> Built version: $("${SCRIPT_DIR}/read-app-version.sh" "${APP_BUNDLE}" short) (build $("${SCRIPT_DIR}/read-app-version.sh" "${APP_BUNDLE}" build))"
echo "==> Done: ${APP_BUNDLE}"
