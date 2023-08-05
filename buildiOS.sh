#!/bin/sh

DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer

# Build
xcodebuild clean archive -project Gladys.xcodeproj -scheme "Gladys" -destination generic/platform=iOS -archivePath ~/Desktop/gladys.xcarchive

if [ $? -eq 0 ]
then
echo
else
echo "!!! Archiving failed, stopping script"
exit 1
fi

# Upload to App Store
xcodebuild -exportArchive -archivePath ~/Desktop/gladys.xcarchive -exportPath ~/Desktop/GladysExport -exportOptionsPlist exportiOS.plist

if [ $? -eq 0 ]
then
echo
else
echo "!!! Exporting failed, stopping script"
exit 1
fi

# Add to Xcode organizer
open ~/Desktop/gladys.xcarchive
