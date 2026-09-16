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
APP="$BUILD/Build/Products/Release/offiky.app"

rm -rf "$BUILD" "$OUT"
xcodebuild -project offiky.xcodeproj -scheme offiky -configuration Release \
  -destination 'platform=macOS' -derivedDataPath "$BUILD" \
  CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="-" \
  DEVELOPMENT_TEAM="" PROVISIONING_PROFILE_SPECIFIER="" \
  build | grep -E "Signing Identity|BUILD SUCCEEDED|error:"

codesign -v --deep --strict "$APP"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$OUT"
echo "완료: $OUT  ($(du -h "$OUT" | cut -f1))"
