# 목차와 폴더 탐색 개선

2026-09-12. 권장한 1차 탐색 범위(목차 검색·접기, Android 현재 폴더 이름 검색·현재 절 표시)를 구현했다. 이전 작업의 변경을 보존했으며 설치된 Mac 앱 교체, 커밋, 외부 발송은 수행하지 않았다.

## 바뀐 사용 흐름

- Mac·Windows·Android의 **목차** 탭에서 제목을 찾고, 제목 옆 화살표 또는 **모두 접기 / 모두 펼치기**로 목록을 정리한다. 검색 결과에는 일치 제목과 상위 제목만 보인다. 검색을 지우면 이전 접기 상태로 돌아온다.
- 제목을 누르면 해당 위치로 이동한다. 같은 이름의 제목과 건너뛴 제목 단계도 구분한다. 파일·목차 탭 왕복은 검색/접기 상태를 유지하며 다른 문서로 이동하면 초기화한다. 편집으로 제목/위치가 바뀌면 접기 상태를 비운다.
- Android 파일 탭의 **현재 폴더에서 찾기**는 현재 표시한 파일·폴더 이름을 좁힌다. 입력마다 저장소를 다시 조회하지 않는다. 같은 폴더 새로고침은 검색을 유지하고 다른 폴더는 초기화한다. 하위 폴더 전체 본문 검색은 이 기능의 범위에 포함되지 않는다.
- Android 목차는 현재 읽는 절을 강조한다. 스크롤 때 제목 위치를 매번 측정하지 않고, 크기·이미지·글자 설정 변경 후에만 갱신한다. 같은 절 안에서는 목차의 속성/목록을 쓰지 않는다.
- 검색 중에는 접기 버튼을 비활성화하고 보이는 펼침 상태와 접근성 안내를 맞췄다. 빈 검색·제목 없는 문서 안내, 키보드 토글 포커스 유지, 긴 제목/파일명 표시를 확인했다.
- Android 가로 화면에서는 중복 안내 영역을 줄여 첫 파일 행을 스크롤 없이 볼 수 있다. 읽기 전용 상태와 Night 기본값은 유지한다.
- 이전 단계의 빠른 파일 열기 키보드/목록 새로고침 수정도 이번 배포본에 포함된다.

주요 파일: `Sources/Core/OutlineNavigation.swift`, `Sources/App/OutlineSidebarView.swift`, `Sources/App/AppModel.swift`, `Sources/App/WorkspaceView.swift`, `Windows/ui/outline.mjs`, `Windows/ui/shell.mjs`, `Windows/ui/shell.css`, `Windows/ui/index.html`, `Android/reader/reader.ts`, `Android/reader/reader.css`, `Android/reader/index.html`.

## 직접 확인한 검증

- Mac: Swift 핵심 테스트 41개 통과. Apple Silicon / macOS 26.6.2의 Universal Release 앱을 복제한 별도 QA 식별자로 실제 화면을 열었다. 검색·조상 표시·중복 제목의 두 번째 위치 이동·접기 후 탭 왕복 유지·검색 0건·다른 문서로 초기화를 확인하고 QA 앱을 종료했다. 설치된 앱은 0.2.2 (5)로 유지했다.
- Mac 자동 회귀: 저장·BOM/줄바꿈·실행 취소·자동 저장·외부 변경 충돌·권한 오류·복구·폴더 이동·검색/바꾸기·HTML/PDF 출력 검사 통과. 약 3 MB/20,003줄에서 파일 읽기부터 2프레임까지 829 ms, 자동 입력 p95 38 ms, 네이티브 연결 p95 62 ms로 기존 성능 기준을 통과했다. [원시 결과](outline-mac-validation.json).
- Windows: 핵심 테스트 19개와 Electron 목차·빠른 열기·파일 관리·디자인·우클릭 메뉴 검증을 Astra가 다시 실행했다. 800×560 창에서 사이드바를 220px로 줄이고 검색·긴 제목·중복 위치·Space/Enter 포커스·탭/문서 전환·실제 제목 편집을 확인했다. 기존 기본 너비 250px는 유지한다. 같은 절 위치 갱신은 목차 DOM을 교체하지 않는다. 포터블 패키지의 ASAR로도 목차 검증을 통과했다. 테스트 초기 프레임 대기와 종료 대기는 기능 오류와 구분해 보완했으며, 종료 제한 시간이 넘으면 해당 테스트가 띄운 프로세스만 정리한다.
- Android: 최종 리더 자산을 대상으로 navigation/browser/settings 검증을 Astra가 실행했다. 393×852, 852×393, 1024×768 화면과 28px 본문, 1,000개 항목, NFC/대소문자 검색, 제목 없는 문서, 마지막 짧은 절 및 같은 절 스크롤의 목차 변경 0건을 확인했다. 읽기 전용 요소·참조/각주/본문 목차·표/수식/다이어그램·Night 마이그레이션도 회귀 검사했다. Luna가 최종 서명 APK를 전용 Android 15 에뮬레이터에 업데이트 설치하고 SAF 조회 회귀 5개를 통과했다. Astra가 최종 APK 해시·압축 무결성·122개 자산 일치·초기 버튼 속성을 독립 대조했다.

화면 기록은 `Windows/test-results/outline-search.png`, `Android/test-results/navigation-outline-search.png`, `navigation-folder.png`, `navigation-landscape.png`, `navigation-phone.png`에 있다. 화면 크기만 설정한 검증과 실제 기기 입력 검증을 구분한다.

## 배포와 제한

배포 버전은 Mac·Windows **0.3.0**, Android **1.2.0 (6)**이다. 최종 패키지 확인 결과는 [Windows](windows-verification-results.json), [Android](outline-android-release.json), [통합 배포 기록](outline-release.json)에 기록한다.

실제 Windows PC, 사용자 Android 기기, 물리 두벌식 입력, Intel/macOS 14 실행은 이번 검증에 포함되지 않는다. Mac은 개인용 ad-hoc 서명이며 공증하지 않았고 Windows는 서명하지 않은 포터블 ZIP이다. Android는 기존 개인 서명을 유지한다. 최근 문서 바로 열기는 별도 후속 후보이다.

이전 QA에서 관측한 폴더 감시 초기화 지연의 정확한 원인은 아직 확정하지 않았다. 이번 Mac 통합 QA는 완료됐으며, 이를 감시 엔진의 모든 지연이 해결된 증거로 취급하지 않는다.

## 리뷰에서 반영한 교훈

`.codex/lessons.md`에 검색/접기 상태와 키보드 포커스, 스크롤 갱신 비용, 낮은 화면의 실제 결과 노출 및 테스트 근거 구분을 기록했다. 변경 사항을 검토하고 필요한 검증을 반복했다.

검증 환경 참고: Electron 프레임이 초기 15초 안에 준비되지 않는 경우를 관측했다. 당시 10코어 Mac의 시스템 부하 평균은 500 이상이었다. 준비 대기를 60초까지 분리했으며, 높은 부하가 직접 원인인지는 확정하지 않았다. 기능 검증 통과를 일반적인 앱 시작 성능의 증거로 해석하지 않는다.
