# MyMacCalendar 정확성 후속 점검

- 점검일: 2026-08-08
- 브랜치: `codex/mymaccalendar-stability-fixes`
- 기준: `6818ae2`
- 원칙: 실제 사용자 Application Support 저장소와 알림 데이터를 사용하지 않음

## 수정 결과

| 영역 | 확인한 문제 | 수정 결과 |
|---|---|---|
| 알림 계획 | 손상된 `Int.max` offset이 날짜 확장 일수 덧셈을 overflow시킴 | overflow를 검사하고 해당 일정의 불가능한 계획을 제외 |
| upcoming 조회 | 음수 horizon이 역방향 `DateInterval`을 만들어 프로세스를 중단시킴 | 서비스 경계에서 빈 결과 반환 |
| 플로팅 상세 | 반복 일정의 미래 회차를 눌러도 원본 anchor 날짜를 표시 | 선택한 `EventOccurrence` 날짜를 불변 상세 snapshot으로 전달 |
| 위젯 표시 | 메뉴의 임시 표시 상태가 이후 Settings 변경을 계속 덮어씀 | 저장 설정 변경 시 임시 override를 해제하는 상태 머신 적용 |
| 휴일 숨김 | API가 이름/provider key를 바꾸면 숨긴 날짜가 다시 나타날 수 있음 | 같은 연도·날짜도 숨김 기준으로 사용 |
| 휴일 가져오기 | 중복 응답, 요청 연도 밖 날짜, 부분 손상 응답 방어 부족 | 공통 import planner로 중복 차단, 연도 밖 제외, 잘못된 날짜가 있으면 전체 응답 거부 |
| 연도 갱신 | 앱 시작·연도 변경 자동 fetch가 구현되지 않음 | 현재 연도에 API 기록이 없을 때 시작/날짜 변경/12시간 주기로 한 번 시도 |

## 자동 검증

- `swift package dump-package`: 통과
- Sources/Tests 전체 `swiftc -parse`: 통과
- `swift test --disable-sandbox --no-parallel`: **125 tests, 0 failures**
- `swift build -c release --disable-sandbox`: 통과
- `./scripts/build_app.sh`: 통과
- Info.plist/entitlements `plutil -lint`: 통과
- 전체 셸 스크립트 `bash -n`: 통과
- 앱 번들 `codesign --verify --deep --strict`: 통과

레거시 migration 테스트에서는 기존과 동일한 Core Data model checksum 및 Objective-C `Array<Int>` materialize 경고가 출력됐지만 3개 migration 테스트와 전체 suite는 통과했다.

## 격리 앱 스모크

사용 경로: `/tmp/MyMacCalendarCorrectnessAudit.qlimBr`
전용 bundle identifier: `com.mymaccalendar.audit.20260808`

- 빈 임시 SwiftData 저장소로 시작하고 현재 연도 온라인 휴일 18개가 자동 추가되는 것을 확인했다.
- 가져온 1월 1일 휴일을 숨긴 뒤 수동 재가져오기에서 `새 휴일 없음`과 숨김 유지를 확인했다.
- 앱 재실행 뒤에도 숨긴 휴일이 목록에 다시 나타나지 않았다.
- 매주 반복 일정을 생성하고 8월 15일 회차를 위젯에서 눌렀을 때 상세 날짜가 `2026년 8월 15일 (토)`로 표시됐다.
- 위젯 Settings off/on, 메인 창을 닫은 플로팅 전용 모드, 일정 수정·삭제와 재실행 후 삭제 유지를 확인했다.
- 로그에는 기존 migration checksum 경고, 입력기 로그, 알림 실패의 event UUID와 `NSError`만 있었고 일정 제목·메모는 없었다.
- 테스트 프로세스, 임시 저장소/앱, 전용 UserDefaults domain을 정리했다.

## 남은 제한

- Computer Use가 테두리 없는 위젯 drag에서 `noWindowsAvailable`을 반환해 실제 origin 변경은 이번에도 자동 UI 입력으로 증명하지 못했다. 드래그 코드와 저장 구조 검사는 통과한다.
- 실제 알림 권한 허용/거부와 전달은 Developer ID로 서명한 최종 배포 앱에서 별도 확인해야 한다.
- 백업/복원 UI, 기존 휴일의 인라인 편집, 공개 배포 notarization은 아직 구현 또는 검증되지 않았다.
- 레거시 fixture 경고는 남아 있으므로 실제 사용자 저장소 업그레이드는 백업 복사본으로 먼저 확인해야 한다.
