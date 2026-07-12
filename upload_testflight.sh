#!/usr/bin/env bash
# upload_testflight.sh — archive, export and upload Wellnario to TestFlight.
#
# Required environment variables (normally saved in a local .env file):
#   APP_STORE_CONNECT_API_KEY_ID
#   APP_STORE_CONNECT_API_ISSUER_ID
#   APP_STORE_CONNECT_API_KEY_PATH
#
# Optional:
#   TESTFLIGHT_TEAM_ID                     Defaults to Wellnario's team ID.
#   TESTFLIGHT_BUNDLE_ID                   Defaults to com.dtigl.wellnario.ios.
#   TESTFLIGHT_BUILD_NUMBER                Defaults to YYYYMMDDHHMM.
#   TESTFLIGHT_BUILD_NAME                  Overrides MARKETING_VERSION (for example 1.0.1).
#   TESTFLIGHT_ARCHIVE_PATH                Defaults under build/testflight/.
#   TESTFLIGHT_EXPORT_PATH                 Defaults under build/testflight/.
#   TESTFLIGHT_EXPORT_OPTIONS_PLIST        Uses a custom ExportOptions.plist as-is.
#   TESTFLIGHT_PROVISIONING_PROFILE        Enables manual signing only while exporting.
#   TESTFLIGHT_PROVISIONING_PROFILE_PATH   Installs a local .mobileprovision first.
#   TESTFLIGHT_SIGNING_CERTIFICATE         Defaults to "Apple Distribution" for manual export.
#   TESTFLIGHT_ALLOW_PROVISIONING_UPDATES  Defaults to 1.
#   TESTFLIGHT_SKIP_BUILD=1                Upload an already exported IPA.
#   TESTFLIGHT_SKIP_UPLOAD=1               Archive and export without uploading.
#   TESTFLIGHT_UPLOAD_TOOL                 transporter (default) or altool.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_PATH="$ROOT_DIR/Wellnario.xcodeproj"
SCHEME="Wellnario"
DEFAULT_TEAM_ID="73ZVWQPH3Z"
DEFAULT_BUNDLE_ID="com.dtigl.wellnario.ios"

usage() {
  printf '%s\n' \
    "Usage: ./upload_testflight.sh" \
    "" \
    "Loads optional credentials from $ROOT_DIR/.env, then archives and uploads Wellnario." \
    "Set TESTFLIGHT_SKIP_UPLOAD=1 to validate the signed IPA without sending it."
}

if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
  usage
  exit 0
fi

load_env() {
  if [ -f "$ROOT_DIR/.env" ]; then
    set -a
    # shellcheck disable=SC1091
    source "$ROOT_DIR/.env"
    set +a
  fi
}

require_var() {
  local name="$1"
  if [ -z "${!name:-}" ]; then
    printf 'Error: %s is not set.\n' "$name" >&2
    exit 1
  fi
}

find_ipa() {
  local export_path="$1"
  local ipa
  ipa="$(find "$export_path" -maxdepth 1 -type f -name '*.ipa' -print 2>/dev/null | head -n 1 || true)"
  if [ -z "$ipa" ]; then
    printf 'Error: no IPA was found in %s.\n' "$export_path" >&2
    exit 1
  fi
  printf '%s\n' "$ipa"
}

install_provisioning_profile() {
  local profile_path="$1"
  local profile_plist
  local profile_uuid
  local profile_name
  local profiles_directory="$HOME/Library/MobileDevice/Provisioning Profiles"

  if [ ! -f "$profile_path" ]; then
    printf 'Error: provisioning profile does not exist: %s\n' "$profile_path" >&2
    exit 1
  fi

  profile_plist="$TEMPORARY_DIRECTORY/profile.plist"
  security cms -D -i "$profile_path" > "$profile_plist"
  profile_uuid="$(/usr/libexec/PlistBuddy -c 'Print :UUID' "$profile_plist")"
  profile_name="$(/usr/libexec/PlistBuddy -c 'Print :Name' "$profile_plist")"
  mkdir -p "$profiles_directory"
  cp "$profile_path" "$profiles_directory/$profile_uuid.mobileprovision"
  TESTFLIGHT_PROVISIONING_PROFILE="$profile_name"
  export TESTFLIGHT_PROVISIONING_PROFILE
  printf "Installed provisioning profile '%s'.\n" "$profile_name"
}

prepare_export_options() {
  local destination="$TEMPORARY_DIRECTORY/ExportOptions.plist"
  local bundle_id="$1"
  local team_id="$2"

  if [ -n "${TESTFLIGHT_EXPORT_OPTIONS_PLIST:-}" ]; then
    if [ ! -f "$TESTFLIGHT_EXPORT_OPTIONS_PLIST" ]; then
      printf 'Error: export options plist does not exist: %s\n' "$TESTFLIGHT_EXPORT_OPTIONS_PLIST" >&2
      exit 1
    fi
    printf '%s\n' "$TESTFLIGHT_EXPORT_OPTIONS_PLIST"
    return
  fi

  plutil -create xml1 "$destination"
  /usr/libexec/PlistBuddy -c 'Add :method string app-store-connect' "$destination"
  /usr/libexec/PlistBuddy -c 'Add :destination string export' "$destination"
  /usr/libexec/PlistBuddy -c "Add :teamID string $team_id" "$destination"
  /usr/libexec/PlistBuddy -c 'Add :stripSwiftSymbols bool true' "$destination"
  /usr/libexec/PlistBuddy -c 'Add :uploadSymbols bool true' "$destination"

  if [ -n "${TESTFLIGHT_PROVISIONING_PROFILE:-}" ]; then
    /usr/libexec/PlistBuddy -c 'Add :signingStyle string manual' "$destination"
    /usr/libexec/PlistBuddy -c 'Add :provisioningProfiles dict' "$destination"
    /usr/libexec/PlistBuddy -c "Add :provisioningProfiles:$bundle_id string $TESTFLIGHT_PROVISIONING_PROFILE" "$destination"
    /usr/libexec/PlistBuddy -c "Add :signingCertificate string ${TESTFLIGHT_SIGNING_CERTIFICATE:-Apple Distribution}" "$destination"
  else
    /usr/libexec/PlistBuddy -c 'Add :signingStyle string automatic' "$destination"
  fi

  printf '%s\n' "$destination"
}

verify_ipa() {
  local ipa_path="$1"
  local expected_bundle_id="$2"
  local expected_build_number="$3"
  local verification_directory="$TEMPORARY_DIRECTORY/ipa"
  local app_path
  local info_plist
  local actual_bundle_id
  local actual_build_number

  mkdir -p "$verification_directory"
  unzip -q "$ipa_path" -d "$verification_directory"
  app_path="$(find "$verification_directory/Payload" -maxdepth 1 -type d -name '*.app' -print | head -n 1 || true)"
  if [ -z "$app_path" ]; then
    printf 'Error: no app bundle was found inside %s.\n' "$ipa_path" >&2
    exit 1
  fi

  info_plist="$app_path/Info.plist"
  actual_bundle_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$info_plist")"
  actual_build_number="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$info_plist")"
  if [ "$actual_bundle_id" != "$expected_bundle_id" ]; then
    printf 'Error: IPA bundle ID is %s; expected %s.\n' "$actual_bundle_id" "$expected_bundle_id" >&2
    exit 1
  fi
  if [ "$actual_build_number" != "$expected_build_number" ]; then
    printf 'Error: IPA build number is %s; expected %s.\n' "$actual_build_number" "$expected_build_number" >&2
    exit 1
  fi
}

upload_with_transporter() {
  local ipa_path="$1"
  xcrun iTMSTransporter \
    -m upload \
    -assetFile "$ipa_path" \
    -apiKey "$APP_STORE_CONNECT_API_KEY_ID" \
    -apiIssuer "$APP_STORE_CONNECT_API_ISSUER_ID"
}

upload_with_altool() {
  local ipa_path="$1"
  xcrun altool \
    --upload-app \
    --type ios \
    --file "$ipa_path" \
    --apiKey "$APP_STORE_CONNECT_API_KEY_ID" \
    --apiIssuer "$APP_STORE_CONNECT_API_ISSUER_ID"
}

load_env

require_var APP_STORE_CONNECT_API_KEY_ID
require_var APP_STORE_CONNECT_API_ISSUER_ID
require_var APP_STORE_CONNECT_API_KEY_PATH

if [ ! -f "$APP_STORE_CONNECT_API_KEY_PATH" ]; then
  printf 'Error: APP_STORE_CONNECT_API_KEY_PATH does not exist: %s\n' "$APP_STORE_CONNECT_API_KEY_PATH" >&2
  exit 1
fi
if [ ! -d "$PROJECT_PATH" ]; then
  printf 'Error: Xcode project does not exist: %s\n' "$PROJECT_PATH" >&2
  exit 1
fi

TEMPORARY_DIRECTORY="$(mktemp -d "${TMPDIR:-/tmp}/wellnario-testflight.XXXXXX")"
trap 'rm -rf "$TEMPORARY_DIRECTORY"' EXIT

if [ -n "${TESTFLIGHT_PROVISIONING_PROFILE_PATH:-}" ]; then
  install_provisioning_profile "$TESTFLIGHT_PROVISIONING_PROFILE_PATH"
fi

team_id="${TESTFLIGHT_TEAM_ID:-$DEFAULT_TEAM_ID}"
bundle_id="${TESTFLIGHT_BUNDLE_ID:-$DEFAULT_BUNDLE_ID}"
build_number="${TESTFLIGHT_BUILD_NUMBER:-$(date +%Y%m%d%H%M)}"
build_name="${TESTFLIGHT_BUILD_NAME:-}"
build_root="${TESTFLIGHT_BUILD_ROOT:-$ROOT_DIR/build/testflight}"
archive_path="${TESTFLIGHT_ARCHIVE_PATH:-$build_root/Wellnario-$build_number.xcarchive}"
export_path="${TESTFLIGHT_EXPORT_PATH:-$build_root/Wellnario-$build_number}"
export_options_plist="$(prepare_export_options "$bundle_id" "$team_id")"

if [ "${TESTFLIGHT_SKIP_BUILD:-0}" != "1" ]; then
  if [ -e "$archive_path" ] || [ -e "$export_path" ]; then
    printf 'Error: build output already exists for build %s. Choose another TESTFLIGHT_BUILD_NUMBER.\n' "$build_number" >&2
    exit 1
  fi

  mkdir -p "$build_root"
  provisioning_arguments=()
  if [ "${TESTFLIGHT_ALLOW_PROVISIONING_UPDATES:-1}" != "0" ]; then
    provisioning_arguments=(
      -allowProvisioningUpdates
      -authenticationKeyPath "$APP_STORE_CONNECT_API_KEY_PATH"
      -authenticationKeyID "$APP_STORE_CONNECT_API_KEY_ID"
      -authenticationKeyIssuerID "$APP_STORE_CONNECT_API_ISSUER_ID"
    )
  fi

  archive_arguments=(
    xcodebuild archive
    -project "$PROJECT_PATH"
    -scheme "$SCHEME"
    -configuration Release
    -destination 'generic/platform=iOS'
    -archivePath "$archive_path"
    "DEVELOPMENT_TEAM=$team_id"
    CODE_SIGN_STYLE=Automatic
    "CURRENT_PROJECT_VERSION=$build_number"
  )
  if [ -n "$build_name" ]; then
    archive_arguments+=("MARKETING_VERSION=$build_name")
  fi

  printf 'Archiving Wellnario %s (%s)…\n' "${build_name:-project version}" "$build_number"
  "${archive_arguments[@]}" "${provisioning_arguments[@]}"

  printf 'Exporting IPA…\n'
  xcodebuild -exportArchive \
    -archivePath "$archive_path" \
    -exportPath "$export_path" \
    -exportOptionsPlist "$export_options_plist" \
    "${provisioning_arguments[@]}"
fi

ipa_path="$(find_ipa "$export_path")"
verify_ipa "$ipa_path" "$bundle_id" "$build_number"
printf 'Exported IPA: %s\n' "$ipa_path"

if [ "${TESTFLIGHT_SKIP_UPLOAD:-0}" = "1" ]; then
  printf 'TESTFLIGHT_SKIP_UPLOAD=1: archive and export completed without uploading.\n'
  exit 0
fi

api_key_directory="$HOME/.appstoreconnect/private_keys"
expected_key_path="$api_key_directory/AuthKey_${APP_STORE_CONNECT_API_KEY_ID}.p8"
mkdir -p "$api_key_directory"
if [ "$APP_STORE_CONNECT_API_KEY_PATH" != "$expected_key_path" ]; then
  cp "$APP_STORE_CONNECT_API_KEY_PATH" "$expected_key_path"
  chmod 600 "$expected_key_path"
fi

upload_tool="${TESTFLIGHT_UPLOAD_TOOL:-transporter}"
printf 'Uploading to TestFlight with %s…\n' "$upload_tool"
case "$upload_tool" in
  transporter)
    upload_with_transporter "$ipa_path"
    ;;
  altool)
    upload_with_altool "$ipa_path"
    ;;
  *)
    printf "Error: TESTFLIGHT_UPLOAD_TOOL must be 'transporter' or 'altool'.\n" >&2
    exit 1
    ;;
esac

printf 'Upload completed. App Store Connect may need a few minutes to process the build.\n'
