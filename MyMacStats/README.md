# MyMacStats

MyMacStats는 macOS 시스템 상태를 한 화면에서 확인하는 SwiftUI 유틸리티입니다. CPU, RAM, Disk, Network, Battery, Processes 상태를 왼쪽 사이드바에 요약하고, 선택한 항목의 원인 목록과 상세 정보를 가운데/오른쪽 패널에 보여줍니다.

## 환경

- macOS 14 이상
- Xcode Command Line Tools
- Swift 6 이상

## 실행

```bash
cd MyMacStats
swift run MyMacStatsApp
```

## 테스트

```bash
cd MyMacStats
swift test
```

## 앱 번들 및 zip 생성

```bash
cd MyMacStats
./scripts/build-app-bundle.sh
open dist/MyMacStats.app
```

스크립트는 `dist/MyMacStats.app`과 `dist/MyMacStats-test-build.zip`을 생성합니다.

## MVP 포함 기능

- SwiftUI 3-column 대시보드
- CPU/RAM/Disk/Network/Battery/Processes 사이드바 요약
- CPU/RAM/Processes 프로세스 목록, 검색, 정렬
- CPU 60초 sparkline
- RAM 위험 상태에서 높은 메모리 사용 프로세스 요약
- Disk 메인 볼륨 사용량
- Network 활성 인터페이스 업로드/다운로드 속도
- Battery 전원 상태, 충전 상태, 사이클 수 표시 시도
- HealthEvaluator debounce 및 임계값 단위 테스트

## MVP 제외 항목

- 메뉴바 상주 모드
- 프로세스 강제 종료
- 알림
- 팬/온도/GPU 센서
- MyMacClean/FlowPilot 연동
- 기록 저장 및 일별 리포트

## 폴더 구조

- `Package.swift`: Swift Package 설정
- `Sources/MyMacStatsCore`: 모델, 포맷터, health 판정, system sampler
- `Sources/MyMacStatsAppSupport`: refresh service와 dashboard view model
- `Sources/MyMacStatsApp`: SwiftUI 앱 진입점과 화면
- `Tests`: Core와 AppSupport 단위 테스트
- `scripts`: 앱 번들/zip 생성 스크립트
