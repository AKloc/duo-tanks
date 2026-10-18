#!/bin/zsh
# Archives Duo Tanks and uploads it to App Store Connect.
# Usage: TEAM_ID=AB12CD34EF scripts/upload.sh
# Bump CURRENT_PROJECT_VERSION in project.yml before each new upload.
set -euo pipefail
cd "$(dirname "$0")/.."

: "${TEAM_ID:?Set TEAM_ID to your 10-character Apple Developer Team ID}"
archive=build/DuoTanks.xcarchive
options=build/ExportOptions.plist

xcodegen generate

cat > "$options" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key><string>app-store-connect</string>
    <key>destination</key><string>upload</string>
    <key>teamID</key><string>$TEAM_ID</string>
    <key>signingStyle</key><string>automatic</string>
</dict>
</plist>
PLIST

xcodebuild archive -project DuoTanks.xcodeproj -scheme DuoTanks -configuration Release \
    -destination 'generic/platform=iOS' -archivePath "$archive" \
    DEVELOPMENT_TEAM="$TEAM_ID" CODE_SIGN_STYLE=Automatic -allowProvisioningUpdates

xcodebuild -exportArchive -archivePath "$archive" -exportOptionsPlist "$options" \
    -exportPath build/export -allowProvisioningUpdates

echo "Uploaded. The build appears in App Store Connect after processing (usually 10–30 minutes)."
