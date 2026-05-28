#!/usr/bin/env bash
#
# Lint and format Swift sources. Run from the repo root.
#
#   scripts/lint.sh         Check formatting + lint (matches CI).
#   scripts/lint.sh --fix   Reformat in place and apply SwiftLint autocorrections.
#
set -euo pipefail

DIRS=(SentryReplayDebugger SentryReplayDebuggerTests SentryReplayDebuggerUITests)

if [[ "${1:-}" == "--fix" ]]; then
    xcrun swift-format format --in-place --recursive --configuration .swift-format "${DIRS[@]}"
    swiftlint --fix --config .swiftlint.yml
    echo "Formatted and autocorrected."
else
    xcrun swift-format lint --strict --recursive --configuration .swift-format "${DIRS[@]}"
    swiftlint lint --config .swiftlint.yml
fi
