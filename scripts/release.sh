#!/bin/bash
# 배포 빌드. Developer ID 로 서명하고 앱과 DMG 를 모두 공증한다.
# 공증까지 끝나면 받는 사람은 드래그해서 넣고 더블클릭만 하면 된다.
#
# 서명한 파일을 공증 전에 먼저 내놓는다. 공증은 Apple 큐에 달려 있어
# 한 시간 넘게 걸리기도 하는데, 그 동안 손에 아무것도 없으면 안 된다.
# 공증이 끝나면 같은 자리를 티켓 박힌 것으로 덮어쓴다.
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

xattr_notice() {
    echo "받는 사람이 응용 프로그램 폴더에 넣은 뒤 한 번 실행해야 열린다:"
    echo "  xattr -dr com.apple.quarantine /Applications/offiky.app"
}

rm -rf "$BUILD"
xcodebuild -project offiky.xcodeproj -scheme offiky -configuration Release \
  -destination 'platform=macOS' -derivedDataPath "$BUILD" \
  CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="$IDENTITY" \
  DEVELOPMENT_TEAM=75J3AS52HQ PROVISIONING_PROFILE_SPECIFIER="" \
  OTHER_CODE_SIGN_FLAGS="--timestamp" \
  CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO \
  build | grep -E "Signing Identity|BUILD SUCCEEDED|error:"
codesign -v --deep --strict "$APP"
package
echo "서명한 파일을 먼저 내놓았다. 공증을 시작한다."

if ! xcrun notarytool history --keychain-profile "$PROFILE" >/dev/null 2>&1; then
    echo
    echo "공증 자격증명 '$PROFILE' 이 없어 서명까지만 했다."
    xattr_notice
    echo "없애려면 파일 위쪽 주석대로 자격증명을 만들고 다시 실행해라."
    exit 0
fi

# submit --wait 는 거부돼도 0 을 반환한다. 상태를 직접 본다
notarize() {
    local out id
    out=$(xcrun notarytool submit "$1" --keychain-profile "$PROFILE" --wait 2>&1)
    grep -E "  id:|status:" <<<"$out" | head -3
    if ! grep -q "status: Accepted" <<<"$out"; then
        id=$(awk '/  id: /{print $2; exit}' <<<"$out")
        echo "공증이 거부됐다:"
        xcrun notarytool log "$id" --keychain-profile "$PROFILE" 2>&1 | grep -E '"message"|"path"'
        echo
        echo "서명까지 된 파일은 그대로 있다."
        xattr_notice
        exit 1
    fi
}

# 앱을 먼저 공증하고 티켓을 박아 둔다. 그래야 zip 으로 받아도 바로 열린다
notarize "$OUT"
xcrun stapler staple "$APP"

package
codesign --sign "$IDENTITY" --timestamp "$DMG"
notarize "$DMG"
xcrun stapler staple "$DMG"

spctl -a -vv "$APP" || echo "경고: Gatekeeper 평가가 통과하지 못했다"
echo "공증 완료"
echo "  $OUT  ($(du -h "$OUT" | cut -f1))"
echo "  $DMG  ($(du -h "$DMG" | cut -f1))"
