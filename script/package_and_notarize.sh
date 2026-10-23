#!/bin/zsh
#
#  Created by ktiays on 2026/7/14.
#  Copyright (c) 2026 ktiays. All rights reserved.
#

set -euo pipefail

readonly SCRIPT_DIR="${0:A:h}"
readonly PROJECT_ROOT="${SCRIPT_DIR:h}"
readonly PROJECT_PATH="${PROJECT_ROOT}/TextAnywhere.xcodeproj"
readonly SCHEME="TextAnywhere"
readonly CONFIGURATION="Release"
readonly PRODUCT_NAME="TextAnywhere"
readonly BUILD_ROOT="${PROJECT_ROOT}/.build/distribution"
readonly DERIVED_DATA_PATH="${BUILD_ROOT}/DerivedData"
readonly ARCHIVE_PATH="${BUILD_ROOT}/${PRODUCT_NAME}.xcarchive"
readonly APP_PATH="${ARCHIVE_PATH}/Products/Applications/${PRODUCT_NAME}.app"
readonly SUBMISSION_ARCHIVE="${BUILD_ROOT}/.notarization-upload.zip"
readonly SUBMISSION_RESULT_PATH="${BUILD_ROOT}/notary-submission.plist"
readonly STATUS_RESULT_PATH="${BUILD_ROOT}/notary-status.plist"
readonly NOTARIZATION_LOG_PATH="${BUILD_ROOT}/notary-log.json"

NOTARYTOOL_PROFILE="${NOTARYTOOL_PROFILE:-}"
SIGNING_IDENTITY="${SIGNING_IDENTITY:-}"
DEVELOPMENT_TEAM="${DEVELOPMENT_TEAM:-}"
POLL_INTERVAL_SECONDS="${POLL_INTERVAL_SECONDS:-20}"
OUTPUT_PATH="${OUTPUT_PATH:-}"
MARKETING_VERSION="${MARKETING_VERSION:-}"
CURRENT_PROJECT_VERSION="${CURRENT_PROJECT_VERSION:-}"

print_usage() {
    /bin/cat <<'EOF'
Build, sign, notarize, staple, and package TextAnywhere.

Usage:
  NOTARYTOOL_PROFILE=<profile> ./script/package_and_notarize.sh

Required environment:
  NOTARYTOOL_PROFILE       Keychain profile created by `xcrun notarytool store-credentials`.

Optional environment:
  SIGNING_IDENTITY         Full Developer ID Application identity. Auto-detected when omitted.
  DEVELOPMENT_TEAM         Apple Developer team ID. Inferred from the signing identity when omitted.
  POLL_INTERVAL_SECONDS    Seconds between notarization status checks. Defaults to 20.
  OUTPUT_PATH              Final ZIP path. Relative paths are resolved from the project root.
  MARKETING_VERSION        Overrides the project's marketing version (CFBundleShortVersionString).
  CURRENT_PROJECT_VERSION  Overrides the project's build number (CFBundleVersion).

Example credential setup:
  xcrun notarytool store-credentials "TextAnywhere" \
    --apple-id "developer@example.com" \
    --team-id "TEAMID" \
    --password "app-specific-password"
EOF
}

fail() {
    print -u2 -- "error: $*"
    exit 1
}

require_command() {
    command -v "$1" >/dev/null 2>&1 || fail "Required command not found: $1"
}

fetch_notarization_log() {
    local submission_id="$1"
    if xcrun notarytool log \
        --keychain-profile "$NOTARYTOOL_PROFILE" \
        "$submission_id" \
        "$NOTARIZATION_LOG_PATH"; then
        print -- "Notarization log: ${NOTARIZATION_LOG_PATH}"
    else
        print -u2 -- "warning: Unable to retrieve the notarization log."
    fi
}

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    print_usage
    exit 0
fi

if (( $# != 0 )); then
    print_usage
    fail "Unexpected arguments: $*"
fi

require_command xcodebuild
require_command xcrun
require_command codesign
require_command ditto
require_command plutil
require_command security
require_command spctl

[[ -n "$NOTARYTOOL_PROFILE" ]] || fail \
    "Set NOTARYTOOL_PROFILE to a Keychain profile created with xcrun notarytool store-credentials."
[[ "$POLL_INTERVAL_SECONDS" =~ ^[1-9][0-9]*$ ]] || fail \
    "POLL_INTERVAL_SECONDS must be a positive integer."

if ! SIGNING_IDENTITIES="$(security find-identity -v -p codesigning)"; then
    fail "Unable to read code-signing identities from the Keychain."
fi

if [[ -z "$SIGNING_IDENTITY" ]]; then
    SIGNING_IDENTITY="$(
        print -r -- "$SIGNING_IDENTITIES" \
            | /usr/bin/awk -F '"' '/Developer ID Application:/ { print $2; exit }'
    )"
fi

[[ -n "$SIGNING_IDENTITY" ]] || fail \
    "No Developer ID Application identity was found. Install its certificate and private key, or set SIGNING_IDENTITY."
print -r -- "$SIGNING_IDENTITIES" | /usr/bin/grep -F "\"${SIGNING_IDENTITY}\"" >/dev/null \
    || fail "The requested signing identity is not valid in the current Keychain: ${SIGNING_IDENTITY}"

if [[ -z "$DEVELOPMENT_TEAM" ]]; then
    DEVELOPMENT_TEAM="$(
        print -r -- "$SIGNING_IDENTITY" \
            | /usr/bin/sed -nE 's/.*\(([A-Z0-9]+)\)$/\1/p'
    )"
fi
[[ -n "$DEVELOPMENT_TEAM" ]] || fail \
    "Unable to infer the team ID from the signing identity. Set DEVELOPMENT_TEAM explicitly."

VERSION_OVERRIDES=()
[[ -n "$MARKETING_VERSION" ]] && VERSION_OVERRIDES+=("MARKETING_VERSION=${MARKETING_VERSION}")
[[ -n "$CURRENT_PROJECT_VERSION" ]] && VERSION_OVERRIDES+=("CURRENT_PROJECT_VERSION=${CURRENT_PROJECT_VERSION}")

/bin/mkdir -p "$BUILD_ROOT"
/bin/rm -rf "$DERIVED_DATA_PATH" "$ARCHIVE_PATH"
/bin/rm -f \
    "$SUBMISSION_ARCHIVE" \
    "$SUBMISSION_RESULT_PATH" \
    "$STATUS_RESULT_PATH" \
    "$NOTARIZATION_LOG_PATH"

print -- "Archiving ${PRODUCT_NAME} with ${SIGNING_IDENTITY}..."
xcodebuild \
    -project "$PROJECT_PATH" \
    -scheme "$SCHEME" \
    -configuration "$CONFIGURATION" \
    -destination "generic/platform=macOS" \
    -derivedDataPath "$DERIVED_DATA_PATH" \
    -archivePath "$ARCHIVE_PATH" \
    archive \
    CODE_SIGN_STYLE=Manual \
    CODE_SIGN_IDENTITY="$SIGNING_IDENTITY" \
    DEVELOPMENT_TEAM="$DEVELOPMENT_TEAM" \
    OTHER_CODE_SIGN_FLAGS="--timestamp" \
    "${VERSION_OVERRIDES[@]}"

[[ -d "$APP_PATH" ]] || fail "Archive did not contain ${APP_PATH}."

print -- "Verifying the Developer ID signature and Hardened Runtime..."
codesign --verify --deep --strict --verbose=2 "$APP_PATH"
SIGNATURE_DETAILS="$(codesign -dvvv "$APP_PATH" 2>&1)"
[[ "$SIGNATURE_DETAILS" == *"Authority=Developer ID Application:"* ]] || fail \
    "The archived app is not signed with a Developer ID Application certificate."
[[ "$SIGNATURE_DETAILS" == *"runtime"* ]] || fail \
    "The archived app is not signed with Hardened Runtime enabled."

print -- "Creating the notarization upload archive..."
ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$SUBMISSION_ARCHIVE"

print -- "Submitting ${PRODUCT_NAME} for notarization..."
if ! xcrun notarytool submit \
    --keychain-profile "$NOTARYTOOL_PROFILE" \
    --output-format plist \
    "$SUBMISSION_ARCHIVE" > "$SUBMISSION_RESULT_PATH"; then
    fail "Notarization submission failed before a submission ID was returned."
fi

if ! SUBMISSION_ID="$(
    plutil -extract id raw -o - "$SUBMISSION_RESULT_PATH" 2>/dev/null
)"; then
    fail "The notarization response did not contain a submission ID. See ${SUBMISSION_RESULT_PATH}."
fi
[[ -n "$SUBMISSION_ID" ]] || fail \
    "The notarization response contained an empty submission ID. See ${SUBMISSION_RESULT_PATH}."

print -- "Notarization submission ID: ${SUBMISSION_ID}"
print -- "Polling every ${POLL_INTERVAL_SECONDS} seconds until Apple returns a terminal result..."

while true; do
    if ! xcrun notarytool info \
        --keychain-profile "$NOTARYTOOL_PROFILE" \
        --output-format plist \
        "$SUBMISSION_ID" > "$STATUS_RESULT_PATH"; then
        print -u2 -- "$(/bin/date '+%Y-%m-%d %H:%M:%S') Status check failed; retrying."
        /bin/sleep "$POLL_INTERVAL_SECONDS"
        continue
    fi

    if ! NOTARIZATION_STATUS="$(
        plutil -extract status raw -o - "$STATUS_RESULT_PATH" 2>/dev/null
    )"; then
        print -u2 -- "$(/bin/date '+%Y-%m-%d %H:%M:%S') Status response was unreadable; retrying."
        /bin/sleep "$POLL_INTERVAL_SECONDS"
        continue
    fi

    print -- "$(/bin/date '+%Y-%m-%d %H:%M:%S') Notarization status: ${NOTARIZATION_STATUS}"

    case "$NOTARIZATION_STATUS" in
        Accepted)
            fetch_notarization_log "$SUBMISSION_ID"
            break
            ;;
        Invalid|Rejected|Failed)
            fetch_notarization_log "$SUBMISSION_ID"
            fail "Notarization finished with status: ${NOTARIZATION_STATUS}"
            ;;
        *)
            /bin/sleep "$POLL_INTERVAL_SECONDS"
            ;;
    esac
done

print -- "Stapling and validating the notarization ticket..."
xcrun stapler staple -v "$APP_PATH"
xcrun stapler validate -v "$APP_PATH"
codesign --verify --deep --strict --verbose=2 "$APP_PATH"
spctl --assess --type execute --verbose=4 "$APP_PATH"

APP_VERSION="$(plutil -extract CFBundleShortVersionString raw -o - "$APP_PATH/Contents/Info.plist")"
APP_BUILD="$(plutil -extract CFBundleVersion raw -o - "$APP_PATH/Contents/Info.plist")"

if [[ -z "$OUTPUT_PATH" ]]; then
    FINAL_ARCHIVE="${BUILD_ROOT}/${PRODUCT_NAME}-${APP_VERSION}-${APP_BUILD}.zip"
elif [[ "$OUTPUT_PATH" == /* ]]; then
    FINAL_ARCHIVE="$OUTPUT_PATH"
else
    FINAL_ARCHIVE="${PROJECT_ROOT}/${OUTPUT_PATH}"
fi

/bin/mkdir -p "${FINAL_ARCHIVE:h}"
/bin/rm -f "$FINAL_ARCHIVE"
ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$FINAL_ARCHIVE"
/bin/rm -f "$SUBMISSION_ARCHIVE"

print -- "Packaging complete: ${FINAL_ARCHIVE}"
