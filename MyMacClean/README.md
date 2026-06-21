# MyMacClean

MyMacClean은 macOS 앱 삭제와 잔여 파일 정리를 돕는 SwiftUI 유틸리티입니다. 설치된 앱을 스캔하고, 관련 파일과 고아 파일을 확인한 뒤 사용자가 직접 검토하고 삭제할 수 있게 만드는 것을 목표로 합니다.

## 다운로드

- macOS 테스트 빌드 zip: [MyMacClean-test-build.zip](https://github.com/biglol10/MyVibeCoding/raw/main/downloads/MyMacClean/MyMacClean-test-build.zip)

> 현재 배포 파일은 개발/테스트용 빌드입니다. 시스템 파일 삭제와 관련된 기능은 반드시 목록을 검토한 뒤 사용하세요.

## 환경

- macOS 14 이상
- Xcode Command Line Tools
- Swift 6 이상
- 앱 관련 파일, 캐시, 로그 일부를 읽으려면 Full Disk Access 권한이 필요할 수 있음

## 주요 기능

- `/Applications` 기준 설치 앱 목록 스캔
- 앱 이름, 번들 ID, 실행 파일명을 이용한 관련 파일 후보 탐색
- 앱 삭제 전 관련 파일 후보와 크기 표시
- 삭제 영수증 저장 및 Delete History 조회
- 이미 삭제된 앱의 잔여 파일을 찾는 Orphan Files 스캔
- 시스템 보호 정책을 둔 위험 경로 제외
- 향후 확장용 메뉴: Startup Items, System Cleanup, Large Files, Maintenance

## 소스 실행

```bash
cd MyMacClean
swift run MyMacCleanApp
```

## 테스트

```bash
cd MyMacClean
swift test
```

## 앱 번들 빌드

```bash
cd MyMacClean
./scripts/build-app-bundle.sh
open dist/MyMacClean.app
```

## DMG 만들기

```bash
cd MyMacClean
./scripts/create-dmg.sh
```

## 다운로드 zip 다시 만들기

```bash
cd MyMacClean
./scripts/build-app-bundle.sh
ditto -c -k --keepParent dist/MyMacClean.app ../downloads/MyMacClean/MyMacClean-test-build.zip
```

## 폴더 구조

- `Package.swift`: Swift Package 설정
- `Sources/MyMacCleanApp`: SwiftUI 앱 진입점과 화면
- `Sources/MyMacCleanAppSupport`: 화면 상태, 내비게이션, ViewModel
- `Sources/MyMacCleanCore`: 앱 발견, 후보 파일 스캔, 삭제 계획/실행/검증, 권한, 안전 정책
- `Sources/MyMacCleanApp/Resources`: 앱 번들용 plist와 아이콘
- `scripts`: 앱 번들/DMG 생성 스크립트
- `Tests`: Core와 AppSupport 단위 테스트
