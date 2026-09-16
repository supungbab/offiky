#!/bin/bash
# 배포 빌드. Developer ID 로 서명한다. 공증은 하지 않는다.
#
# 받는 사람은 응용 프로그램 폴더에 넣은 뒤 한 번만 아래를 실행해야 한다.
#   xattr -dr com.apple.quarantine /Applications/offiky.app
#
# 이 단계를 없애려면 공증이 필요하다. Apple 큐가 몇 시간씩 밀리는 날이 있고
# 취소할 방법이 없어서 뺐다. 다시 넣으려면 서명 뒤에 이 순서로 붙인다.
#   xcrun notarytool submit <zip> --keychain-profile <프로파일> --wait
#   xcrun stapler staple <앱>        # DMG 도 서명·제출·스테이플을 따로 한다
# submit 은 거부돼도 0 을 반환하므로 출력에서 "status: Accepted" 를 직접 확인해야 한다.
set -euo pipefail

IDENTITY="Developer ID Application: MyeongHo Kyeong (75J3AS52HQ)"
BUILD=/tmp/offiky-release
OUT=~/Desktop/offiky.zip
DMG=~/Desktop/offiky.dmg
APP="$BUILD/Build/Products/Release/offiky.app"

rm -rf "$BUILD"
xcodebuild -project offiky.xcodeproj -scheme offiky -configuration Release \
  -destination 'platform=macOS' -derivedDataPath "$BUILD" \
  CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="$IDENTITY" \
  DEVELOPMENT_TEAM=75J3AS52HQ PROVISIONING_PROFILE_SPECIFIER="" \
  OTHER_CODE_SIGN_FLAGS="--timestamp" \
  CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO \
  build | grep -E "Signing Identity|BUILD SUCCEEDED|error:"
codesign -v --deep --strict "$APP"

rm -f "$OUT" "$DMG"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$OUT"
STAGE=$(mktemp -d)
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname offiky -srcfolder "$STAGE" -ov -format UDZO -quiet "$DMG"
rm -rf "$STAGE"

echo "완료"
echo "  $OUT  ($(du -h "$OUT" | cut -f1))"
echo "  $DMG  ($(du -h "$DMG" | cut -f1))"
echo
echo "받는 사람이 응용 프로그램 폴더에 넣은 뒤 한 번 실행해야 열린다:"
echo "  xattr -dr com.apple.quarantine /Applications/offiky.app"
