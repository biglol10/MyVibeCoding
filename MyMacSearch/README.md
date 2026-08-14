# MyMacSearch

MyMacSearch는 macOS용 파일명·경로 검색 도구입니다. Spotlight에 핵심 검색을 맡기지 않고, 사용자가 승인한 위치를 초기 스캔한 뒤 SQLite FTS5 인덱스와 FSEvents 변경 감지로 갱신합니다. V1은 파일을 읽기 전용으로 취급하며 삭제하거나 수정하지 않습니다.

## 사용법

첫 실행에서 추천 위치를 확인하고 인덱싱을 시작합니다. 기본 후보는 현재 존재하는 `~/Desktop`, `~/Documents`, `~/Downloads`, `~/Developer/Projects`입니다. 홈 전체를 자동 선택하지 않으며, 외장 디스크와 네트워크 볼륨은 Settings에서 사용자가 명시적으로 허용해야 합니다.

검색창은 일반 단어와 다음 필터를 함께 지원합니다.

```text
ext:swift
kind:pdf
path:Downloads
name:report
modified:today
modified:7d
```

결과에는 이름, 경로, 종류, 크기, 수정일이 표시됩니다. 행을 선택한 뒤 Enter로 열고, Space로 Quick Look을 표시하며, Command-C로 경로를 복사할 수 있습니다. 컨텍스트 메뉴에서는 Open, Reveal in Finder, Copy Path, Open in Terminal, Open in MyMacFinder를 사용할 수 있습니다. 전역 단축키는 Option-Space입니다.

하단 상태바는 `Initial scan`, `Watching`, `Paused`, `Permission needed`, `Error` 상태와 현재 경로, 처리 수, skip 수를 보여줍니다. 결과는 제한된 window와 페이지 방식으로 불러와 대량 결과를 한꺼번에 UI에 올리지 않습니다.

## 인덱싱 정책과 권한

다음 위치 또는 디렉터리는 기본 제외합니다.

- `/System`, `/Library`, `~/Library/Caches`
- `.git`, `.build`, `node_modules`, `DerivedData`
- package bundle 내부

symlink는 항목 자체만 기록하고 대상 디렉터리를 따라가지 않습니다. package bundle도 하나의 항목으로 기록하고 내부로 내려가지 않습니다. hidden file은 별도 설정을 켠 경우에만 포함합니다. 접근할 수 없는 폴더는 앱을 중단시키지 않고 permission denied 또는 skipped로 집계합니다.

Desktop, Documents, Downloads 또는 다른 보호 위치가 차단되면 Settings의 버튼으로 `System Settings > Privacy & Security > Full Disk Access`를 열 수 있습니다. 필요한 이유는 선택한 검색 범위의 파일명과 메타데이터를 읽기 위해서이며, 권한이 없는 위치는 건너뜁니다.

## V1 제한사항

V1은 파일 내용 검색, OCR, PDF 본문 검색을 하지 않습니다. 파일명, 확장자, 경로, 파일 종류, 수정일, 크기 메타데이터만 인덱싱합니다. fuzzy search는 포함하지 않으며 prefix, substring, FTS 검색을 우선합니다. 네트워크 볼륨의 연결 해제, 사라지거나 이동된 파일, 외부 앱 실행 실패는 정상적인 오류 상태로 표시됩니다.

인덱스와 설정은 기본적으로 `~/Library/Application Support/MyMacSearch/`에 저장됩니다. 시스템 SQLite에 FTS5 또는 필요한 trigram tokenizer가 없으면 조용히 다른 엔진으로 바꾸지 않고 명확한 오류를 표시합니다.

## 개발과 테스트

```bash
swift test --package-path MyMacSearch
swift build --package-path MyMacSearch -Xswiftc -warnings-as-errors
MyMacSearch/scripts/run-performance-benchmark.sh
```

일반 테스트에는 쿼리 파서, 인덱스 생성·갱신·삭제, 권한 실패, 취소, FSEvents 계획과 실제 watcher 시작·중지 lifecycle, 결과 테이블 키보드 명령, UI 상태, 외부 액션과 10만 metadata 회귀가 포함됩니다. 100만 건 opt-in benchmark는 다음처럼 실행합니다.

```bash
MYMACSEARCH_RUN_MILLION_BENCHMARK=1 swift test --package-path MyMacSearch -c release --filter MillionEntryIndexBenchmarkTests
```

2026-08-14 개발 Mac의 최근 100만 metadata 생성·인덱싱은 약 173.77초, warm 검색은 p50 8.83ms / p95 10.37ms였고 결과 100건 제한을 사용했습니다. 이 수치는 synthetic benchmark이며 실제 디스크 스캔 시간은 파일 시스템과 권한에 따라 달라집니다.

## 앱 번들 및 개인 설치 ZIP

```bash
MyMacSearch/scripts/build-app-bundle.sh
MyMacSearch/scripts/package-personal.sh
MyMacSearch/scripts/check-distribution.sh
```

생성 파일은 `MyMacSearch/dist/MyMacSearch-personal-mac.zip`입니다. ZIP은 ad-hoc 서명된 개인용 빌드이며 Developer ID notarization을 거친 공개 배포본이 아닙니다. 설치기는 실행 중인 앱의 종료 요청을 짧게 제한한 뒤 기존 `/Applications/MyMacSearch.app`을 임시 백업하고, 새 앱의 strict codesign 검증이 끝난 뒤에만 백업을 제거합니다. 사용자 설정과 인덱스 데이터는 삭제하지 않습니다.
