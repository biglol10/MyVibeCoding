# MyMacCalendar 안정성 후속 점검

- 점검일: 2026-08-13
- 브랜치: `codex/mymaccalendar-stability-fixes`
- 기준: 커밋 `6818ae2` 위의 기존 미커밋 정확성 수정 포함
- 원칙: 실제 사용자 Application Support 저장소와 알림 데이터를 사용하지 않음

## 수정 결과

| 영역 | 확인한 문제 | 수정 결과 |
|---|---|---|
| 알림 계획 | `[Int.max, 1]`처럼 손상값과 정상값이 섞이면 event 단위 overflow 방어가 정상 알림까지 제거 | 표현 가능한 offset만 남긴 뒤 확장 범위를 계산해 `1일 전` 알림 보존 |
| 빠른 추가 | 평년의 `2/29`가 날짜 확인 실패로 처리되고, 윤년의 2월 29일이 지난 뒤에는 과거 날짜를 반환 | 최대 8년 범위에서 다음 유효한 날짜를 찾아 2100년 같은 세기 윤년 예외까지 처리 |
| 빠른 추가 저장 | 날짜 없는 입력이나 잘못된 날짜가 fallback인 오늘로 즉시 저장될 수 있음 | 제출 정책을 분리하고 오늘 저장 전에 명시적 확인 대화상자 표시 |
| 플로팅 위젯 | 화면과 일부만 겹쳐도 정상 위치로 간주하고, 외부 모니터 제거 뒤 열린 창을 재배치하지 않음 | 창 전체를 가시 화면에 clamp하고 화면 구성 변경 알림에서 즉시 재검증 |
| 플로팅 위젯 | 저장 origin이 NaN/무한대이면 AppKit에 손상된 좌표를 전달할 수 있음 | 순수 위치 검증 계층에서 유한하지 않은 값을 안전한 기본 위치로 교체 |

SwiftData 스키마와 저장 위치는 변경하지 않았다.

## 테스트 주도 재현

- 정상 offset과 `Int.max`가 함께 있을 때 기존 결과가 빈 배열임을 확인한 뒤 정상 offset 보존으로 수정했다.
- 2026년 `2/29`와 2028년 3월 이후 `2/29` 테스트가 각각 fallback/과거 날짜로 실패하는 것을 확인한 뒤 2028년/2032년으로 수정했다.
- 빠른 추가 제출 정책과 위젯 위치 계산은 타입이 없는 컴파일 실패를 확인한 뒤 최소 구현했다.

## 자동 검증

- `swift package dump-package`: 통과
- Sources/Tests 전체 `swiftc -parse`: 통과
- 변경된 순수 Swift 로직 Swift 6 typecheck: 통과
- `swift test --disable-sandbox --no-parallel`: **135 tests, 0 failures**
- `swift build -c release --disable-sandbox`: 통과
- `./scripts/build_app.sh`: 통과
- Info.plist/entitlements `plutil -lint`: 통과
- 전체 셸 스크립트 `bash -n`: 통과
- 앱 번들 `codesign --verify --deep --strict`: 통과
- `git diff --check`: 통과

레거시 migration 테스트에서는 기존과 동일한 Core Data model checksum 및 Objective-C `Array<Int>` materialize 경고가 출력됐지만 3개 migration 테스트와 전체 suite는 통과했다.

## 격리 앱 스모크

사용 경로: `/tmp/MyMacCalendarStabilityAudit.VyvMwC`

전용 bundle identifier: `com.mymaccalendar.audit.20260813.stability`

- 고유 bundle identifier와 `MYMACCALENDAR_STORE_URL`로 빈 임시 저장소를 사용했다.
- 위젯 origin을 `99999, 99999`로 넣고 시작한 뒤 메인 창을 닫았을 때 260 x 260 위젯이 현재 화면 안에 표시됐다.
- 날짜 없는 `날짜 확인 테스트` 입력에서 오늘 날짜 미리보기와 경고를 확인했다.
- `추가`를 누르면 `이 날짜로 추가할까요?` 확인 대화상자가 열리고, 취소하면 빠른 추가 화면과 입력값이 유지됐다.
- `2/29 윤년 확인`은 `2028년 2월 29일 화요일`로 미리보기가 표시되고 추가 확인 없이 정상 저장됐다.
- 앱 로그에는 기존 Core Data checksum과 macOS 입력기 로그만 있었고 일정 제목, 메모, 저장소 전체 경로, 크래시는 없었다.
- 테스트 앱, 저장소, 로그, 전용 UserDefaults domain을 정리했다.

## 남은 제한

- 실제 알림 권한 허용/거부와 전달은 Developer ID로 서명한 최종 배포 앱에서 별도 확인해야 한다.
- 플로팅 위젯의 화면 복구는 실제 단일 디스플레이에서 화면 밖 저장값으로 확인했다. 물리적 외부 모니터 연결/분리는 순수 다중 화면 테스트와 AppKit 알림 배선으로 검증했다.
- 레거시 fixture 경고가 남으므로 실제 사용자 저장소 업그레이드는 백업 복사본으로 먼저 확인해야 한다.
- 백업/복원, 휴일 인라인 편집, 공개 배포 notarization은 이번 패치 범위에 포함하지 않았다.
