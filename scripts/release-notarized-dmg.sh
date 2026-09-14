#!/usr/bin/env bash
set -euo pipefail

# Produces a signed, notarized DMG without placing Apple credentials in source.
# Required Keychain-backed inputs:
#   DEVELOPER_ID_APPLICATION='Developer ID Application: Your Name (TEAMID)'
#   DEVELOPMENT_TEAM=TEAMID
#   NOTARY_PROFILE=your-notarytool-keychain-profile
# Optional: RELEASE_VERSION=0.1.0

if [[ -z "${DEVELOPER_ID_APPLICATION:-}" || -z "${DEVELOPMENT_TEAM:-}" || -z "${NOTARY_PROFILE:-}" ]]; then
  echo "Set DEVELOPER_ID_APPLICATION, DEVELOPMENT_TEAM, and NOTARY_PROFILE before releasing." >&2
  exit 64
fi

release_version="${RELEASE_VERSION:-0.1.0}"
root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
release_dir="$root_dir/build/release/$release_version"
archive_path="$release_dir/MondayCommandCenter.xcarchive"
stage_dir="$release_dir/stage"
app_path="$archive_path/Products/Applications/Command Center.app"
zip_path="$release_dir/Command-Center-$release_version.zip"
dmg_path="$release_dir/Command-Center-$release_version.dmg"

rm -rf "$release_dir"
mkdir -p "$release_dir" "$stage_dir"

xcodegen generate --spec "$root_dir/project.yml" --project "$root_dir"

xcodebuild archive \
  -project "$root_dir/MondayCommandCenter.xcodeproj" \
  -scheme MondayCommandCenter \
  -configuration Release \
  -archivePath "$archive_path" \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY="$DEVELOPER_ID_APPLICATION" \
  OTHER_CODE_SIGN_FLAGS="--timestamp" \
  DEVELOPMENT_TEAM="$DEVELOPMENT_TEAM" \
  MARKETING_VERSION="$release_version" \
  CURRENT_PROJECT_VERSION=1

codesign --verify --deep --strict --verbose=2 "$app_path"
ditto -c -k --keepParent "$app_path" "$zip_path"
xcrun notarytool submit "$zip_path" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$app_path"

cp -R "$app_path" "$stage_dir/"
ln -s /Applications "$stage_dir/Applications"
hdiutil create -volname "MONDAY Command Center" -srcfolder "$stage_dir" -ov -format UDZO "$dmg_path"
codesign --force --timestamp --sign "$DEVELOPER_ID_APPLICATION" "$dmg_path"
codesign --verify --strict --verbose=2 "$dmg_path"
xcrun notarytool submit "$dmg_path" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$dmg_path"
spctl --assess --type execute --context context:primary-signature --verbose=4 "$app_path"
spctl --assess --type open --context context:primary-signature --verbose=4 "$dmg_path"

echo "Release DMG: $dmg_path"
