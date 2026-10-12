# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 프로젝트 개요

LyricsSlideCreator는 멜론(Melon.com)에서 노래를 검색하여 가사와 앨범아트를 가져오고, 템플릿 기반으로 PowerPoint 프레젠테이션을 생성하는 PySide6(Qt Quick/QML) GUI 애플리케이션이다. UI 라벨과 코드 주석은 한국어로 작성되어 있다.

## 실행 방법

```bash
# 의존성 설치 (venv 사용 권장)
pip install -r requirements.txt

# 개발 모드 실행
python run.py
```

## 빌드

빌드 방식은 Nuitka + 설치 파일(Windows: Inno Setup, macOS: .app)로 전환 중이다. `build_windows.bat`(PyInstaller)는 아직 이전 방식이며 assets/QML을 포함하지 않는다.

```bash
# 빌드 전에 버전 기록 (src/utils/_build_info.py 생성, 커밋하지 않음)
python scripts/set_version.py 1.2.0
```

## 아키텍처

**진입점**: `run.py` — 전역 예외 핸들러 설정 후 `src/qml_ui/app.py`의 `main()` 실행. `create_app()`은 실행(exec) 없이 앱/엔진/백엔드를 만들어 테스트에서도 쓸 수 있다.

**UI 레이어** (`src/qml_ui/`):
- `app.py` — Pretendard 등록, Basic 스타일 지정, QML 엔진에 `backend`/`assetsUrl` 컨텍스트 프로퍼티와 앨범아트 이미지 프로바이더(`image://art/<song_id>`) 등록.
- `backend.py` — QML이 호출하는 `Backend`(QObject). 네트워크/PPT 생성은 스레드 풀에서 실행하고 결과를 시그널(JSON 문자열)로 돌려준다. 앨범아트는 Python(requests)이 내려받아 `AlbumArtProvider`로 전달 — Qt의 TLS 플러그인에 의존하지 않기 위함.
- `qml/` — `Main.qml`(페이지 전환·단축키), `SearchPage.qml`, `EditorPage.qml`(가사 편집·히스토리), `SlideList.qml`(미리보기·나누기/합치기·줄 드래그 앤 드롭), 공용 컴포넌트, `Theme.qml`(디자인 토큰 싱글턴, 다크 모드), `editor.js`(슬라이드 모델 순수 로직).
- 편집 모델: 가사 텍스트가 유일한 원본이고, 빈 줄로 구분된 덩어리가 슬라이드 한 장. 미리보기에서의 편집도 텍스트를 고쳐 쓰는 방식으로 처리한다.

**리소스** (`assets/`): Pretendard 폰트(템플릿 폰트와 동일), SVG 아이콘.

**백엔드** (`src/utils/`):
- `melon_api.py` — `MelonScraper` 클래스가 멜론에서 노래 검색 결과와 가사/앨범아트를 스크래핑. BeautifulSoup + 정규식 사용. 멜론 HTML 구조 변경 시 깨질 수 있음.
- `ppt_engine.py` — `PPTBuilder` 클래스가 템플릿 PPTX를 로드하고, 슬라이드 구조를 딥카피하여 서식 유지, "가사" 플레이스홀더 텍스트를 교체, `BytesIO`로 메모리 내 슬라이드 생성.
- `helpers.py` — `resource_path()`가 PyInstaller(`sys._MEIPASS`)에서는 번들 폴더, 그 외(개발 모드·Nuitka)에서는 프로젝트 루트 기준으로 경로를 해석.
- `version.py` — `get_version()`은 빌드 시 기록된 버전, 개발 모드에서는 "TEST". `parse_version()`/`is_newer()`로 릴리스 태그(v1.2.0, v1.2.0-beta.1, v1.1-beta) 비교.

**주요 패턴**:
- `__init__.py` 파일 없음. `sys.path` 주입으로 모듈 탐색
- 프로젝트 루트의 `template.pptx`가 필수이며 실행 파일에 번들됨
- 메모리 내 PPT 생성(BytesIO), 임시 파일 미사용
- 앱 폴더 밖에 파일을 남기지 않는다: QML 디스크 캐시·GPU 파이프라인 캐시를 끈다(`app.py`). 설정 저장 등 새 기능을 넣을 때도 이 원칙을 지킨다
  - 허용된 예외(OS가 남기는 기록): OS 기본 파일 대화상자의 마지막 폴더 기록(macOS `~/Library/Preferences/<앱>.plist`, Windows 레지스트리), macOS Metal 셰이더 캐시(`/var/folders/.../C/<앱>/com.apple.metal`)
- 자동화된 테스트 스위트 없음
