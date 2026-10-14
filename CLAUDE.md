# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 프로젝트 개요

LyricsSlideCreator는 멜론(Melon.com)에서 노래를 검색하여 가사와 앨범아트를 가져오고, 템플릿 기반으로 PowerPoint 프레젠테이션을 생성하는 PySide6(Qt Quick/QML) GUI 애플리케이션이다. UI 라벨과 코드 주석은 한국어로 작성되어 있다.

## 실행 방법

```bash
# 의존성 설치 (venv 사용 권장). 버전은 고정돼 있다
pip install -r requirements.txt          # 실행용 (PySide6-Essentials 등)
pip install -r requirements-build.txt    # 빌드용 (위 + Nuitka)

# 개발 모드 실행
python run.py
```

## 빌드·릴리스

```bash
python scripts/build.py 1.2.0   # 버전 기록(scripts/set_version.py) + Nuitka 빌드
```

- macOS: Nuitka `--mode=app` → `dist/가사 슬라이드 생성기.app` + `-macOS.zip`(ditto). 화면에 보이는 이름은 '가사 슬라이드 생성기'(`APP_NAME`, `windows.iss` `AppName`), 파일·번들 ID·설치 폴더·AppId 등 내부 이름은 영문 그대로(업데이트와 연결). 번들 ID `io.github.seungheony.lyricsslidecreator`
- Windows: Nuitka `--mode=standalone` → 실행 파일 아이콘 넣기(`add_exe_icon`, Nuitka `--windows-icon-from-ico`는 쓰지 말 것: QtWidgets를 빼서 Nuitka가 덧붙이는 PySide6 아이콘 코드가 실패하고 앱이 시작하자마자 접근 위반으로 죽음 — v1.2.0-beta.4) → Inno Setup(`installer/windows.iss`, 사용자 계정 설치, 제거 시 전부 삭제) → `-Setup.exe`
- 실행 파일 하나(onefile)는 실행마다 압축을 풀어 느리고 사용자 폴더에 캐시를 남기므로 쓰지 않는다
- `scripts/build.py`의 `EXCLUDED_QT`로 쓰지 않는 Qt 모듈(웹 엔진 등)을 뺀다. QML에서 새 Qt 모듈을 import하면 여기서 빠져 있지 않은지 확인할 것
- 빌드 중에는 `src/`, `assets/`를 수정하지 말 것 (Nuitka가 파일 목록을 먼저 만들고 나중에 복사해서 섞인다)
- CI는 러너(windows-2022, macos-14)·Python 패치 버전·Inno Setup 버전을 고정한다(올릴 때는 베타로 먼저 확인). 최상위 권한은 `contents: read`, 릴리스 잡만 `write`. 버전 형식은 `-beta.N`만 허용(workflow_dispatch 기본값도 `0.0.0-beta.1`). `scripts/build.py`는 빌드 뒤 `_build_info.py`를 지우고, macOS는 Info.plist에 한국어 정보를 넣은 뒤 ad-hoc 재서명한다
- `.github/workflows/release.yml`: 태그 `v*` 푸시 → Windows/macOS 빌드 → 검증(`--self-test`, Windows는 `scripts/verify_windows.ps1`로 설치·실행·제거 후 남은 파일 확인) → SHA256SUMS.txt와 함께 릴리스. 절차: `scripts/release.sh`를 인자 없이 실행해 메뉴로 고른다(master가 아니거나 뒤처져 있으면 먼저 master로 바꾸고 pull할지 묻고, 받은 뒤 master의 release.sh로 다시 실행). `1) 베타 배포`(버전 입력, 프리릴리스) → 업데이트·기능 직접 테스트(`docs/RELEASE_CHECKLIST.md`) → `2) 정식 배포`(마지막 베타와 같은 커밋에 정식 태그, 릴리스가 만들어질 때까지 기다린 뒤 그 버전의 베타 릴리스를 확인 받고 지움 — 공개 저장소라 릴리스를 숨길 수 없어서. 태그는 남김. 못 지웠으면 `3) 베타 릴리스 정리`). 브랜치는 작업 브랜치 → master PR 하나뿐(develop 없음). 정식 릴리스 노트 범위는 `scripts/notes_start_tag.py`가 정한다(같은 커밋의 베타 기준이면 비기 때문). 빌드·검증은 태그 푸시(=`release.sh`) 때만 실행하고 PR에서는 하지 않는다(필요하면 workflow_dispatch로 수동 실행)

**자동 업데이트** (`src/utils/updater.py`): GitHub 릴리스 목록에서 새 버전 확인 → 설치 파일 다운로드 + SHA256 검증 → Windows는 설치 파일을 `/VERYSILENT`로 실행, macOS는 앱 종료 후 .app을 교체·재실행하는 스크립트 실행. 릴리스 파일 이름 규칙(`-Setup.exe`, `-macOS.zip`, `SHA256SUMS.txt`)을 바꾸면 업데이트가 깨진다. `LSC_UPDATE_API` 환경변수로 다른 릴리스 목록 주소를 써서 시험할 수 있다.

## 아키텍처

**진입점**: `run.py` — 전역 예외 핸들러 설정 후 `src/qml_ui/app.py`의 `main()` 실행. `create_app()`은 실행(exec) 없이 앱/엔진/백엔드를 만들어 테스트에서도 쓸 수 있다.

**UI 레이어** (`src/qml_ui/`):
- `app.py` — Pretendard 등록, Basic 스타일 지정, QML 엔진에 `backend`/`assetsUrl` 컨텍스트 프로퍼티와 앨범아트 이미지 프로바이더(`image://art/<song_id>`) 등록.
- `backend.py` — QML이 호출하는 `Backend`(QObject). 네트워크/PPT 생성은 스레드 풀에서 실행하고 결과를 시그널(JSON 문자열)로 돌려준다. 앨범아트는 Python(requests)이 내려받아 `AlbumArtProvider`로 전달 — Qt의 TLS 플러그인에 의존하지 않기 위함.
- `qml/` — `Main.qml`(페이지 전환·단축키), `SearchPage.qml`, `EditorPage.qml`(가사 편집·히스토리), `SlideList.qml`(미리보기·나누기/합치기·줄 드래그 앤 드롭), 공용 컴포넌트, `HelpButton.qml`/`Tour.qml`(? 버튼 → 대상만 밝힌 단계별 튜토리얼. 단계 내용은 `EditorHelp.qml`·`SearchPage.qml` `showHelp()`. 예시 동작은 `Demo.qml`(가짜 포인터 `DemoCursor`, 스크립트 재생)로 실제 화면 위에 재생하고, 바뀌는 모습은 복제본 `DemoSlides.qml` 등을 덮어 그린다 — 실제 가사는 건드리지 않음), `Theme.qml`(디자인 토큰 싱글턴, 다크 모드), `editor.js`(슬라이드 모델 순수 로직).
- 편집 모델: 가사 텍스트가 유일한 원본이고, 빈 줄로 구분된 덩어리가 슬라이드 한 장. 미리보기에서의 편집도 텍스트를 고쳐 쓰는 방식으로 처리한다.
- 줄 드래그 규칙(`editor.js` `resolveDrop`/`planDrop`): 첫 줄은 앞 슬라이드 끝·앞쪽 새 슬라이드, 마지막 줄은 뒤 슬라이드 처음·뒤쪽 새 슬라이드로만 (꺼짐 상태에선 3줄이 돼도 그대로). "2줄 유지"(`keepTwo`, 기본 켜짐)를 켜면 2줄을 넘은 슬라이드는 같은 방향으로 연쇄 밀기(맨 앞/뒤는 새 슬라이드), 줄이 빠진 슬라이드는 반대쪽 이웃에서 연쇄로 당겨 채움. 합치기·입력칸은 줄 수 제한 없음. 단 2줄 유지 중이면 3줄 이상이 생길 때 확인(`ConfirmDialog`): 합치기는 실행 전, 입력은 입력칸 포커스가 빠질 때 한 번('그대로 두기'한 슬라이드는 다시 묻지 않음)

**리소스** (`assets/`): Pretendard 폰트(템플릿 폰트와 동일), SVG 아이콘.

**백엔드** (`src/utils/`):
- `melon_api.py` — `MelonScraper` 클래스가 멜론에서 노래 검색 결과와 가사/앨범아트를 스크래핑. BeautifulSoup + 정규식 사용. 멜론 HTML 구조 변경 시 깨질 수 있음.
- `ppt_engine.py` — `PPTBuilder` 클래스가 템플릿 PPTX를 로드하고, 슬라이드 구조를 딥카피하여 서식 유지, "가사" 플레이스홀더 텍스트를 교체, `BytesIO`로 메모리 내 슬라이드 생성.
- `line_fit.py` — PPT에서 가사 한 줄이 글상자 폭을 넘어 줄바꿈되는지 미리 계산(`LineFit.ratio`, 1 초과면 줄바꿈). 값은 코드에 두지 않고 템플릿 가사 글상자(`ppt_engine.find_lyrics_shape`, PPT 생성과 같은 글상자)에서 PowerPoint 상속 순서(런→문단→목록 스타일→레이아웃→마스터→텍스트 스타일→기본값, 테마 글꼴)대로 폭·안쪽 여백·글꼴·크기·굵게·자간·커닝 등을 읽는다. 폭은 PowerPoint 규칙 그대로(16.109 Mac에서 200줄로 확인): 글자별 설계 폭을 1/8pt로 반올림해 합산, 커닝은 글꼴에 예전 방식 `kern` 표가 있을 때만(GPOS 무시), 합 > 쓸 수 있는 폭이면 줄바꿈, `hangingPunct`면 줄 끝 문장부호 한 글자(`HANGING_PUNCT`)는 제외. 비율은 반올림하지 않는다(1/8pt만 넘어도 줄바꿈). 글꼴이 이 컴퓨터에 없으면 어림값(`exact=False`). 템플릿 내장 글꼴은 MTX 압축이라 쓰지 않음. 결과는 `SlideList`에 줄별 경고로 표시
- `helpers.py` — `resource_path()`가 PyInstaller(`sys._MEIPASS`)에서는 번들 폴더, 그 외(개발 모드·Nuitka)에서는 프로젝트 루트 기준으로 경로를 해석.
- `version.py` — `get_version()`은 빌드 시 기록된 버전, 개발 모드에서는 "TEST". `parse_version()`/`is_newer()`로 릴리스 태그(v1.2.0, v1.2.0-beta.1, v1.1-beta) 비교.

**주요 패턴**:
- `__init__.py` 파일 없음. `sys.path` 주입으로 모듈 탐색
- 프로젝트 루트의 `template.pptx`가 필수이며 실행 파일에 번들됨
- 메모리 내 PPT 생성(BytesIO), 임시 파일 미사용
- 앱 폴더 밖에 파일을 남기지 않는다: QML 디스크 캐시·GPU 파이프라인 캐시를 끈다(`app.py`). 설정 저장 등 새 기능을 넣을 때도 이 원칙을 지킨다
  - 앱 상태 기록(첫 실행 튜토리얼을 봤는지)은 앱 폴더 안 `app_state.json`(`src/utils/app_state.py`). 업데이트하면 앱 폴더가 새로 깔려 기록도 초기화되고(튜토리얼 다시 표시), 쓸 수 없으면 무시한다
  - 허용된 예외(OS가 남기는 기록): OS 기본 파일 대화상자의 마지막 폴더 기록(macOS `~/Library/Preferences/<앱>.plist`, Windows 레지스트리), macOS Metal 셰이더 캐시(`/var/folders/.../C/<앱>/com.apple.metal`)
- 자동화된 테스트 스위트 없음
