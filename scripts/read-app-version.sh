#!/bin/bash
# Reads CFBundleShortVersionString / CFBundleVersion back OUT of a BUILT .app
# bundle's Info.plist, so the DMG name, tags and update manifests reflect what
# was actually built rather than what was merely intended.
#
# Usage:
#   scripts/read-app-version.sh short|build
#   scripts/read-app-version.sh [path-to-App.app] short|build
#
# Default path: build/FloTile.app. Exits non-zero with a stderr message if the
# bundle or key is missing.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

usage() {
    echo "Usage: $(basename "$0") [path-to-App.app] short|build" >&2
    exit 1
}

if [ "$#" -eq 2 ]; then
    APP_BUNDLE="$1"
    FIELD="$2"
elif [ "$#" -eq 1 ]; then
    APP_BUNDLE="${REPO_ROOT}/build/FloTile.app"
    FIELD="$1"
else
    usage
fi

case "${FIELD}" in
    short) PLIST_KEY="CFBundleShortVersionString" ;;
    build) PLIST_KEY="CFBundleVersion" ;;
    *) usage ;;
esac

INFO_PLIST="${APP_BUNDLE}/Contents/Info.plist"
if [ ! -f "${INFO_PLIST}" ]; then
    echo "error: no Info.plist found at ${INFO_PLIST} (build the app first)" >&2
    exit 1
fi

if ! /usr/libexec/PlistBuddy -c "Print :${PLIST_KEY}" "${INFO_PLIST}" 2>/dev/null; then
    echo "error: key ${PLIST_KEY} missing from ${INFO_PLIST}" >&2
    exit 1
fi
