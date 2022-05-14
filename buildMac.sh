#!/bin/sh

# Clean
xcodebuild clean archive -project Gladys.xcodeproj -scheme "MacGladys" -destination "generic/platform=OS X" -archivePath ~/Desktop/macgladys.xcarchive | xcpretty

if [ $? -eq 0 ]
then
echo
else
echo "!!! Archiving failed, stopping script"
exit 1
fi

# Upload to Dev ID
#xcodebuild -exportArchive -archivePath ~/Desktop/macgladys.xcarchive -exportPath ~/Desktop/GladysExport -exportOptionsPlist exportDevID.plist
#
#if [ $? -eq 0 ]
#then
#echo
#else
#echo "!!! Exporting failed, stopping script"
#exit 1
#fi

# Upload to App Store
xcodebuild -exportArchive -archivePath ~/Desktop/macgladys.xcarchive -exportPath ~/Desktop/GladysExport -exportOptionsPlist exportMac.plist

if [ $? -eq 0 ]
then
echo
else
echo "!!! Exporting failed, stopping script"
exit 1
fi

# Add to Xcode organizer
open ~/Desktop/macgladys.xcarchive
