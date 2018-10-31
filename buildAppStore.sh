BUILD=`/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "Gladys/Info.plist"`
BUILD=$((BUILD + 1))

echo "Will send up build $BUILD..."
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD" "Gladys/Info.plist"

xcodebuild clean -workspace Gladys.xcworkspace -scheme "Gladys" | xcpretty
xcodebuild archive -workspace Gladys.xcworkspace -scheme "Gladys" -destination generic/platform=iOS -archivePath ~/Desktop/gladys-release.xcarchive | xcpretty
xcodebuild -exportArchive -archivePath ~/Desktop/gladys-release.xcarchive -exportPath ~/Desktop/GladysAppStore -exportOptionsPlist exportAppStoreOptions.plist
open ~/Desktop/gladys-release.xcarchive
