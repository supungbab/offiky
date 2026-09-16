#!/bin/bash
# 배포 빌드. Developer ID 로 서명하고 앱과 DMG 를 모두 공증한다.
# 공증까지 끝나면 받는 사람은 드래그해서 넣고 더블클릭만 하면 된다.
#
# 공증 자격증명은 한 번만 만들면 된다. 앱 암호는
# account.apple.com > 로그인 및 보안 > 앱 암호 에서 발급한다.
#
#   xcrun notarytool store-credentials offiky \
#     --apple-id supungbab@gmail.com --team-id 75J3AS52HQ --password <앱-암호>
set -euo pipefail

IDENTITY="Developer ID Application: MyeongHo Kyeong (75J3AS52HQ)"
PROFILE="${1:-offiky}"
BUILD=/tmp/offiky-release
OUT=~/Desktop/offiky.zip
DMG=~/Desktop/offiky.dmg
APP="$BUILD/Build/Products/Release/offiky.app"

rm -rf "$BUILD" "$OUT" "$DMG"
xcodebuild -project offiky.xcodeproj -scheme offiky -configuration Release \
  -destination 'platform=macOS' -derivedDataPath "$BUILD" \
  CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="$IDENTITY" \
  DEVELOPMENT_TEAM=75J3AS52HQ PROVISIONING_PROFILE_SPECIFIER="" \
  build | grep -E "Signing Identity|BUILD SUCCEEDED|error:"
codesign -v --deep --strict "$APP"

package() {
    rm -f "$OUT" "$DMG"
    ditto -c -k --sequesterRsrc --keepParent "$APP" "$OUT"
    local stage
    stage=$(mktemp -d)
    cp -R "$APP" "$stage/"
    ln -s /Applications "$stage/Applications"
    hdiutil create -volname offiky -srcfolder "$stage" -ov -format UDZO -quiet "$DMG"
    rm -rf "$stage"
}

if ! xcrun notarytool history --keychain-profile "$PROFILE" >/dev/null 2>&1; then
    package
    echo
    echo "공증 자격증명 '$PROFILE' 이 없어 서명까지만 했다."
    echo "받는 사람이 한 번 실행해야 열린다:"
    echo "  xattr -dr com.apple.quarantine /Applications/offiky.app"
    echo
    echo "이 단계를 없애려면 파일 위쪽 주석대로 자격증명을 만들고 다시 실행해라."
    exit 0
fi

# 앱을 먼저 공증하고 티켓을 박아 둔다. 그래야 zip 으로 받아도 바로 열린다
TICKET=$(mktemp -d)/app.zip
ditto -c -k --sequesterRsrc --keepParent "$APP" "$TICKET"
xcrun notarytool submit "$TICKET" --keychain-profile "$PROFILE" --wait
xcrun stapler staple "$APP"

package
codesign --sign "$IDENTITY" --timestamp "$DMG"
xcrun notarytool submit "$DMG" --keychain-profile "$PROFILE" --wait
xcrun stapler staple "$DMG"

spctl -a -vv "$APP"
echo "완료"
echo "  $OUT  ($(du -h "$OUT" | cut -f1))"
echo "  $DMG  ($(du -h "$DMG" | cut -f1))"
