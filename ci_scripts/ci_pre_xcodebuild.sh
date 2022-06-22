#!/bin/sh

echo "Setting build number"
sed -i '' -e 's/CURRENT_PROJECT_VERSION \= [^\;]*\;/CURRENT_PROJECT_VERSION = $CI_BUILD_NUMBER;/' ./parent/Gladys.xcodeproj/project.pbxproj
echo "Done"
