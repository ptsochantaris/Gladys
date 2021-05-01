#!/bin/sh

# Clean
xcodebuild clean -project Gladys.xcodeproj -scheme "Gladys" | xcpretty

if [ $? -eq 0 ]
then
echo
else
echo "!!! Cleaning failed, stopping script"
exit 1
fi

# Build
xcodebuild archive -project Gladys.xcodeproj -scheme "Gladys" -destination generic/platform=iOS -archivePath ~/Desktop/gladys.xcarchive | xcpretty

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
