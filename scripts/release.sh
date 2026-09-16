#!/bin/bash
# 사내 테스트용 빌드. 인증서 없이 애드혹으로 서명한다.
#
# 받는 사람은 압축을 푼 뒤 한 번만 아래를 실행해야 한다.
#   xattr -dr com.apple.quarantine /Applications/offiky.app
#
# 이 단계를 없애려면 Developer ID 로 서명하고 공증해야 한다. 그때는
# CODE_SIGN_IDENTITY 를 "Developer ID Application: ..." 로 바꾸고
# notarytool submit --wait, stapler staple 을 뒤에 붙인다.
set -euo pipefail

BUILD=/tmp/offiky-release
OUT=~/Desktop/offiky.zip
DMG=~/Desktop/offiky.dmg
APP="$BUILD/Build/Products/Release/offiky.app"

rm -rf "$BUILD" "$OUT" "$DMG"
xcodebuild -project offiky.xcodeproj -scheme offiky -configuration Release \
  -destination 'platform=macOS' -derivedDataPath "$BUILD" \
  CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="-" \
  DEVELOPMENT_TEAM="" PROVISIONING_PROFILE_SPECIFIER="" \
  build | grep -E "Signing Identity|BUILD SUCCEEDED|error:"

codesign -v --deep --strict "$APP"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$OUT"

# 응용 프로그램 폴더 바로가기를 같이 넣어 드래그로 설치하게 한다.
# 격리 꼬리표는 그대로 붙지만, 앱이 늘 /Applications 에 놓이므로
# 안내하는 xattr 경로가 어긋나지 않는다.
STAGE=$(mktemp -d)
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname offiky -srcfolder "$STAGE" -ov -format UDZO -quiet "$DMG"
rm -rf "$STAGE"

echo "완료"
echo "  $OUT  ($(du -h "$OUT" | cut -f1))"
echo "  $DMG  ($(du -h "$DMG" | cut -f1))"
