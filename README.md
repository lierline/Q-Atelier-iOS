# Q-Atelier iOS 앱

Q-Atelier(의료기기 개발 · 인허가 시스템)를 아이폰 · 아이패드에서 여는 앱입니다.
운영 사이트를 iOS 기본 웹 화면(WKWebView)으로 띄우고, 웹 화면이 스스로 못 하는 일을 앱이 잇습니다.

| 하는 일 | 방법 |
|---|---|
| 브라우저 안에서 만든 파일 저장(내보내기 단추) | `bridge.js` 가 파일을 앱으로 넘기고, 앱이 «파일» 앱의 Q-Atelier 폴더에 저장한 뒤 미리 보기로 엽니다 |
| 서버가 주는 파일 받기(첨부 · 문서) | WKDownload 로 같은 폴더에 받아 미리 보기로 엽니다 |
| 인쇄 | `window.print()` 를 iOS 인쇄 창으로 잇습니다 |
| 확인 창 · 새 창 링크 | alert · confirm · prompt 를 iOS 창으로, 새 창 링크는 같은 화면에서 엽니다 |
| 우리 사이트 밖 주소 | 사파리 · 해당 앱으로 넘깁니다 |
| 망이 끊겼을 때 | 앱 안의 끊김 화면을 띄우고 「다시 시도」 로 마지막 화면을 다시 엽니다 |
| 켜는 장면 · 바탕색 | 붓이 Q 를 긋는 장면을 보여 주고, 상태 표시줄 자리를 사이트 바탕색에 맞춥니다 |

아직 없는 것: 앱 알림, 지문 · 얼굴 로그인, 알림 메일의 링크로 앱 열기.

## 만드는 법

Xcode 프로젝트는 커밋하지 않고 `project.yml` 에서 만듭니다. 맥에서:

```bash
brew install xcodegen
xcodegen generate
open QAtelier.xcodeproj
```

커밋마다 깃허브 액션(`.github/workflows/ios.yml`)이 시뮬레이터용으로 빌드하고, 아이폰 · 아이패드 시뮬레이터에 깔아
밝은 · 어두운 모드 화면과 켜는 장면 영상을 찍어 올립니다(`scripts/shoot.sh`).
켜는 장면은 8배 느리게 녹화하므로, 받은 결과는 `tools/shots.py` 로 실제 속도로 되돌려 봅니다.

```bash
gh run download <실행 번호> -R lierline/Q-Atelier-iOS -n ios-shots -D shots
python tools/shots.py shots/out
```

## 사용 허가

이 저장소의 소스 코드는 메드크래프트의 것이며 사용 허가를 주지 않습니다(All rights reserved).
켜는 장면의 글자에 쓴 JetBrains Mono 는 SIL Open Font License 1.1 을 따릅니다(`QAtelier/Resources/JetBrainsMono-OFL.txt`).
