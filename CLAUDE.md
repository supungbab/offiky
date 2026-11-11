# Offiky

## 배포

1. `offiky.xcodeproj/project.pbxproj` 의 `MARKETING_VERSION`·`CURRENT_PROJECT_VERSION` 4곳씩을 새 버전으로 수정한다
2. `chore: X.Y.Z` 로 커밋하고 푸시한다
3. `./scripts/release.sh` 를 실행한다. 결과물은 `build/Offiky.dmg`·`build/Offiky.zip`
4. `gh release create vX.Y.Z -R supungbab/offiky --target main --title "Offiky X.Y.Z" --notes "## 달라진 점 …" build/Offiky.dmg build/Offiky.zip`
5. `~/ide/homebrew-tap/Casks/offiky.rb` 의 `version`·`sha256` 을 수정하고 `offiky X.Y.Z` 로 커밋·푸시한다. 이 커밋에는 Co-Authored-By 를 적지 않는다
6. `curl -sL https://github.com/supungbab/offiky/releases/download/vX.Y.Z/Offiky.zip | shasum -a 256` 이 cask 의 `sha256` 과 같은지 확인한다

## 디버그 인스턴스

번들 id 를 바꾼 복사본으로 실행한다. 같은 id 면 실제 앱의 환경설정을 덮어쓴다.

```sh
xcodebuild -project offiky.xcodeproj -scheme offiky -configuration Debug -destination 'platform=macOS' -derivedDataPath /tmp/offiky-debug CODE_SIGNING_ALLOWED=NO build
cp -R /tmp/offiky-debug/Build/Products/Debug/Offiky.app "$DIR/debug1/"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier com.offiky.debug1" "$DIR/debug1/Offiky.app/Contents/Info.plist"
codesign --force --deep --entitlements offiky.entitlements -s - "$DIR/debug1/Offiky.app"  # offiky/ 아래가 아니라 리포 루트에 있다
defaults write com.offiky.debug1 channel -int 2   # Debug 빌드만: bot -bool YES 면 혼자 움직이고, dance -bool YES 면 제자리에서 계속 춤춘다. fishing -bool YES 면 계속 낚시하고 입질이 오면 챔질하며 biteDelay -float 4 로 대기를 줄인다. working -bool NO
open -n "$DIR/debug1/Offiky.app"
```

채널을 따로 말하지 않으면 2채널로 실행한다. 로그는 `log stream --level info --predicate 'subsystem == "offiky"'` 로 확인한다.

## 조작키 추가

새 키를 추가하면 세 곳에 함께 반영한다.

- `Control.swift` 의 `HintView` (조종 중에 표시되는 안내 줄)
- README 의 기능 표
- `offikyApp.swift` 의 DEBUG `Bot` 동작. 디버그 인스턴스가 새 동작도 실행하게 된다

## 테스트

```sh
xcodebuild test -project offiky.xcodeproj -scheme offiky -destination 'platform=macOS' -derivedDataPath /tmp/offiky-test CODE_SIGNING_ALLOWED=NO
```

Debug 빌드와 테스트 호스트는 `com.offiky.app.debug` 로 실행된다. 배포본과 번들 id 가 같으면 `open -b com.offiky.app` 이 Debug 빌드를 실행한다. `World.shared.me` 상태가 그 환경설정에 따라 달라지므로 `World` 대신 `CharacterNode` 단위로 검증한다.

## 픽셀 아트

- 원본 캐릭터: [ChaosWitchNikol](https://chaoswitchnikol.itch.io) 의 [Goat Characters](https://chaoswitchnikol.itch.io/goat-characters)(염소)·[Animal Characters](https://chaoswitchnikol.itch.io/animal-characters)(새·양·개구리·돼지), CC BY 4.0
- 참조: [How to make good pixel art effects with Claude](https://www.spritefusion.com/blog/how-to-make-good-pixel-art-effects-with-claude) · 이펙트 라이브러리 https://www.spritefusion.com/pixel-art-vfx (MIT)

캐릭터를 추가하면 어느 원본에서 왔는지(원본 없이 코드로 그렸으면 그 스크립트)를 README 의 출처 문단과 `characters.txt` 에 적는다.

- 캐릭터·이펙트는 Python(Pillow) 코드로 그리고, 디버그 인스턴스에서 실제 크기로 확인하며 다듬는다 (`scripts/make_slime.py` 참고)
- 사용자가 이미지를 주면 [Pixel Snapper](https://github.com/Hugo-Dz/spritefusion-pixel-snapper)(MIT)로 격자에 맞춰 캐릭터를 만든다. 설치는 `brew install Hugo-Dz/tap/spritefusion-pixel-snapper`, 사용은 `spritefusion-pixel-snapper <입력> <출력.png> [색 수] [--pixel-size N] [--palette 16진수,…]` (색 수 기본 16). 기존 캐릭터와 색을 맞출 때는 `--palette` 를, 격자가 어긋날 때는 `--pixel-size` 를 지정한다. 결과가 144×144 시트(24×24 장 6×6)와 `scripts/image_prompt.txt` 의 행 구성에 맞는지 확인한다
- 새 캐릭터는 시안 여러 개를 GIF 로 보여 주지 말고, 기존과 같은 144×144 시트 하나를 완성해 확대 이미지로 보여 준다
- 소품·무기는 번호를 붙인 시안 여러 개를 한 이미지에 나란히 보여 주고 고르게 한다
- 움직이는 에셋은 부품(바퀴·본체 등)을 실행 중에 합치지 말고 프레임마다 통째로 그린 스트립으로 만든다
- 색 변형은 실행 중에 색을 입히지 말고 미리 칠한 에셋으로 만든다
- 1px 선은 실제 크기에서 옆 선과 합쳐져 다른 부위로 보인다. 강아지의 먼 쪽 다리 두 개가 가운데 다리 하나로 보였다
- GIF 는 팔레트 하나로 고정해 만든다. 프레임마다 팔레트를 만들면 색이 깜빡인다
- 라이브러리 코드는 픽셀 버퍼에 직접 그리는 방식이라 SpriteKit 에 그대로 넣을 수 없다. 원리만 가져와 SpriteKit 으로 다시 구현한다
- 캐릭터를 추가하면 `scripts/make_characters.py` 로 `characters.txt`·`docs/characters.png` 를 다시 만든다

## 이전 버전과의 호환

- `protocolVersion` 을 바꾸면 이전 버전과 서로 보이지 않는다. 꼭 필요할 때만 바꾼다
- 이전 클라이언트는 모르는 JSON 키와 모르는 메시지 종류를 무시한다. 새 필드는 옵셔널로 추가한다
- 번호로 전송되는 값(캐릭터·W 물건·오토바이 색·무기 번호 등)은 뒤에 추가만 하고 기존 번호를 바꾸지 않는다
- 이전 클라이언트는 모르는 캐릭터·W 물건 번호를 받으면 업데이트 팻말로 표시한다. 물건은 2.53.0 이하에서 노트북으로 표시된다
