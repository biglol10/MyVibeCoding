# FlowPilot_mac

FlowPilot_mac은 Tauri, React, TypeScript, Rust로 만든 데스크톱 활동 추적 앱입니다. 활성 앱/창과 브라우저 탭 도메인을 수집하고, 생산성 분류 규칙을 적용해 오늘 요약, 타임라인, 주간 리포트, 미분류 검토 화면을 제공합니다.

## 다운로드

- macOS DMG: [FlowPilot_0.1.0_aarch64.dmg](https://github.com/biglol10/MyVibeCoding/raw/main/downloads/FlowPilot_mac/FlowPilot_0.1.0_aarch64.dmg)
- macOS arm64 전체 패키지 zip: [FlowPilot_mac_arm64.zip](https://github.com/biglol10/MyVibeCoding/raw/main/downloads/FlowPilot_mac/FlowPilot_mac_arm64.zip)
- Windows 설치 파일: [FlowPilot_0.1.0_x64-setup.exe](https://github.com/biglol10/MyVibeCoding/raw/main/downloads/FlowPilot_mac/FlowPilot_0.1.0_x64-setup.exe)
- Windows portable zip: [FlowPilot-0.1.0-portable.zip](https://github.com/biglol10/MyVibeCoding/raw/main/downloads/FlowPilot_mac/FlowPilot-0.1.0-portable.zip)
- Windows 단일 실행 파일: [flowpilot.exe](https://github.com/biglol10/MyVibeCoding/raw/main/downloads/FlowPilot_mac/flowpilot.exe)

> macOS 빌드는 로컬 개발 인증서 방식으로 만든 산출물입니다. 처음 실행할 때 권한 또는 보안 경고가 나올 수 있습니다.

## 환경

- Node.js 22 LTS와 npm (`.nvmrc` 포함)
- Rust 1.77.2 이상
- Tauri 2 CLI는 npm devDependency로 설치됨
- macOS 앱 추적: Accessibility, Screen Recording 권한 필요
- 브라우저 도메인 추적: `browser-extension`을 Chrome 확장 프로그램 개발자 모드로 로드

## 주요 기능

- 오늘 요약, 타임라인, 주간 리포트
- 앱/창/도메인 기반 활동 세션 저장
- 생산적, 비생산, 중립, 제외, 검토 필요 분류
- 기본 규칙과 사용자 규칙 관리
- 도메인, 앱, 제목 키워드, URL 패턴 규칙 타입
- 미분류 항목 검토 후 빠른 규칙 생성
- 차트와 정렬/검색 가능한 사용량 테이블
- 오늘 활동 CSV 내보내기 로직
- Chrome 확장 프로그램이 `127.0.0.1:17321/browser-event`로 활성 탭 정보를 전달

## 웹 UI 개발 실행

```bash
cd FlowPilot_mac
nvm use
npm ci
npm run dev
```

## Tauri 데스크톱 실행

```bash
cd FlowPilot_mac
nvm use
npm ci
npm run tauri -- dev
```

## 테스트

프론트엔드 테스트:

```bash
cd FlowPilot_mac
nvm use
npm test
```

Rust/Tauri 테스트:

```bash
cd FlowPilot_mac/src-tauri
cargo test
```

브라우저 확장 테스트:

```bash
cd FlowPilot_mac/browser-extension
nvm use
npm ci
npm test
```

## macOS 패키징

```bash
cd FlowPilot_mac
nvm use
npm ci
npm run package:macos
```

생성된 DMG는 `src-tauri/target/release/bundle/dmg/FlowPilot_0.1.0_aarch64.dmg`에 만들어집니다.

## 브라우저 확장 빌드와 로드

```bash
cd FlowPilot_mac/browser-extension
nvm use
npm ci
npm run build
```

Chrome에서 `chrome://extensions`를 열고 Developer mode를 켠 뒤 `FlowPilot_mac/browser-extension` 폴더를 Load unpacked로 추가합니다.

## 폴더 구조

- `src`: React 앱, 페이지, 차트, 테이블, 규칙 UI
- `src-tauri`: Rust/Tauri 백엔드, 수집기, SQLite 저장소, 권한 처리
- `browser-extension`: Chrome 활성 탭 도메인 브리지
- `scripts/package-macos-local.mjs`: macOS 앱 번들, 서명, DMG 생성 자동화
- `assets`: 앱 아이콘 원본
- `tests/e2e`: Playwright E2E 테스트
