# MyMacCalendar

MyMacCalendar는 macOS용 로컬 우선 캘린더 앱입니다. 하루 종일 일정 관리, 간단한 반복 일정, 직접 편집 가능한 휴일, 설정 기반 플로팅 위젯을 목표로 만든 독립 앱입니다. Apple Calendar나 외부 계정 로그인 없이 SwiftData에 로컬 저장합니다.

## 다운로드

- macOS 테스트 빌드 zip: [MyMacCalendar-test-build.zip](https://github.com/biglol10/MyVibeCoding/raw/main/downloads/MyMacCalendar/MyMacCalendar-test-build.zip)

현재 배포 파일은 개발/테스트용 빌드입니다. Apple Developer ID 서명과 공증이 없기 때문에, GitHub에서 다운로드한 zip을 바로 실행하면 macOS Gatekeeper가 "손상되었으므로 휴지통으로 이동" 경고를 표시할 수 있습니다.

### 처음 실행 방법

방법 1: 동봉된 설치 헬퍼 사용 (권장)

1. zip 압축을 풉니다.
2. `MyMacCalendar` 폴더 안의 `Install MyMacCalendar.command`를 Finder에서 우클릭합니다.
3. `열기`를 선택합니다.
4. 헬퍼가 `MyMacCalendar.app`의 다운로드 격리 속성을 제거하고 `/Applications/MyMacCalendar.app`으로 설치한 뒤 앱을 실행합니다.

설치하지 않고 압축을 푼 위치에서 바로 실행하려면 `Open MyMacCalendar.command`를 우클릭해서 열 수 있습니다.

방법 2: 터미널에서 격리 속성 직접 제거

```bash
xattr -dr com.apple.quarantine /path/to/MyMacCalendar.app
open /path/to/MyMacCalendar.app
```

방법 3: 소스에서 직접 실행

```bash
git clone https://github.com/biglol10/MyVibeCoding.git
cd MyVibeCoding/MyMacCalendar
swift run MyMacCalendar
```

## 주요 기능

- 월간 달력 화면과 우측 일정 패널
- 하루 종일 일정 생성, 수정, 삭제
- 주간, 월간, 연간 반복 일정
- 7일 전, 2일 전, 1일 전, 당일 알림 옵션 저장
- 빠른 일정 추가: `6/30 codex 만료`, `2026-06-30 codex`, `다음주 월요일 병원`
- 제목/메모 기반 일정 검색
- 직접 휴일 등록과 삭제
- API로 가져온 휴일을 숨김 처리할 수 있는 core merge 로직
- 메뉴바 아이콘과 플로팅 upcoming 위젯
- 위젯 표시, 항상 위, 투명도, 표시 개수 설정
- 설정 창: General, Widget, Notifications, Holidays, Appearance, Data

## 현재 동작 확인

최근 수동 검증에서 확인한 흐름입니다.

- 일정 생성 후 월 셀 점 표시와 우측 패널 반영
- 우측 일정 행 클릭 후 편집 화면 진입
- 일정 삭제 확인 다이얼로그와 삭제 후 패널/재실행 유지
- 수동 휴일 등록, 삭제, 재실행 후 삭제 유지
- 빠른 추가 입력 중 Preview와 Add 버튼 활성화
- 플로팅 위젯에 upcoming 일정 표시
- 오늘 일정은 위젯에서 빨간 막대, 이후 일정은 파란 막대로 표시
- 설정에서 플로팅 위젯 on/off 시 실제 위젯 창 생성/숨김

## 요구사항

- macOS 14 이상
- Xcode 16.4 또는 Swift 6 호환 toolchain

## 실행

개발 중에는 SwiftPM 실행 파일로 바로 실행할 수 있습니다.

```bash
swift run MyMacCalendar
```

앱 번들로 실행하려면 아래 스크립트를 사용합니다.

```bash
./scripts/build_app.sh
open build/MyMacCalendar.app
```

생성되는 앱 번들 위치:

```text
build/MyMacCalendar.app
dist/MyMacCalendar-test-build.zip
```

## 테스트

전체 테스트:

```bash
swift test
```

현재 테스트 범위:

- 월간 달력 grid 생성
- 반복 일정 occurrence 확장
- upcoming 일정 정렬/검색
- 빠른 추가 parser
- 알림 예약 계획 계산
- 휴일 API decode/merge
- API 휴일 숨김 유지
- 수동 휴일 우선 처리
- 기본 설정 생성

## 프로젝트 구조

```text
Sources/MyMacCalendar
  App/                 macOS 앱 진입점과 AppDelegate
  Controllers/         메뉴바, 플로팅 위젯 controller
  Views/               SwiftUI 화면

Sources/MyMacCalendarCore
  Models/              SwiftData 모델
  Services/            달력, 반복, 휴일, 알림, 빠른 추가 로직
  Stores/              SwiftData container/settings store

Tests/MyMacCalendarCoreTests
  Core 로직 단위 테스트

scripts/build_app.sh
  release build 후 .app 번들 생성
```

## 데이터 저장

앱 데이터는 SwiftData를 통해 로컬에 저장됩니다. 일정, 휴일, 설정은 앱을 종료하고 다시 열어도 유지됩니다. 현재 백업/복원 UI는 아직 구현하지 않았습니다.

## 휴일 처리

수동 휴일 등록과 삭제는 앱 설정의 `Holidays` 탭에서 사용할 수 있습니다.

Core에는 Nager.Date API 응답 decode와 merge 로직이 있습니다. API 휴일이 잘못됐을 때 숨김 처리하면 같은 provider key로 다시 가져와도 유지되도록 테스트되어 있습니다. 다만 앱 시작 시 자동으로 API를 fetch하는 UI/스케줄링 연결은 아직 남은 작업입니다.

## 알림 처리

일정 편집 화면에서 알림 offset 값을 저장할 수 있고, core에는 macOS notification request를 계산하고 예약하는 서비스가 있습니다. 현재 UI 저장 동작과 실제 `UNUserNotificationCenter` 예약 연결은 다음 단계 작업입니다.

## 알려진 제한

- 로그인/외부 캘린더 동기화는 없습니다.
- 한국 공휴일 자동 fetch는 앱 UI에 아직 연결되어 있지 않습니다.
- 백업/복원 기능은 자리만 잡혀 있고 아직 구현하지 않았습니다.
- `Mac start auto-run` 설정은 UI만 있고 실제 Login Items 등록은 아직 연결되어 있지 않습니다.
- 알림 권한 요청과 실제 알림 예약의 앱 UI 통합이 남아 있습니다.

## 개발 메모

현재 검증 명령:

```bash
swift test
./scripts/build_app.sh
```

최근 검증 기준으로 두 명령 모두 성공합니다.

## 다운로드 zip 다시 만들기

```bash
cd MyMacCalendar
./scripts/build_app.sh
mkdir -p ../downloads/MyMacCalendar
cp dist/MyMacCalendar-test-build.zip ../downloads/MyMacCalendar/MyMacCalendar-test-build.zip
```
