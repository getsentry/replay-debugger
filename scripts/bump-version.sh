#!/bin/bash
set -eux

OLD_VERSION="${1}"
NEW_VERSION="${2}"

if [[ -z "$OLD_VERSION" || -z "$NEW_VERSION" ]]; then
    echo "Error: Both old and new version arguments are required" >&2
    echo "Usage: $0 <old_version> <new_version>" >&2
    exit 1
fi

SCRIPT_DIR="$(dirname "${BASH_SOURCE[0]}")"
PROJECT_ROOT="${SCRIPT_DIR}/.."
PROJECT_FILE="${PROJECT_ROOT}/SentryReplayDebugger.xcodeproj/project.pbxproj"

if [[ ! -f "$PROJECT_FILE" ]]; then
    echo "Error: Project file not found at $PROJECT_FILE" >&2
    exit 1
fi

# Update MARKETING_VERSION and CURRENT_PROJECT_VERSION in project file
sed -i '' -e "s/MARKETING_VERSION = [^;]*/MARKETING_VERSION = $NEW_VERSION/g" \
          -e "s/CURRENT_PROJECT_VERSION = [^;]*/CURRENT_PROJECT_VERSION = $NEW_VERSION/g" \
          "$PROJECT_FILE"

echo "Updated version from $OLD_VERSION to $NEW_VERSION"
