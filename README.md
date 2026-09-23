<div align="center">

<img src="docs/icon.png" width="120" alt="Offiky">

# Offiky

**같은 방에 있는 동료들의 픽셀 캐릭터가 내 화면 아래를 돌아다닙니다.**

[![릴리스](https://img.shields.io/github/v/release/supungbab/offiky?style=flat-square&color=6cb328)](https://github.com/supungbab/offiky/releases)
[![macOS](https://img.shields.io/badge/macOS-14%2B-000?style=flat-square&logo=apple)](https://www.apple.com/macos/)
[![Swift](https://img.shields.io/badge/Swift-5-F05138?style=flat-square&logo=swift&logoColor=white)](https://swift.org)
[![Homebrew](https://img.shields.io/badge/Homebrew-cask-FBB040?style=flat-square&logo=homebrew&logoColor=white)](https://github.com/supungbab/homebrew-tap)
[![라이선스](https://img.shields.io/github/license/supungbab/offiky?style=flat-square)](LICENSE)

<img src="docs/demo.gif" width="342" alt="데모">

</div>

## 왜 만들었나요

- **사무실에 동료가 있다는 느낌을 줍니다.** 옆자리가 비어 있어도 화면 아래에서 동료가 걸어 다닙니다.
- **실행해 두기만 하면 됩니다.** 계정도 서버도 필요 없습니다. 같은 방에 들어온 사람끼리 알아서 서로를 찾습니다.
- **일을 방해하지 않습니다.** 메뉴바에만 있고 Dock 에는 나타나지 않습니다. 캐릭터 위를 클릭해도 아래 창이 그대로 클릭됩니다.

## 이름

**Offi**ce + Luc**ky** 를 합친 이름으로, 사무실에 사는 행운의 마스코트라는 뜻입니다.
친한 동료들과 함께 놀려고 만들었고, "오피키"라고 읽습니다.

## 사용법

| 기능 | 방법 |
|---|---|
| **채팅** | `⌥F` 를 누르면 화면 아래에 입력창이 나타납니다. 한 번에 50자까지 입력할 수 있습니다. 엔터로 보내면 내 캐릭터 머리 위에 말풍선이 5초간 표시되고, 입력창 위 목록에 지난 대화가 남습니다 |
| **조종** | `⌥D` 를 누르면 조종을 시작합니다. `←` `→` 로 이동하고, 같은 방향을 빠르게 두 번 누르면 대시합니다. `↑` 로 점프하고, 공중에서 한 번 더 누르면 2단 점프합니다. `esc` 로 끝냅니다 |
| **웅크리기** | 제자리에서 `↓` 를 누르면 고개를 숙입니다. 방향키와 함께 누르면 웅크린 채 천천히 이동합니다 |
| **옮기기** | 마우스로 캐릭터를 집어 원하는 곳에 놓습니다. 공중에서 놓으면 바닥으로 떨어집니다 |
| **꾸미기** | 메뉴 → 내 캐릭터… 에서 모양을 먼저 고르고, 그 모양의 프리셋 중 하나를 고릅니다 |
| **이름** | 메뉴 → 내 이름 변경… 에서 바꿉니다. 처음에는 맥 계정 이름으로 표시됩니다 |
| **방** | 메뉴 → 방 만들기… / 방 참여하기 에서 고릅니다. **같은 방에 있는 사람끼리만 서로 보입니다** |
| **참가자** | 메뉴 → 방 → 참가자 N명… 에서 지금 보이는 사람을 확인합니다. 중계를 맡은 사람에게는 호스트 배지가 표시됩니다 |

조종하지 않을 때 캐릭터는 제자리에 서 있습니다. 높은 곳에서 떨어지면 아파하는 동작이 나옵니다.

## 캐릭터

<img src="docs/characters.png" width="700" alt="캐릭터 목록">

모양 다섯 가지에 색 프리셋을 더해 만들었습니다. 그림에서 세로줄은 모양(염소·양·새·개구리·돼지)이고,
가로줄은 프리셋입니다. 모양마다 프리셋 개수는 조금씩 다릅니다. 각 줄의 첫 칸은 원작자가 그린
그대로이고, 나머지는 등·배·눈 같은 부위를 따로 칠한 것입니다.

| 모양 | 프리셋 |
|---|---|
| 염소 | `white` `brown` `black` `gold` `red` `demon` |
| 양 | `grey` `suffolk` `ink` `candy` `fleece` `night` |
| 새 | `blue` `penguin` `magpie` `parrot` `flamingo` `kingfisher` `scarlet` |
| 개구리 | `green` `fire` `dart` `tree` `azure` `violet` |
| 돼지 | `red` `pink` `black` `ivory` `royal` `carrot` |

프리셋은 원본 그림에서 색을 칠하는 자리는 그대로 두고 색만 바꾼 것입니다. 만들 때 세 가지를 지켰습니다.

- 이름만 들어도 모습이 떠오를 것
- 몸통과 배의 색이 뚜렷하게 다를 것
- 눈이 머리 색에 묻히지 않을 것

## 동작

캐릭터 하나는 **그림 24장**으로 움직입니다. 위에서부터 대기 · 걷기 · 피격 · 점프 · 인사 · 달리기 순서이고,
각각 4 · 6 · 4 · 3 · 1 · 6장입니다. 재생 속도도 동작마다 다릅니다. 초당 대기 5장, 걷기 12장,
피격 14장, 점프 11장, 달리기 18장입니다.

맨 위의 움직이는 그림은 `scripts/make_gifs.py` 가 이 그림들로 만든 것입니다. 앱과 같은 값을 씁니다.
걷기는 초당 60pt, 대시는 초당 180pt, 중력은 1100 입니다. 점프는 캐릭터 키의 2.25배인 108pt 까지
올라가므로, 그림의 세로 공간도 그만큼 높게 잡았습니다.

## 설치

### 요구사항

**macOS 14 (Sonoma) 이상**이 필요합니다. Apple Silicon 과 Intel 맥 모두에서 동작합니다.

### Homebrew

이 방법을 권장합니다. 처음 실행할 때 필요한 격리 해제를 cask 가 대신 처리하고, 업데이트도 명령 한 줄이면 됩니다.
Homebrew 가 없다면 먼저 [brew.sh](https://brew.sh) 에 나온 명령으로 설치하세요.

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

그다음 Offiky 를 설치합니다.

```bash
brew install --cask supungbab/tap/offiky
```

업데이트할 때는 아래 명령을 실행합니다.

```bash
brew update && brew upgrade --cask offiky
```

> **`brew update` 를 꼭 함께 실행하세요.** brew 는 tap 정보를 하루에 한 번만 새로 읽습니다.
> 그 전에는 새 버전이 나온 것을 모르고 "이미 최신"이라고 답합니다.

### 직접 내려받기

[릴리스](https://github.com/supungbab/offiky/releases)에서 `Offiky.dmg` 를 내려받아
응용 프로그램 폴더로 드래그합니다. 그다음 터미널에서 아래 명령을 한 번 실행합니다.

```bash
xattr -dr com.apple.quarantine /Applications/Offiky.app
```

Offiky 는 Apple 공증을 받지 않아서 macOS 가 처음 실행을 막습니다. 위 명령이 그 차단을 해제합니다.
Homebrew 로 설치하면 이 단계는 cask 가 대신 처리합니다.

### 소스에서 빌드하기

```bash
git clone https://github.com/supungbab/offiky.git
cd offiky
xcodebuild -project offiky.xcodeproj -scheme offiky -configuration Release build
```

배포용 서명과 패키징은 `scripts/release.sh` 가 처리합니다. 앱 아이콘은 `scripts/make_icon.py` 가
개구리 그림을 읽어 만듭니다.

## 동작 원리

| 항목 | 방식 |
|---|---|
| **방** | 방을 만들면 고유한 코드가 하나 생깁니다. 같은 방인지는 이 코드로 판단하고, 방 이름은 목록에 표시할 때만 씁니다. **한 방에는 50명까지** 들어올 수 있습니다 |
| **찾기** | Bonjour (`_offiky._tcp`)로 서로를 찾습니다. 광고에 방 코드를 넣어 같은 방 사람끼리만 연결합니다 |
| **호스트** | 외부 서버 없이, 방 안의 한 사람이 중계를 맡습니다. **방에 먼저 들어온 사람이 호스트**이고, 나머지는 호스트에게만 연결합니다 |
| **호스트 교체** | 호스트가 나가면 남은 사람 중 먼저 들어온 사람이 이어받습니다. 나갔다 다시 들어온 사람은 새로 들어온 사람으로 봅니다. Wi-Fi 가 끊겨 알림 없이 사라진 호스트는 10초간 응답이 없으면 나간 것으로 봅니다 |
| **좌표** | 움직이는 동안 0.1초마다 UDP 로 보내고, 서 있으면 3초에 한 번만 보냅니다. 받는 쪽은 받은 좌표 사이를 부드럽게 채워 그리고, 좌표가 잠깐 끊기면 걷던 속도로 계속 움직입니다 |
| **채팅·입장·퇴장** | 반드시 도착해야 하므로 TCP 로 보냅니다. UDP 가 막힌 망에서는 좌표도 TCP 로 보냅니다 |
| **모아 보내기** | 호스트는 20ms 동안 모인 좌표를 사람마다 한 번에 모아 보냅니다. 하나씩 보내면 50명일 때 초당 전송 횟수가 24,500회에 이릅니다 |
| **화면 배치** | 연결된 모든 화면을 왼쪽부터 한 줄로 이어 놓은 것처럼 다룹니다. 화면이 넓을수록 더 멀리까지 보입니다 |

예전에는 모두가 모두에게 직접 연결했습니다. 그러면 50명일 때 한 사람이 연결 49개를 유지해야 했습니다.
지금은 호스트만 그만큼 유지하고, 나머지는 호스트와의 연결 하나만 유지합니다.

**모두 같은 버전을 설치해야 합니다.** 통신 규약이 다르면 서로 보이지 않습니다.
그런 동료가 있으면 메뉴에 표시됩니다.

## 개인정보와 권한

- **로컬 네트워크 권한**이 필요합니다. 처음 실행할 때 macOS 가 허용할지 묻습니다. 거부하면 동료를 찾지 못합니다.
- **App Sandbox 안에서 동작합니다.** 네트워크 연결만 허용되어 있고, 파일에는 접근하지 않습니다.
- **대화 내용은 저장하지 않습니다.** 말풍선은 5초 뒤에 사라집니다. 입력창 위 목록은 최근 100개를
  메모리에만 보관하고, 방을 나가거나 앱을 종료하면 사라집니다.
  디스크에 저장하는 것은 내 이름, 고른 캐릭터 번호, 처음 실행할 때 만드는 설치 식별자뿐입니다.
  설치 식별자는 캐릭터를 아직 고르지 않았을 때 기본 캐릭터를 정하는 데만 씁니다.
- **외부로 나가는 통신은 하나뿐입니다.** GitHub 에 새 버전이 있는지 확인하는 요청이며, 이때도
  내 정보는 보내지 않습니다.

## 라이선스와 출처

코드는 [MIT](LICENSE) 라이선스입니다.

캐릭터 그림은 [ChaosWitchNikol](https://chaoswitchnikol.itch.io) 의 작품입니다.

- [Goat Characters](https://chaoswitchnikol.itch.io/goat-characters) — 염소
- [Animal Characters](https://chaoswitchnikol.itch.io/animal-characters) — 새, 양, 개구리, 돼지

두 팩 모두 [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/) 라이선스입니다.
**원본을 그대로 쓰지 않고 색을 바꿔 표시합니다.** 받은 그림의 모양은 그대로 두고,
등·배·눈 같은 부위를 따로 칠해 프리셋을 만들었습니다.

캐릭터마다 쓰는 색과 그림 24장의 픽셀 배치는 [`characters.txt`](characters.txt) 에 있습니다.
