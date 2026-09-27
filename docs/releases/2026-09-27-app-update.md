# 전체 앱 변경 반영 — 2026-09-27

원본 프로젝트의 현재 코드와 테스트를 MyVibeCoding에 반영했다. 원본의 미커밋 작업은 그대로 두었고, 로컬 캐시·서명 비밀·개인 검증 로그는 복사하지 않았다. 이 저장소에서 직접 수정된 MyMacStats와 기존 Finder 외부 폴더 연동, FlowPilot 아이콘 구성을 유지했다.

## 앱별 반영과 이번 검증

| 앱 | 반영 내용 | 이번 검증 |
|---|---|---|
| CaptureStudio | MP4 오디오 처리, Trim Copy 원본 보존, 주석·단축키·프리셋, 카운트다운 취소와 편집 화면 개선 | Swift 339개 중 328개 통과·권한 필요 11개 제외, Release 빌드·개인 설치 ZIP |
| MyMacCalendar | 반복 일정 전체 편집 확인, 동시 알림 묶음과 상태 안내, 위젯 전체 목록, 월 이동·시간대와 V4 데이터 변환 | Swift 145개 통과, Release 빌드·개인 설치 ZIP |
| MyMacClean | 삭제 권한 복구 안내, 스캔·파일 크기·후보 판단 및 삭제 기록 안전성 | Swift 217개 통과, Release 빌드·DMG |
| MyMacFinder | 파일 작업·외부 앱 열기·폴더 크기·파일 정보 및 목록 사용성 | Swift 645개 통과, Release 빌드·개인 설치 ZIP. 기존 외부 폴더 연동 보존 |
| MyMacStats | 프로세스/PID 구분과 종료 확인, 알림 경쟁 상태, CPU·배터리·디스크 상태 및 목록/설정 개선 | Swift 113개 통과, Release 빌드·개인 설치 ZIP |
| MyMarkdownViewer Mac | 표 입력 보존, 검색창 실행 취소, 자동 저장 초점, 링크·목차 이동과 충돌 해결 안내 | Swift 51개, 편집기 단위 21개, WebKit 화면 95개 통과. Mac 0.3.7(13) 기존 최신 빌드의 편집기 리소스 235개와 현재 산출물 일치 |
| MyMarkdownViewer Windows | 동일 공통 편집기 수정을 포함해 0.3.8로 재패키징 | Windows 단위 25개 통과. ZIP 무결성·AMD64 실행 파일·ASAR와 현재 소스/리소스 일치 |
| MarkdownReader Android | 앱 코드 변경 없음. 업데이트 서명을 유지하는 기존 1.2.3 APK 포함 | APK v2/v3 서명, 패키지·버전과 SHA-256 확인 |
| FlowPilot | 현재 네이티브 코드와 아이콘 설정으로 설치 파일 갱신, 프런트엔드 의존성 잠금 불일치 보정 | Swift 85개, 프런트엔드 69개·패키징 스크립트 11개 통과. 프런트엔드 빌드·네이티브 ZIP·DMG |
| MyMacSearch | 새 변경/별도 원본 없음. 기존 설치 파일 유지 | 기존 ZIP 무결성·포함 앱 서명 확인. 이번에 재빌드하지 않음 |

## 다운로드

[전체 배포 페이지](https://github.com/biglol10/MyVibeCoding/releases/tag/apps-2026-09-27)에서 설치 파일과 SHA-256을 제공한다. Windows ZIP은 GitHub 일반 파일 크기 제한을 넘으므로 Release 자산으로만 제공한다. 나머지 앱은 루트 및 앱별 README의 다운로드 링크와 `downloads/`에서도 받을 수 있다.

| 파일 | SHA-256 |
|---|---|
| `CaptureStudio-personal-mac.zip` | `4cb0b12637bc26363293eda8f639db7af4b6d4afec2445038005ccc1ff1bf119` |
| `MyMacCalendar-personal-mac.zip` | `8987d7ac546b60aba3edaead9397bbbe6025f38eb380689dcf41dbd59e597b72` |
| `MyMacClean-dev.dmg` | `bbb8ac572f93b7d8b309981327ddaec56e6edd530620215b55409779046dbc5e` |
| `MyMacFinder-personal-mac.zip` | `6616112026e8cfe9f3edbf863f74b9b9623208494031a1057f479eebde6a8a03` |
| `MyMacStats-test-build.zip` | `02b15f2b327556f4bfd31637d6f2c17cb50fa252a2b045441d6b5e48170a91b9` |
| `FlowPilot_native_mac_arm64.zip` | `ba41bb8be16e00156f969c54bc009def203c3a74c95ee6e982d72006c1dcbf44` |
| `FlowPilot_native_mac_arm64.dmg` | `5109307a9584f01d6eee52f9b4543630c243a2d4b7ea796e487e5def34a7a93e` |
| `MyMarkdownViewer-0.3.7-macOS.zip` | `1549588d1b938c016d4fbed9e420a8847d93b44b93cd03dca64abbdda2f529d8` |
| `MarkdownReader-1.2.3-Android.apk` | `ae7208a7d109f32ba869a0acf224dfed1b83b41e2b734d94f7a1e792e8d001da` |
| `MyMarkdownViewer-0.3.8-Windows-x64.zip` | `c127f9e14c6970aa8070015cc7edd5d01003415bab29f14c3133405ff899b7c5` |
| `MyMacSearch-personal-mac.zip` | `e3efb644206718b603dda0f586cd5f1576cb89df36ff0903796fd39b095ba95a` |

## 검증 경계

- macOS 앱은 개인 사용용 ad-hoc 서명 빌드이며 Apple 공증 배포본이 아니다.
- 이번 작업은 코드 동기화, 테스트와 패키징이다. 설치 앱이나 사용자 데이터를 교체하지 않았다.
- 실제 Windows·Android 기기 실행, 물리적 두벌식 입력, 실녹음·화면 녹화와 실제 알림 전달은 이번에 검증하지 않았다.
- CaptureStudio의 기존 AVAssetWriter Sendable 경고와 FlowPilot의 큰 프런트엔드 번들 경고는 남아 있다.
