# offiky

같은 네트워크에 있는 동료들의 픽셀 캐릭터가 각자 화면 바닥을 돌아다닌다.
단축키 하나로 말풍선을 띄워 대화한다.

메뉴바에만 상주하고 Dock 에는 뜨지 않는다.

## 설치

```
brew install --cask supungbab/tap/offiky
```

Homebrew 를 쓰지 않으면 [릴리스](https://github.com/supungbab/offiky/releases)에서
`Offiky.dmg` 를 받아 응용 프로그램 폴더로 드래그한 뒤, 터미널에서 한 번 실행한다.

```
xattr -dr com.apple.quarantine /Applications/Offiky.app
```

공증을 받지 않아 macOS 가 처음 실행을 막는다. Homebrew 로 설치하면 이 단계를 대신 처리한다.

**macOS 14(Sonoma) 이상**이 필요하다.

## 쓰는 법

| | |
|---|---|
| 채팅 | `⌥Space` — 화면 아래 입력창이 뜬다. 엔터로 보내면 머리 위에 5초간 표시된다 |
| 캐릭터 옮기기 | 마우스로 집어서 놓는다. 공중에서 놓으면 떨어진다 |
| 캐릭터 바꾸기 | 메뉴 → 내 캐릭터… — 9종 중에 고르고 색을 조정한다 |
| 이름 바꾸기 | 메뉴 → 내 이름 변경… — 기본값은 맥 계정 이름이다 |

같은 네트워크에 있으면 자동으로 서로를 찾는다. 서버가 없다 — Bonjour 로 발견하고
참가자 중 한 명이 자동으로 중계 역할을 맡는다. 대화 내용은 어디에도 저장하지 않는다.

캐릭터는 스스로 걷고 뛰고 점프한다. 빠르게 정면으로 부딪치거나 높은 곳에서 떨어지면
아파하는 동작이 나온다.

확장 디스플레이를 쓰면 그만큼 넓은 범위를 본다. 좌표는 모두에게 같으므로, 화면이 좁은
사람에게는 멀리 있는 캐릭터가 보이지 않을 뿐이다.

## 직접 빌드하기

```
git clone https://github.com/supungbab/offiky.git
cd offiky
xcodebuild -project offiky.xcodeproj -scheme offiky -configuration Release build
```

배포용 서명·패키징은 `scripts/release.sh` 가 한다. 앱 아이콘은 `scripts/make_icon.py` 가
16×16 픽셀 지도에서 만든다.

## 라이선스

코드는 [MIT](LICENSE) 다. 캐릭터 그림은 별도 라이선스를 따른다.

## 캐릭터 그림

[ChaosWitchNikol](https://chaoswitchnikol.itch.io) 의 작품을 사용한다.

- [Goat Characters](https://chaoswitchnikol.itch.io/goat-characters) — 염소 5종
- [Animal Characters](https://chaoswitchnikol.itch.io/animal-characters) — 새, 양, 개구리, 돼지

두 팩 모두 [Creative Commons Attribution 4.0 International](https://creativecommons.org/licenses/by/4.0/)
라이선스다. **원본을 그대로 쓰지 않고 색상·채도·밝기를 조정해 표시한다.**
