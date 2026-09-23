<div align="center">

<img src="docs/icon.png" width="120" alt="Offiky">

# Offiky

**동료들의 작은 픽셀 캐릭터가 내 화면 아래를 걸어 다닙니다.**

[![릴리스](https://img.shields.io/github/v/release/supungbab/offiky?style=flat-square&color=6cb328)](https://github.com/supungbab/offiky/releases)
[![macOS](https://img.shields.io/badge/macOS-14%2B-000?style=flat-square&logo=apple)](https://www.apple.com/macos/)
[![Homebrew](https://img.shields.io/badge/Homebrew-cask-FBB040?style=flat-square&logo=homebrew&logoColor=white)](https://github.com/supungbab/homebrew-tap)
[![라이선스](https://img.shields.io/github/license/supungbab/offiky?style=flat-square)](LICENSE)

<img src="docs/demo.gif" width="342" alt="데모">

</div>

조용한 사무실, 각자 모니터만 보고 있는 오후. Offiky 를 실행해 두면 화면 아래에 동료들의
캐릭터가 나타나 돌아다닙니다. 누가 자리에 있는지 한눈에 보이고, 말풍선으로 가볍게
말을 걸 수도 있습니다. 메신저를 열 만큼은 아니지만 한마디 건네고 싶을 때 딱 맞습니다.

## 이런 걸 할 수 있어요

- **동료가 보입니다.** 같은 방에 들어온 동료의 캐릭터가 화면 아래를 걸어 다닙니다.
  옆자리가 비어 있어도 사무실에 사람이 있다는 느낌이 듭니다.
- **말을 걸 수 있습니다.** `⌥F` 를 누르고 한마디 입력하면 내 캐릭터 머리 위에 말풍선이 나타납니다.
  동료들 화면에도 똑같이 보입니다.
- **직접 움직일 수 있습니다.** `⌥D` 를 누르면 방향키로 조종합니다. 걷고, 달리고, 2단 점프까지 합니다.
  동료 캐릭터 옆으로 달려가 고개 숙여 인사해 보세요.
- **내 캐릭터를 집어 들 수 있습니다.** 마우스로 들어 원하는 곳에 옮길 수 있습니다. 높은 곳에서 떨어뜨리면 아파합니다.
- **나만의 캐릭터를 고를 수 있습니다.** 염소, 양, 새, 개구리, 돼지 중에서 고르고 색도 바꿀 수 있습니다.

<div align="center">
<img src="docs/characters.png" width="700" alt="고를 수 있는 캐릭터">
</div>

## 걱정하지 않아도 돼요

- **일을 방해하지 않습니다.** 메뉴바에만 있고 Dock 에는 나타나지 않습니다.
  캐릭터 위를 클릭해도 아래 창이 그대로 클릭됩니다.
- **가입도 설정도 없습니다.** 계정도 서버도 필요 없습니다. 같은 네트워크에서 같은 방에 들어오면 서로를 찾아냅니다.
- **대화가 남지 않습니다.** 말풍선은 5초 뒤 사라지고, 대화 목록은 앱을 종료하면 지워집니다. 어디에도 저장하지 않습니다.
- **내 정보가 밖으로 나가지 않습니다.** 모든 통신은 사무실 네트워크 안에서만 오갑니다.
  바깥으로 나가는 요청은 새 버전을 확인하는 것 하나뿐이고, 그때도 내 정보는 보내지 않습니다.

## 시작하기

**1. 설치합니다.** 터미널에 아래 한 줄을 붙여 넣으세요.

```bash
brew install --cask supungbab/tap/offiky
```

Homebrew 가 없다면 먼저 [brew.sh](https://brew.sh) 의 설치 명령을 실행하세요.

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

**2. 실행합니다.** 응용 프로그램 폴더에서 Offiky 를 열면 메뉴바에 아이콘이 생깁니다.
로컬 네트워크 사용을 허용할지 물으면 **허용**을 눌러 주세요. 그래야 동료를 찾을 수 있습니다.

**3. 방에 들어갑니다.** 메뉴바 아이콘 → **방 만들기…** 로 방을 만들고, 동료에게 방 이름을 알려 주세요.
동료는 **방 참여하기** 에서 그 방을 고르면 됩니다.

<details>
<summary>Homebrew 없이 직접 설치하기</summary>

[릴리스](https://github.com/supungbab/offiky/releases)에서 `Offiky.dmg` 를 내려받아 응용 프로그램 폴더로
드래그합니다. Apple 공증을 받지 않은 앱이라 macOS 가 처음 실행을 막으므로, 터미널에서 아래 명령을 한 번 실행합니다.

```bash
xattr -dr com.apple.quarantine /Applications/Offiky.app
```

Homebrew 로 설치하면 이 단계를 대신 처리해 줍니다.

</details>

## 사용법

| 기능 | 방법 |
|---|---|
| **채팅** | `⌥F` 로 입력창을 열고 엔터로 보냅니다. 입력창 위에 지난 대화가 보입니다 |
| **조종** | `⌥D` 로 시작합니다. `←` `→` 이동, 같은 방향을 빠르게 두 번 누르면 대시, `↑` 점프(공중에서 한 번 더 누르면 2단 점프), `esc` 로 끝냅니다 |
| **인사** | 조종 중에 `↓` 를 누르면 고개를 숙입니다. 방향키와 함께 누르면 웅크린 채 천천히 걷습니다 |
| **옮기기** | 마우스로 내 캐릭터를 집어 원하는 곳에 놓습니다 |
| **꾸미기** | 메뉴 → **내 캐릭터…** 에서 모양과 색을 고릅니다 |
| **이름** | 메뉴 → **내 이름 변경…** 에서 바꿉니다. 처음에는 맥 계정 이름으로 표시됩니다 |
| **참가자** | 메뉴 → 방 → **참가자** 에서 지금 함께 있는 사람을 봅니다 |

## 자주 묻는 질문

**재택근무하는 동료도 볼 수 있나요?**
아니요. 같은 네트워크(예: 같은 사무실 Wi-Fi)에 있는 사람끼리만 보입니다. 서버를 거치지 않는 대신 생긴 한계입니다.

**몇 명까지 함께할 수 있나요?**
한 방에 50명까지 들어올 수 있습니다.

**동료가 안 보여요.**
세 가지를 확인해 주세요.
- 같은 방에 들어와 있는지 (메뉴 → 방)
- 같은 버전을 쓰는지. 버전이 다른 동료가 있으면 메뉴에 표시됩니다.
- 로컬 네트워크 권한을 허용했는지 (시스템 설정 → 개인정보 보호 및 보안 → 로컬 네트워크)

**업데이트는 어떻게 하나요?**
새 버전이 나오면 메뉴바 아이콘에 빨간 점이 표시됩니다. 메뉴의 **새 버전 받기** 를 누른 뒤
**복사하고 터미널 열기** 를 고르면 명령이 복사되고 터미널이 열립니다. 붙여 넣고 엔터만 누르세요.
직접 입력한다면 아래와 같습니다.

```bash
brew update && brew upgrade --cask offiky
```

`brew update` 없이 실행하면 brew 가 새 버전을 모르고 "이미 최신"이라고 답할 수 있으니 꼭 함께 실행하세요.

**무료인가요?**
네, 무료이고 소스도 공개되어 있습니다.

**어떤 맥에서 동작하나요?**
macOS 14 (Sonoma) 이상이면 Apple Silicon 과 Intel 맥 모두에서 동작합니다.

## 이름

**Offi**ce + Luc**ky**. 사무실에 사는 행운의 마스코트라는 뜻이고, "오피키"라고 읽습니다.
친한 동료들과 함께 놀려고 만들었습니다.

## 만든 사람들

코드는 [MIT](LICENSE) 라이선스입니다. 소스에서 직접 빌드하려면 아래처럼 합니다.

```bash
git clone https://github.com/supungbab/offiky.git
cd offiky
xcodebuild -project offiky.xcodeproj -scheme offiky -configuration Release build
```

캐릭터 그림은 [ChaosWitchNikol](https://chaoswitchnikol.itch.io) 님의 작품입니다.

- [Goat Characters](https://chaoswitchnikol.itch.io/goat-characters) — 염소
- [Animal Characters](https://chaoswitchnikol.itch.io/animal-characters) — 새, 양, 개구리, 돼지

두 팩 모두 [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/) 라이선스이며,
Offiky 는 원본의 모양을 그대로 두고 색을 바꾼 프리셋을 함께 제공합니다.
