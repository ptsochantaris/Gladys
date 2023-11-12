#!/bin/sh

DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer

# Clean
xcodebuild clean archive -project Gladys.xcodeproj -scheme "MacGladys" -destination "generic/platform=macOS" -archivePath ~/Desktop/macgladys.xcarchive

if [ $? -eq 0 ]
then
echo
else
echo "!!! Archiving failed, stopping script"
exit 1
fi

# Upload to App Store
xcodebuild -exportArchive -archivePath ~/Desktop/macgladys.xcarchive -exportPath ~/Desktop/GladysExport -allowProvisioningUpdates -exportOptionsPlist exportMac.plist

if [ $? -eq 0 ]
then
echo
else
echo "!!! Exporting failed, stopping script"
exit 1
fi

# Add to Xcode organizer
open ~/Desktop/macgladys.xcarchive
