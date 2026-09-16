#!/bin/bash
# 배포 서명용 자체 인증서를 키체인에 만든다. 한 번만 실행하면 된다.
#
# Apple 인증서를 쓰지 않는 이유: 개발자 프로그램을 갱신하지 않아도
# 계속 배포할 수 있다. 대신 Gatekeeper 는 통과하지 못하므로 받는 사람이
# 격리 속성을 지워야 한다 (Homebrew 로 설치하면 cask 가 대신 한다).
#
# 애드혹(-s -)으로도 서명은 되지만 빌드마다 신원이 바뀐다. 그러면 macOS 가
# 로컬 네트워크 권한을 업데이트마다 다시 물어본다. 고정된 인증서가 그것을 막는다.
set -euo pipefail

NAME="offiky Local"
if security find-identity -p codesigning 2>/dev/null | grep -qF "\"$NAME\""; then
    echo "'$NAME' 이 이미 있다."
    exit 0
fi

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

openssl req -x509 -newkey rsa:2048 -keyout "$WORK/key.pem" -out "$WORK/cert.pem" \
  -days 7300 -nodes -subj "/CN=$NAME" \
  -addext "basicConstraints=critical,CA:false" \
  -addext "keyUsage=critical,digitalSignature" \
  -addext "extendedKeyUsage=critical,codeSigning"

# macOS 가 읽을 수 있도록 옛 PKCS12 형식으로 묶는다.
# OpenSSL 3 의 기본 암호화는 Security 프레임워크가 해석하지 못한다.
openssl pkcs12 -export -out "$WORK/identity.p12" \
  -inkey "$WORK/key.pem" -in "$WORK/cert.pem" \
  -passout pass:offiky -name "$NAME" \
  -macalg sha1 -keypbe PBE-SHA1-3DES -certpbe PBE-SHA1-3DES

security import "$WORK/identity.p12" -k ~/Library/Keychains/login.keychain-db \
  -P offiky -T /usr/bin/codesign -A

echo "만들었다. 신뢰되지 않은 인증서라 find-identity -v 목록에는 안 보이지만 서명에는 쓸 수 있다."
security find-identity -p codesigning | grep -F "$NAME"
