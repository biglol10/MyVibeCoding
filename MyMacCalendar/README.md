# MyMacCalendar

MyMacCalendar는 macOS용 로컬 우선 캘린더 앱입니다. 하루 종일 일정 관리, 간단한 반복 일정, 직접 등록·삭제할 수 있는 휴일, 설정 기반 플로팅 위젯을 목표로 만든 독립 앱입니다. Apple Calendar나 외부 계정 로그인 없이 SwiftData에 로컬 저장합니다.

## 주요 기능

- 월간 달력 화면과 우측 일정 패널
- 하루 종일 일정 생성, 수정, 삭제
- 주간, 월간, 연간 반복 일정
- 7일 전, 2일 전, 1일 전, 당일 알림 옵션 저장과 macOS 알림 예약/취소
- 빠른 일정 추가: `6/30 codex 만료`, `2026-06-30 codex`, `다음주 월요일 병원`; 날짜를 확정하지 못하면 저장 전 확인
- 제목/메모 검색, 검색 결과에서 해당 날짜 이동 및 일정 편집
- 직접 휴일 등록/삭제, 현재 연도 온라인 휴일 자동 가져오기, 가져온 휴일 숨김 처리
- 메뉴바 아이콘과 플로팅 upcoming 위젯
- 위젯 표시, 항상 위, 투명도, 표시 개수 설정
- 시작 시 자동 실행, 메뉴바 표시, 달력 밀도 설정
- 설정 창: General, Widget, Notifications, Holidays, Appearance, Data

## 현재 동작 확인

최근 수동 검증에서 확인한 흐름입니다.

- 일정 생성 후 월 셀 점 표시와 우측 패널 반영
- 우측 일정 행 클릭 후 편집 화면 진입
- 일정 삭제 확인 다이얼로그와 삭제 후 패널/재실행 유지
- 수동 휴일 등록, 삭제, 재실행 후 삭제 유지
- 빠른 추가 입력 중 Preview와 Add 버튼 활성화
- 빠른 추가의 날짜 없는 입력은 오늘로 저장하기 전에 확인하고, `2/29`는 다음 윤년으로 계산
- `Command-F`로 검색 필드 이동, 제목/메모 검색, 결과 선택 후 해당 날짜와 편집 화면 이동
- 플로팅 위젯에 upcoming 일정 표시
- 오늘 일정은 위젯에서 빨간 막대, 이후 일정은 파란 막대로 표시
- 설정에서 플로팅 위젯 on/off 시 실제 위젯 창 생성/숨김
- 저장된 위젯 위치가 화면 밖이거나 모니터 구성이 바뀌면 현재 화면 안으로 복구
- 설정에서 온라인 휴일 가져오기, 숨김 유지, 메뉴바 표시, 시작 시 자동 실행 설정
- 앱 시작 시 현재 연도 휴일 자동 가져오기와 같은 연도 중복 요청 방지

전체 기능별 검증 범위는 [2026-08-04 전체 기능 점검표](docs/verification/2026-08-04-full-feature-audit.md)에, 최신 안정성 수정과 후속 검증은 [2026-08-08 정확성 점검](docs/verification/2026-08-08-correctness-audit.md)에 기록합니다.

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

## 테스트

전체 테스트:

```bash
swift test --disable-sandbox --no-parallel
```

현재 테스트 범위:

- 월간 달력 grid 생성
- 반복 일정 occurrence 확장
- upcoming 일정 정렬/검색
- 빠른 추가 parser
- 빠른 추가 윤년 계산과 날짜 확인 제출 정책
- 반복 일정의 90일 알림 계획, 월말/윤년 보정, 전역 상한
- 알림 add-before-remove, 취소/교체/삭제 경쟁 상태와 orphan 정리
- 휴일 API decode/fetch/merge
- API 휴일 숨김 유지, 이름 변경·중복·잘못된 연도/날짜 방어
- 현재 연도 휴일 자동 갱신 판단
- 수동 휴일 우선 처리
- 기본 설정 생성과 설정 UI 동작 연결
- 플로팅 위젯 표시/드래그/고정 크기/전체 보기
- 화면 밖·손상 위치와 모니터 변경 시 위젯 위치 복구
- 일정 생성, 수정, 삭제, 휴일 처리 E2E 성격의 store workflow
- 저장 실패 rollback, 손상 설정값 정규화, 레거시 저장소 마이그레이션

테스트에는 실제 동작을 실행하는 테스트와 SwiftUI/AppKit 연결 구조를 확인하는 소스 검사가 함께 포함됩니다. 실제 macOS 창 조작 여부는 위 전체 기능 점검표에서 별도로 구분합니다.

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

앱 데이터는 SwiftData 영구 저장소에 로컬로 저장됩니다. 영구 저장소를 열거나 준비하지 못하면 메모리 저장소로 대체하지 않고 편집을 차단하는 오류 화면을 표시합니다. 일정, 휴일, 설정은 앱을 종료하고 다시 열어도 유지됩니다. 현재 백업/복원 UI는 아직 구현하지 않았습니다.

초기 배열 형태의 알림 offset을 사용하던 저장소는 versioned migration으로 현재 문자열 표현으로 옮깁니다. 카테고리 도입 전 저장소와 카테고리가 추가된 중간 저장소를 모두 지원합니다. 마이그레이션은 저장소를 자동 삭제하거나 새 빈 저장소로 교체하지 않으며, 실패하면 동일하게 편집을 차단합니다.

## 휴일 처리

수동 휴일 등록과 삭제는 앱 설정의 `Holidays` 탭에서 사용할 수 있습니다. 같은 탭에서 온라인 휴일을 가져올 수 있고, API로 가져온 휴일이 잘못됐을 때 숨김 처리하면 공급자 이름이 바뀌더라도 같은 연도와 날짜의 휴일은 다시 나타나지 않습니다.

앱 시작 시 현재 연도의 API 휴일이 저장돼 있지 않으면 한 번 자동으로 가져옵니다. 실행 중에는 달력 날짜 변경 알림과 12시간 유지보수 주기에서 연도 변경을 확인하며, 같은 세션에서 이미 시도한 연도는 반복 요청하지 않습니다. 자동 가져오기가 실패해도 기존 휴일을 변경하지 않으며 설정 화면의 수동 가져오기는 계속 사용할 수 있습니다.

## 알림 처리

일정 편집 화면에서 알림 offset 값을 저장하면 `UNUserNotificationCenter`를 통해 macOS 알림을 예약합니다. 반복 일정은 실제 fire date 기준 90일 범위에서 계산하며, 월말과 윤년 날짜를 보정합니다. 갱신은 새 batch를 모두 추가한 뒤 이전 identifier를 제거하고, 취소나 부분 실패가 발생하면 staging batch를 정리합니다. 앱 시작 시 존재하지 않는 일정의 orphan 알림도 정리합니다. macOS 알림 권한이 거부되어 있으면 pending 알림을 변경하지 않습니다.

## 알려진 제한

- 로그인/외부 캘린더 동기화는 없습니다.
- 백업/복원 기능은 자리만 잡혀 있고 아직 구현하지 않았습니다.
- 공용 배포는 Developer ID 서명과 notarization 설정이 필요합니다.
- 레거시 배열형 알림 offset fixture의 마이그레이션과 재개방은 통과하지만, 현재 SDK가 해당 배열 속성을 읽을 때 Core Data 경고를 출력합니다. 실제 사용자 저장소 업그레이드는 백업 복사본으로 먼저 확인해야 합니다.
- 알림 계획과 비동기 경쟁 상태는 fake client로 검증했지만, 최종 배포 서명에서 macOS 권한 허용·거부와 실제 알림 전달을 별도로 스모크해야 합니다.

## 개발 메모

현재 검증 명령:

```bash
swift test --disable-sandbox --no-parallel
swift build -c release --disable-sandbox
./scripts/build_app.sh
```

최근 검증 기준으로 위 명령은 성공합니다. 개인 설치 zip은 필요할 때 `./scripts/package_personal.sh`로 생성하며, 출력 경로는 `dist/MyMacCalendar-personal-mac.zip`입니다.
