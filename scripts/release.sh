#!/bin/bash
# 배포 빌드. 자체 서명 인증서로 서명한다. Apple 인증서를 쓰지 않으므로
# 개발자 프로그램 회원권과 무관하게 계속 배포할 수 있다.
#
# 인증서는 한 번만 만들면 된다. scripts/make_cert.sh 참고.
# 없으면 애드혹으로 서명한다 — 동작은 하지만 빌드마다 신원이 바뀌어
# 로컬 네트워크 권한을 매번 다시 물어본다.
#
# 받는 사람은 응용 프로그램 폴더에 넣은 뒤 한 번만 아래를 실행해야 한다.
#   xattr -dr com.apple.quarantine /Applications/Offiky.app
# Homebrew 로 설치하면 cask 가 대신 처리한다.
set -euo pipefail

IDENTITY="offiky Local"
BUILD=/tmp/offiky-release
OUT=~/Desktop/Offiky.zip
DMG=~/Desktop/Offiky.dmg
APP="$BUILD/Build/Products/Release/Offiky.app"
ENTITLEMENTS=offiky.entitlements

rm -rf "$BUILD"
# 서명은 아래에서 직접 한다. 빌드 단계에서는 하지 않는다
xcodebuild -project offiky.xcodeproj -scheme offiky -configuration Release \
  -destination 'platform=macOS' -derivedDataPath "$BUILD" \
  CODE_SIGNING_ALLOWED=NO \
  build | grep -E "BUILD SUCCEEDED|error:"

if security find-identity -p codesigning 2>/dev/null | grep -qF "\"$IDENTITY\""; then
    echo "==> $IDENTITY 로 서명"
    codesign --force --options runtime --entitlements "$ENTITLEMENTS" -s "$IDENTITY" "$APP"
else
    echo "==> '$IDENTITY' 가 없어 애드혹으로 서명한다 (scripts/make_cert.sh 참고)"
    codesign --force --options runtime --entitlements "$ENTITLEMENTS" -s - "$APP"
fi
codesign -v --strict "$APP"
codesign -dvv "$APP" 2>&1 | grep -E "^Authority|flags="

rm -f "$OUT" "$DMG"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$OUT"
STAGE=$(mktemp -d)
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname Offiky -srcfolder "$STAGE" -ov -format UDZO -quiet "$DMG"
rm -rf "$STAGE"

echo "완료"
echo "  $OUT  ($(du -h "$OUT" | cut -f1))"
echo "  $DMG  ($(du -h "$DMG" | cut -f1))"
