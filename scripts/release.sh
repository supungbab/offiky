#!/bin/bash
# 배포용 빌드. Developer ID 로 서명하고 공증까지 한다.
#
# 공증 자격증명은 한 번만 만들어 두면 된다. 앱 암호는
# appleid.apple.com > 로그인 및 보안 > 앱 암호 에서 발급한다.
#
#   xcrun notarytool store-credentials offiky \
#     --apple-id supungbab@gmail.com --team-id 75J3AS52HQ --password <앱-암호>
set -euo pipefail

IDENTITY="Developer ID Application: MyeongHo Kyeong (75J3AS52HQ)"
PROFILE="${1:-offiky}"
BUILD=/tmp/offiky-release
OUT=~/Desktop/offiky.zip
APP="$BUILD/Build/Products/Release/offiky.app"

rm -rf "$BUILD" "$OUT"
xcodebuild -project offiky.xcodeproj -scheme offiky -configuration Release \
  -destination 'platform=macOS' -derivedDataPath "$BUILD" \
  CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="$IDENTITY" \
  DEVELOPMENT_TEAM=75J3AS52HQ PROVISIONING_PROFILE_SPECIFIER="" \
  build | grep -E "Signing Identity|BUILD SUCCEEDED|error:"

ditto -c -k --sequesterRsrc --keepParent "$APP" "$OUT"

if ! xcrun notarytool history --keychain-profile "$PROFILE" >/dev/null 2>&1; then
    echo
    echo "공증 자격증명 '$PROFILE' 이 없다. 서명만 된 zip 을 만들었다: $OUT"
    echo "받는 사람이 아래를 한 번 실행해야 열린다."
    echo "  xattr -dr com.apple.quarantine /Applications/offiky.app"
    echo
    echo "자격증명을 만들면 이 단계가 사라진다. 파일 위쪽 주석 참고."
    exit 0
fi

xcrun notarytool submit "$OUT" --keychain-profile "$PROFILE" --wait
xcrun stapler staple "$APP"
rm -f "$OUT"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$OUT"

spctl -a -vv "$APP"
echo "공증 완료: $OUT"
