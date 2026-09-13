# Android Markdown Reader

개인 사용을 위한 휴대폰 우선 Markdown 리더입니다. 태블릿 화면에도 대응하며, 문서 원문을 수정·저장·생성·이름 변경·삭제하지 않는 읽기 전용 앱입니다. Android 시스템 파일 선택기로 문서 하나 또는 폴더를 열고, 선택한 트리 안의 상대 경로 이미지도 표시합니다.

## 사용자 기능

- 문서와 폴더 열기, 목차 제목 검색·접기/펼치기·현재 읽는 절 강조, 본문 검색
- 현재 폴더의 파일·폴더 이름 검색 (하위 폴더 전체 검색은 제외)
- 글자 크기와 줄 간격 조절
- 라이트·다크·나이트 테마 (Night 청회색 기본)
- 폴더 새로고침 및 조회 실패·로딩 상태 안내
- 표, 코드, 수식, Mermaid, 로컬 이미지 렌더링
- 인터넷 이미지는 문서별로 허용할 때만 불러오며 HTTPS 주소만 허용

읽을 문서의 폴더를 선택하면 상대 경로 이미지가 함께 열립니다. Android가 `Download` 루트 폴더 선택을 제한하면 그 안에 만든 하위 폴더를 선택하세요.

## 제한

문서는 UTF-8 기준 8 MiB, 이미지는 20 MiB, 폴더 목록은 1,000개까지입니다. 인터넷 이미지는 기본 차단이며, 문서마다 허용 여부를 다시 선택합니다.

Android 8 이상과 최신 Android System WebView 업데이트를 권장합니다. Android 15 전용 에뮬레이터와 Chromium 휴대폰·태블릿 화면으로 검증했으며, 사용자 실기기에는 설치하지 않았습니다.

## 개인 APK 만들기

저장소 루트에서 reader bundle을 만든 뒤 Android 호스트를 빌드합니다.

```sh
node Android/scripts/build-reader.mjs
cd Android
./gradlew :app:assembleDebug
```

개인 release APK는 저장소 루트에서 다음 명령으로 만듭니다.

```sh
python3 Android/scripts/package-apk.py
```

현재 배포 파일은 [Android 1.2.3 APK 다운로드](https://github.com/biglol10/MyVibeCoding/raw/main/downloads/MyMacMarkdownViewer/MarkdownReader-1.2.3-Android.apk)입니다. 새 빌드 파일명은 앱 버전을 따릅니다. 개인 서명 자료 `~/.local/share/mymarkdownreader-signing`이 있어야 업데이트 가능한 동일 서명이 유지됩니다. 이 폴더의 비밀 내용은 공개하거나 저장소에 추가하지 마세요.

## 구조와 브리지

`Android/app`은 파일 선택기와 읽기 전용 native host이고, `Android/reader`는 WebView reader bundle입니다. WebView는 `https://appassets.androidplatform.net/reader/index.html`에서 bundle을 읽습니다. asset UI는 `window.AndroidBridge.postMessage(JSON.stringify(message))`로 host에 요청하고, host 이벤트는 `window.ReaderHost.receive(event)`로 전달합니다.

## 1.1.1 업데이트

폴더의 파일명과 유형을 한 번에 조회하여 개별 파일 정보 조회 실패에 따른 누락을 줄였다. 조회 실패·로딩은 빈 폴더로 표시하지 않으며 현재 폴더의 새로고침을 지원한다. 기존 설치는 최초 업데이트 실행 때 한 번 Night로 전환하고, 이후 사용자가 선택한 테마와 글자 크기·줄 간격은 유지한다.

## 1.2.0 탐색 개선

검색을 지우면 이전 목차 접기 상태로 돌아오며, 다른 문서를 열면 초기화합니다. 가로 화면에서도 파일 목록을 바로 확인할 수 있습니다. [구현·검증 기록](../docs/Outline-Navigation-Release-2026-09-12.md).

## 1.2.1 이어 읽기

마지막 문서·읽던 위치·탐색 폴더를 복원합니다. 화면 회전·테마 변경 후에도 읽기 비율을 유지합니다. 문서 접근 폴더와 탐색 폴더를 구분하고, 만료되거나 잘못된 폴더 정보가 읽을 수 있는 문서의 복원을 막지 않도록 했습니다.

## 1.2.2 읽기 가독성

코드·인라인 코드·표의 최소 글자 크기, 문법 색상과 검색 강조 대비를 개선했습니다. 이 글자 크기는 본문 글자 크기 설정과 함께 확대됩니다.

## 1.2.3 코드 언어 표시

코드 상자와 Mermaid 위에 언어 이름을 표시합니다. 언어가 없으면 ‘텍스트’로 표시하며, 표시를 눌러도 원문은 바뀌지 않습니다. 읽기 전용 앱에는 언어 변경 기능이 없습니다. [검증 범위](../docs/Code-Language-Verification-2026-09-13.md)를 확인하세요.
