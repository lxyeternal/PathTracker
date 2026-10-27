#!/bin/zsh
# Archives the iPhone app (with its Apple Watch app) and uploads it to App Store Connect for
# TestFlight. Run from the repository root:  zsh AppStore/upload.sh
# Needs: the app created in App Store Connect, and your developer account signed in to Xcode
# (Xcode › Settings › Accounts).
set -e
cd "$(dirname "$0")/.."

ARCHIVE=build/Waytrace.xcarchive
# Every upload needs a new build number; the time of the upload always is one.
BUILD=$(date +%Y%m%d%H%M)

echo "Archiving build $BUILD…"
xcodebuild -project RecordPath.xcodeproj -scheme RecordPath -configuration Release \
  -destination 'generic/platform=iOS' -archivePath "$ARCHIVE" \
  -allowProvisioningUpdates CURRENT_PROJECT_VERSION="$BUILD" \
  archive | grep -E "error:|warning: .*signing|ARCHIVE" || true

[ -d "$ARCHIVE" ] || { echo "The archive failed; open the project in Xcode and try Product › Archive to see why."; exit 1; }

echo "Uploading…"
xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportPath build/export \
  -exportOptionsPlist AppStore/ExportOptions.plist -allowProvisioningUpdates \
  | grep -E "error:|EXPORT|Upload|uploaded" || true

echo "Done. The build shows up in App Store Connect › TestFlight after processing (usually 10–30 minutes)."
