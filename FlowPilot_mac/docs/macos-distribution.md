# FlowPilot macOS Distribution

다른 Mac에서 다운로드 후 바로 실행되는 배포 파일은 Developer ID 서명과 Apple 공증이 필요합니다.
로컬 개발용 `package:macos` 산출물은 ad-hoc 서명이라 MyVibeCoding 같은 외부 배포에 쓰면 Gatekeeper가 앱을 차단하고
휴지통으로 이동하라는 경고를 표시할 수 있습니다.

## Prerequisites

- Apple Developer Program 멤버십
- Keychain에 설치된 `Developer ID Application: ...` 인증서
- Apple notarization credentials
- Apple Silicon 대상 배포 기준의 현재 산출물: `FlowPilot_0.1.0_aarch64.dmg`

현재 Mac에 배포용 인증서가 있는지 확인합니다.

```bash
security find-identity -v -p codesigning
```

출력에 `Developer ID Application:` 항목이 있어야 합니다. `Apple Development:` 인증서는 개발 실행용이며 외부 배포용이 아닙니다.

## Store Notary Credentials

권장 방식은 notarytool keychain profile입니다.

```bash
xcrun notarytool store-credentials "flowpilot-notary" \
  --apple-id "APPLE_ID_EMAIL" \
  --team-id "TEAM_ID" \
  --password "APP_SPECIFIC_PASSWORD"
```

## Build a Signed and Notarized DMG

```bash
source "$HOME/.cargo/env"
APPLE_NOTARY_KEYCHAIN_PROFILE="flowpilot-notary" \
FLOWPILOT_DEVELOPER_ID="Developer ID Application: YOUR_NAME_OR_COMPANY (TEAM_ID)" \
npm run package:macos:release
```

이 명령은 다음을 모두 수행합니다.

- Tauri app bundle 빌드
- `FlowPilot.app` Developer ID 서명
- `FlowPilot.app` 공증 및 staple
- DMG 생성
- DMG Developer ID 서명
- DMG 공증 및 staple
- `spctl` Gatekeeper 평가

성공 산출물:

```text
src-tauri/target/release/bundle/dmg/FlowPilot_0.1.0_aarch64.dmg
```

## Create MyVibeCoding Zip

공증된 DMG만 ZIP에 포함되도록 검증한 뒤 압축합니다.

```bash
npm run package:macos:distribution
```

성공 산출물:

```text
release/FlowPilot_mac_arm64.zip
```

MyVibeCoding에는 이 ZIP을 업로드합니다.

## Personal Mac Install Without Notarization

본인 소유의 다른 Mac에만 설치할 목적이고 공개 배포를 하지 않는다면 Developer ID 공증 없이 개인용 패키지를 사용할 수 있습니다.
이 방식은 앱을 바로 더블클릭하지 않고 설치 스크립트로 `/Applications`에 복사한 뒤 macOS 다운로드 quarantine 속성을 제거합니다.

```bash
npm run package:macos:personal
```

성공 산출물:

```text
release/FlowPilot_personal_mac_arm64.zip
```

다른 Mac에서는 ZIP을 푼 뒤 터미널에서 다음을 실행합니다.

```bash
cd ~/Downloads/FlowPilot_personal_mac_arm64
chmod +x install-flowpilot-personal.command
./install-flowpilot-personal.command
```

이 개인용 ZIP은 본인 Mac 사이에서만 사용합니다. 공개 다운로드 링크나 불특정 사용자 배포에는 Developer ID 서명과 공증된 DMG를 사용합니다.

## Validation Commands

```bash
xcrun stapler validate src-tauri/target/release/bundle/dmg/FlowPilot_0.1.0_aarch64.dmg
spctl --assess --type open --verbose=4 src-tauri/target/release/bundle/dmg/FlowPilot_0.1.0_aarch64.dmg
```

앱 번들도 확인하려면:

```bash
codesign -dv --verbose=4 src-tauri/target/release/bundle/macos/FlowPilot.app
spctl --assess --type execute --verbose=4 src-tauri/target/release/bundle/macos/FlowPilot.app
```

## Notes

- 현재 패키지는 Apple Silicon(`aarch64`)용입니다. Intel Mac까지 지원하려면 x86_64 또는 universal 빌드가 별도로 필요합니다.
- Chrome 도메인 집계용 확장 프로그램은 ZIP에 unpacked extension 형태로 포함됩니다. 일반 사용자가 개발자 모드 없이 설치하게 하려면 Chrome Web Store 배포가 추가로 필요합니다.
- 공증되지 않은 ZIP이나 ad-hoc signed app에 quarantine 제거 명령을 안내하는 방식은 최종 사용자 배포 방식으로 사용하지 않습니다.
