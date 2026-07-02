# MyMacCalendar

MyMacCalendar는 macOS용 로컬 우선 캘린더 앱입니다. 하루 종일 일정 관리, 간단한 반복 일정, 직접 편집 가능한 휴일, 설정 기반 플로팅 위젯을 목표로 만든 독립 앱입니다. Apple Calendar나 외부 계정 로그인 없이 SwiftData에 로컬 저장합니다.

## 다운로드

- macOS 개인 설치 zip: [MyMacCalendar-personal-mac.zip](https://github.com/biglol10/MyVibeCoding/raw/main/downloads/MyMacCalendar/MyMacCalendar-personal-mac.zip)
- 기존 test-build 호환 zip: [MyMacCalendar-test-build.zip](https://github.com/biglol10/MyVibeCoding/raw/main/downloads/MyMacCalendar/MyMacCalendar-test-build.zip)

현재 zip은 Apple Developer ID 서명과 공증이 없는 개인/테스트 빌드입니다. GitHub에서 받은 zip을 압축 해제한 뒤 앱을 직접 더블클릭하지 말고, 동봉된 `Install MyMacCalendar.command`를 Finder에서 우클릭해 여세요. 설치 헬퍼가 다운로드 격리 속성을 제거하고 `/Applications/MyMacCalendar.app`으로 설치합니다.

## 주요 기능

- 월간 달력 화면과 우측 일정 패널
- 하루 종일 일정 생성, 수정, 삭제
- 주간, 월간, 연간 반복 일정
- 7일 전, 2일 전, 1일 전, 당일 알림 옵션 저장
- 빠른 일정 추가: `6/30 codex 만료`, `2026-06-30 codex`, `다음주 월요일 병원`
- 제목/메모 기반 일정 검색
- 한국 공휴일 가져오기, 직접 휴일 등록과 삭제
- API로 가져온 휴일을 숨김 처리할 수 있는 core merge 로직
- 메뉴바 아이콘과 플로팅 upcoming 위젯
- 위젯 표시, 항상 위, 투명도, 표시 개수 설정
- 설정 창: General, Widget, Notifications, Holidays, Appearance, Data

## 현재 동작 확인

최근 수동 검증에서 확인한 흐름입니다.

- 일정 생성 후 월 셀 점 표시와 우측 패널 반영
- 우측 일정 행 클릭 후 편집 화면 진입
- 일정 삭제 확인 다이얼로그와 삭제 후 패널/재실행 유지
- 한국 휴일 가져오기, 수동 휴일 등록, 삭제, 재실행 후 삭제 유지
- 빠른 추가 입력 중 Preview와 Add 버튼 활성화
- 플로팅 위젯에 upcoming 일정 표시
- 오늘 일정은 위젯에서 빨간 막대, 이후 일정은 파란 막대로 표시
- 설정에서 플로팅 위젯 on/off 시 실제 위젯 창 생성/숨김
- 설정에서 메뉴바 아이콘 표시와 Mac 시작 시 자동 실행을 실제 앱 동작에 반영

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

아이콘을 새로 만들려면:

```bash
./scripts/generate_app_icon.swift
```

또는

```bash
./scripts/generate_app_icon.sh
```

생성되는 앱 번들 위치:

```text
build/MyMacCalendar.app
```

## 다른 Mac에 설치하기

공개 배포용으로 바로 쓰는 경우:

1. Mac Developer 계정에서 `Developer ID Application` 인증서를 준비합니다.
2. `./scripts/package_release.sh`를 실행해 노타라이즈 zip을 만듭니다.
3. 생성된 zip(`dist/MyMacCalendar-0.1.0-macOS.zip`)을 배포합니다.

개인 용도로 여러 Mac에 옮겨 쓰는 경우:

1. `./scripts/package_personal.sh`를 실행해 개인용 zip(`dist/MyMacCalendar-personal-mac.zip`)을 만듭니다.
2. 압축 해제 후 `Install MyMacCalendar.command`를 우클릭해서 실행합니다.
3. 설치 후 필요한 권한이 있으면 시스템 설정에서 허용합니다.

참고로 개인용 패키지는 이 Mac에서의 동작을 전제로 한 패키지로, 다운로드 격리 속성 제거와 로컬 ad-hoc 서명을 수행합니다.

기존 README 링크 호환을 위해 `MyMacCalendar-test-build.zip`도 같은 개인 설치 패키지 구조로 갱신합니다.

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
- 설정 변경과 앱 동작 연결
- 이벤트 편집, 월간 grid 상호작용, 플로팅 위젯 표시

## 프로젝트 구조

```text
Sources/MyMacCalendar
  App/                 macOS 앱 진입점과 AppDelegate
  Controllers/         메뉴바, 플로팅 위젯 controller
  Views/               SwiftUI 화면

Resources/
  AppIcon.icns         앱 번들 아이콘

Sources/MyMacCalendarCore
  Models/              SwiftData 모델
  Services/            달력, 반복, 휴일, 알림, 빠른 추가 로직
  Stores/              SwiftData container/settings store

Tests/MyMacCalendarCoreTests
  Core 로직 단위 테스트

scripts/build_app.sh
  release build 후 .app 번들 생성
scripts/package_personal.sh
  개인 Mac 설치용 zip 생성
scripts/package_release.sh
  Developer ID 서명과 notarization 기반 공개 배포 zip 생성
```

## 데이터 저장

앱 데이터는 SwiftData를 통해 로컬에 저장됩니다. 일정, 휴일, 설정은 앱을 종료하고 다시 열어도 유지됩니다. 현재 백업/복원 UI는 자리만 잡혀 있고 아직 구현하지 않았습니다.

## 휴일 처리

수동 휴일 등록과 삭제는 앱 설정의 `Holidays` 탭에서 사용할 수 있습니다.

Core에는 Nager.Date API 응답 decode와 merge 로직이 있습니다. Settings의 Holidays 탭에서 한국 공휴일을 가져올 수 있고, API 휴일이 잘못됐을 때 숨김 처리하면 같은 provider key로 다시 가져와도 유지되도록 테스트되어 있습니다. 앱 시작 시 자동으로 API를 fetch하는 스케줄링은 아직 남은 작업입니다.

## 알림 처리

일정 편집 화면에서 알림 offset 값을 저장할 수 있고, core에는 macOS notification request를 계산하고 예약하는 서비스가 있습니다. 현재 UI 저장 동작과 실제 `UNUserNotificationCenter` 예약 연결은 다음 단계 작업입니다.

## 알려진 제한

- 로그인/외부 캘린더 동기화는 없습니다.
- 백업/복원 기능은 자리만 잡혀 있고 아직 구현하지 않았습니다.
- 알림 권한 요청과 실제 알림 예약의 앱 UI 통합이 남아 있습니다.
- 공개 배포용 notarized zip은 Developer ID 인증서와 notarization 설정이 필요합니다.

## 개발 메모

현재 검증 명령:

```bash
swift test
./scripts/build_app.sh
./scripts/package_personal.sh
```

최근 검증 기준으로 세 명령 모두 성공합니다.

## 다운로드 zip 다시 만들기

```bash
cd MyMacCalendar
./scripts/package_personal.sh
mkdir -p ../downloads/MyMacCalendar
cp dist/MyMacCalendar-personal-mac.zip ../downloads/MyMacCalendar/MyMacCalendar-personal-mac.zip
cp dist/MyMacCalendar-personal-mac.zip ../downloads/MyMacCalendar/MyMacCalendar-test-build.zip
```
