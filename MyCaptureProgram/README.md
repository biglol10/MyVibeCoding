# MyCaptureProgram

MyCaptureProgram은 `CaptureStudio`라는 SwiftUI 기반 macOS 캡처 앱입니다. Windows Snipping Tool처럼 빠른 스크린샷과 화면 녹화를 목표로 만들었고, 캡처 직후 편집, OCR, 빠른 가리기까지 한 흐름에서 처리합니다.

## 다운로드

- macOS arm64 실행 파일 zip: [CaptureStudio-macos-arm64.zip](https://github.com/biglol10/MyVibeCoding/raw/main/downloads/MyCaptureProgram/CaptureStudio-macos-arm64.zip)

> 현재 배포 파일은 개발용으로 직접 서명/공증하지 않은 빌드입니다. macOS Gatekeeper가 차단하면 Finder에서 우클릭 후 열기를 사용하거나, 소스에서 직접 빌드해서 실행하세요.

## 환경

- macOS 15 이상
- Xcode Command Line Tools
- Swift 6 이상
- 화면 캡처/녹화 기능 사용 시 macOS의 Screen Recording 권한 필요

## 주요 기능

- 스크린샷 모드와 화면 녹화 모드
- 사각형, 창, 전체 화면, 자유형 캡처 영역 모델
- 캡처 결과 편집 캔버스
- 펜, 형광펜, 화살표, 사각형, 타원, 텍스트 주석
- 빠른 가리기/블러 목적의 redaction 레이어
- Vision 기반 OCR 결과 패널과 텍스트 복사
- 저장/복사 시 편집 레이어를 PNG로 합성
- 출력 폴더, 파일명, 단축키 설정 모델

## 소스 실행

```bash
cd MyCaptureProgram
swift run CaptureStudio
```

## 테스트

기본 단위 테스트:

```bash
cd MyCaptureProgram
swift test
```

ScreenCaptureKit과 실제 캡처 흐름을 포함한 통합 테스트:

```bash
cd MyCaptureProgram
CAPTURE_STUDIO_RUN_INTEGRATION=1 swift test
```

## 배포 파일 다시 만들기

```bash
cd MyCaptureProgram
swift build -c release
ditto -c -k --keepParent .build/arm64-apple-macosx/release/CaptureStudio ../downloads/MyCaptureProgram/CaptureStudio-macos-arm64.zip
```

## 폴더 구조

- `Package.swift`: Swift Package 설정
- `Sources/CaptureStudio/App`: 앱 상태와 앱 진입점
- `Sources/CaptureStudio/Capture`: 스크린샷/녹화/선택 영역 처리
- `Sources/CaptureStudio/Editing`: 편집 도구, 레이어, 렌더링
- `Sources/CaptureStudio/OCR`: OCR 모델과 서비스
- `Sources/CaptureStudio/Redaction`: 빠른 가리기 감지 로직
- `Sources/CaptureStudio/Settings`: 앱 설정 저장
- `Sources/CaptureStudio/Shortcuts`: 단축키 모델
- `Sources/CaptureStudio/Views`: SwiftUI 화면
- `Tests/CaptureStudioTests`: 단위/통합 테스트
