# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 프로젝트 개요

LyricsSlideCreator는 멜론(Melon.com)에서 노래를 검색하여 가사와 앨범아트를 가져오고, 템플릿 기반으로 PowerPoint 프레젠테이션을 생성하는 PySide6(Qt Quick/QML) GUI 애플리케이션이다. UI 라벨과 코드 주석은 한국어로 작성되어 있다.

## 실행 방법

```bash
# 의존성 설치 (venv 사용 권장, Python 3.13: .python-version, CI와 같은 버전). 버전은 고정돼 있다
pip install -r requirements.txt          # 실행용 (PySide6-Essentials 등)
pip install -r requirements-build.txt    # 빌드용 (위 + Nuitka)

# 개발 모드 실행
python run.py
```

## 빌드·릴리스

```bash
python scripts/build.py 1.2.0   # 버전 기록(scripts/set_version.py) + Nuitka 빌드
```

- macOS: Nuitka `--mode=app` → `dist/Lyrics Slide Creator.app` + `-macOS.zip`(ditto). Apple Silicon 전용(Intel 미지원, 결정 사항). `patch_info_plist`가 `LSMinimumSystemVersion`을 넣는다: 실행 파일·Python·Qt 프레임워크 minos와 바닥값 14.0(PySide6 6.12 휠 태그)의 큰 값이고 빌드 로그에 minos 목록을 찍는다(PySide6 바인딩 .so는 SDK 버전이 찍혀 있어 제외). 최소 버전을 바꾸면 README 설치 안내도 맞출 것. 화면에 보이는 이름은 'Lyrics Slide Creator'(`APP_NAME`, `windows.iss` `AppName`; v1.2.0-beta.4~v1.3.0은 '가사 슬라이드 생성기'), 공백을 쓸 수 없는 곳과 파일·번들 ID·설치 폴더·AppId 등 내부 이름은 `LyricsSlideCreator`(업데이트와 연결). exe 제품 이름(`--product-name`)은 SignPath에 등록한 프로젝트 이름과 같아야 해서 `LyricsSlideCreator`. 번들 ID `io.github.seungheony.lyricsslidecreator`
- Windows: Nuitka `--mode=standalone` → 실행 파일 아이콘 넣기(`add_exe_icon`, Nuitka `--windows-icon-from-ico`는 쓰지 말 것: QtWidgets를 빼서 Nuitka가 덧붙이는 PySide6 아이콘 코드가 실패하고 앱이 시작하자마자 접근 위반으로 죽음 — v1.2.0-beta.4) → Inno Setup(`installer/windows.iss`, 사용자 계정 설치, 제거 시 전부 삭제) → `-Windows-Setup.exe`(v1.4-beta.1까지 `-Setup.exe`. macOS `-macOS.zip`처럼 운영체제를 보이려고 바꿈, 업데이트는 끝부분 `-Setup.exe`로 찾아 예전 앱도 그대로)
- 실행 파일 하나(onefile)는 실행마다 압축을 풀어 느리고 사용자 폴더에 캐시를 남기므로 쓰지 않는다
- `scripts/build.py`의 `EXCLUDED_QT`로 쓰지 않는 Qt 모듈(웹 엔진 등)을 뺀다. QML에서 새 Qt 모듈을 import하면 여기서 빠져 있지 않은지 확인할 것
- 빌드 중에는 `src/`, `assets/`를 수정하지 말 것 (Nuitka가 파일 목록을 먼저 만들고 나중에 복사해서 섞인다)
- CI는 러너(windows-2022, macos-14)·Python 패치 버전·Inno Setup 버전을 고정한다(올릴 때는 베타로 먼저 확인). 최상위 권한은 `contents: read`, 릴리스 잡만 `write`. 버전 형식은 `-beta.N`만 허용(workflow_dispatch 기본값도 `0.0.0-beta.1`). `scripts/build.py`는 빌드 뒤 `_build_info.py`를 지우고, macOS는 Info.plist에 한국어 정보를 넣은 뒤 ad-hoc 재서명한다
- `.github/workflows/release.yml`: 태그 `v*` 푸시 → Windows/macOS 빌드 → 검증(`--self-test`, Windows는 `scripts/verify_windows.ps1`로 설치·실행·제거 후 남은 파일 확인) → SHA256SUMS.txt와 함께 릴리스. 절차: `scripts/release.sh`를 인자 없이 실행해 메뉴로 고른다(master가 아니거나 뒤처져 있으면 먼저 master로 바꾸고 pull할지 묻고, 받은 뒤 master의 release.sh로 다시 실행). `1) 베타 배포`(버전 입력, 프리릴리스. v1.4부터 끝자리 0은 떼고 `1.4`·`1.4.1`로 낸다 — `1.4.0`을 넣어도 `1.4`로 바꾸고, 태그 비교·정렬은 세 자리로 맞춰서 한다(`full_version`). 앱은 `1.4` = `1.4.0`으로 비교) → 업데이트·기능 직접 테스트(`docs/RELEASE_CHECKLIST.md`) → `2) 정식 배포`(대상 베타의 릴리스와 파일 3개를 먼저 확인, 마지막 베타와 같은 커밋에 정식 태그, 태그 푸시가 실패하면 로컬 태그를 지움, 릴리스가 만들어질 때까지 기다린 뒤 그 버전의 베타 릴리스를 확인 받고 지움 — 공개 저장소라 릴리스를 숨길 수 없어서. 태그는 남김. 못 지웠으면 `3) 베타 릴리스 정리`). 브랜치는 작업 브랜치 → master PR 하나뿐(develop 없음). 정식 릴리스 노트 범위는 `scripts/notes_start_tag.py`가 정한다(같은 커밋의 베타 기준이면 비기 때문). 빌드·검증은 태그 푸시(=`release.sh`) 때만 실행한다. PR이나 작업 중 확인용으로 workflow_dispatch 수동 실행도 하지 않고, 빌드에 관련된 변경은 다음 베타 배포에서 확인한다

**자동 업데이트** (`src/utils/updater.py`): GitHub 릴리스 목록에서 새 버전 확인(자동 확인은 조용히, 버전 표시를 누르면 직접 확인) → 설치할 수 있는 위치인지 먼저 확인(`can_install`) → 설치 파일 다운로드 + SHA256 검증(취소·창 닫기 시 받던 파일 삭제) → Windows는 설치 파일을 `/SILENT /SUPPRESSMSGBOXES /LOG`로 실행(실행 직전 앱 뮤텍스를 놓음, `windows.iss` `AppMutex`와 이름이 같아야 함), macOS는 앱 종료 후 `APPLY_SH`가 .app을 백업 이름으로 옮기고 새 앱을 넣은 뒤 실행 파일·서명을 확인해 실패하면 되돌린다(경로는 인자로 넘김, 예전 한글 이름 앱(`LEGACY_APP_NAMES`)은 새 이름으로 옮김). 설치 시작 때 `UPDATE_DIR`에 `pending.json`을 남기고 다음 실행 때 버전을 비교해 성공/실패를 알린다(`take_last_result`). 릴리스 노트는 `## 바뀐 점` 섹션만 보여 주고, 없으면 자동 노트에서 기여자·PR 주소·커밋 접두어를 걷어 낸다(`release_notes`). `release.yml`이 릴리스 노트 맨 위에 붙이는 'Code signing policy' 링크 줄(SignPath Foundation 조건, README 같은 이름의 섹션)도 뺀다. 릴리스 파일 이름 규칙(끝부분 `-Setup.exe`, `-macOS.zip`, `SHA256SUMS.txt`)을 바꾸면 업데이트가 깨진다. 저장소 이름은 2026-10-14에 `lyricsSlide_Creator`에서 `LyricsSlideCreator`로 바꿨다 — v1.3.0까지의 앱은 예전 주소로 확인하고 GitHub가 넘겨줘서 동작하므로, 예전 이름의 저장소를 새로 만들면 그 앱들의 업데이트가 끊긴다. `LSC_UPDATE_API` 환경변수로 다른 릴리스 목록 주소를 써서 시험할 수 있다. 앱 종료 때는 네트워크 작업을 기다리지 않고 PPT 저장만 기다린다(`Backend.shutdown` 후 `os._exit`).

## 아키텍처

**진입점**: `run.py` — 전역 예외 핸들러 설정 후 `src/qml_ui/app.py`의 `main()` 실행. `create_app()`은 실행(exec) 없이 앱/엔진/백엔드를 만들어 테스트에서도 쓸 수 있다.

**UI 레이어** (`src/qml_ui/`):
- `app.py` — Pretendard 등록, Basic 스타일 지정, QML 엔진에 `backend`/`assetsUrl` 컨텍스트 프로퍼티와 앨범아트 이미지 프로바이더(`image://art/<song_id>`) 등록.
- `backend.py` — QML이 호출하는 `Backend`(QObject). 네트워크/PPT 생성은 스레드 풀에서 실행하고 결과를 시그널(JSON 문자열)로 돌려준다. 앨범아트는 Python(requests)이 내려받아 `AlbumArtProvider`로 전달 — Qt의 TLS 플러그인에 의존하지 않기 위함.
- `qml/` — `Main.qml`(곡 담기·단축키. 창은 기본 1100×800·최소 900×560이고 작은 화면에서는 작업 영역의 92%×90%까지 줄여 가운데에 연다(`fitToScreen`, 최소 크기도 같은 한도로 낮춤)), `EditorPage.qml`(늘 보이는 기본 화면: 머리글(앱 이름·콘티 요약)·콘티·가사 편집·히스토리. 콘티가 비면 빈 상태), `SongDrawer.qml`(곡 찾기 서랍: 탭·서랍 튜토리얼), `SearchPanel.qml`(멜론 탭), `PresetLibrary.qml`(보관함 탭), `ManualForm.qml`(직접 입력 탭), `SlideList.qml`(미리보기·나누기/합치기·줄 드래그 앤 드롭), 공용 컴포넌트, `HelpButton.qml`/`Tour.qml`(? 버튼 → 대상만 밝힌 단계별 튜토리얼. 단계 내용은 편집 화면 `EditorHelp.qml`(슬라이드 ? 하나에 미리보기·나누기/합치기·줄 옮기기·2줄 유지·되돌리기를 이어서), 서랍 `SongDrawer.showHelp`. 예시 동작은 `Demo.qml`(가짜 포인터 `DemoCursor`, 스크립트 재생)로 실제 화면 위에 재생하고, 바뀌는 모습은 복제본 `DemoSlides.qml` 등을 덮어 그린다 — 실제 가사는 건드리지 않음), `Theme.qml`(디자인 토큰 싱글턴, 다크 모드), `editor.js`(슬라이드 모델 순수 로직).
- 키보드·접근성: 모든 컨트롤은 Tab으로 닿고 포커스 테두리를 그린다(`AppButton`·`HelpButton`은 `visualFocus`, 결과 행·콘티 행은 직접). `AppButton`은 Return/Enter로 자기 클릭을 먼저 처리해서, 확인창·튜토리얼에서 포커스된 버튼이 실행되고 포커스가 없으면 창의 기본 동작(확인·다음)이 된다. 팝업은 열릴 때 `contentItem`으로 포커스를 되돌린다(전에 포커스한 버튼이 남아 Enter가 그 버튼을 누르는 것을 막음). 검색: 검색칸 ↓ → 결과 목록, ↑↓·Enter로 곡 열기, 첫 행 ↑ → 검색칸. 콘티 목록: ↑↓ 고르기, Enter/Space 편집, Delete 빼기(되돌리기 토스트), Alt+↑↓ 순서. 가사 칸 Tab은 탭 문자 대신 다음 컨트롤로(`EditorPage.moveFocusFrom`). 빈 곳(머리글·여백·막대 바탕, 슬라이드 목록의 카드 밖)을 누르면 입력 커서를 빼고 슬라이드 강조를 푼다(`EditorPage.clearSelection`: 맨 아래 깔린 `MouseArea`와 `SlideList.backgroundClicked`, 가사를 다시 누르면 다시 강조). 아이콘만 있는 `AppButton`에는 `Accessible.name`, `HelpButton`에는 `label`("<label> 도움말")을 준다
- 툴팁·입력칸 메뉴: Qt 기본 툴팁은 다크 모드에서도 흰 상자라 `AppToolTip`(Theme 토큰 `tooltipBg`)을 쓴다 — `ToolTip.visible/text` 어태치드 속성은 쓰지 말 것. 입력칸 오른쪽 클릭 메뉴는 `ContextMenu.menu: AppTextMenu { editor: ... }`(한국어, Qt 6.9+). 가사 칸은 `useHistory`로 되돌리기·다시 실행을 앱 히스토리에 연결하고 붙여넣기는 `notePaste()`로 한 단계로 남긴다. Qt 기본 문구(macOS 앱 메뉴 '끝내기' 등)는 `assets/translations/qtbase_ko.qm`을 `install_translations`가 불러와 한국어로 보인다(빌드된 앱에는 Qt 번역 폴더가 없어 앱에 포함, `--self-test`가 확인). PySide6를 올리면 이 파일도 같은 버전으로 다시 복사
- 오류 대화상자(`AppDialog.showError(제목\n안내, 자세한 내용, 두 번째 동작, 다시 시도)`): 자세한 내용의 마지막 줄을 요약으로 보이고 '자세히 보기'(펼침)·'오류 정보 복사'(`Backend.copyErrorReport`: 버전·OS·내용, 사용자 폴더 경로는 `~`로 바꿈)를 둔다. '다시 시도'는 백엔드가 `retry`를 true로 준 곡 불러오기 실패(연결·응답·예외)에만 나온다. '문제 알리기'는 오류 정보를 복사하고 GitHub 문의 화면을 연다
- 문의하기(`FeedbackDialog.qml`, 편집 화면 아래 막대의 템플릿 도움말 옆): 앱에 GitHub 토큰을 넣지 않으려고 안내만 하고 브라우저로 새 이슈 화면을 연다(`backend.feedback_url`, 양식 `.github/ISSUE_TEMPLATE/feedback.yml` 하나에 종류는 드롭다운, 버전·운영체제 칸을 주소로 미리 채움 — 칸 id `version`·`os`를 바꾸면 같이 고칠 것). 쓰는 사람에게 GitHub 계정이 필요하고 글은 공개된다
- 튜토리얼 카드(`Tour`): 폭은 강조 영역 옆 남은 자리에 맞춰 260~360, 어디에도 안 들어가면 남은 자리가 넓은 쪽 화면 가장자리에 붙인다. 강조 테두리는 예시(Loader) 위에 그린다
- 편집 모델: 가사 텍스트가 유일한 원본이고, 빈 줄로 구분된 덩어리가 슬라이드 한 장. 미리보기에서의 편집도 텍스트를 고쳐 쓰는 방식으로 처리한다.
  - 텍스트를 고쳐 쓸 때는 통째로 바꾸지 않고 바뀐 구간만 지우고 넣는다(`editor.js` `textDiff`, `EditorPage.setText`) — 커서·선택·스크롤·한글 조합을 지키기 위함. 편집 전에는 `prepareEdit()`(조합 중 글자 확정, 미뤄 둔 목록 갱신 반영)
  - 입력 중 슬라이드 목록은 80ms씩 모아서 갱신하고(`sync`), 줄 배열이 바뀐 슬라이드 카드만 고친다(`SlideList` ListModel 차분 갱신). 줄바꿈 비율은 줄별로 캐시
  - 콘티(여러 곡을 한 PPT로): 편집 화면 왼쪽 `SetlistPanel.qml`(곡 제목·줄바꿈 있음 표시, 끌어서 순서, 휴지통으로 빼기 — 0곡까지 뺄 수 있고 다 빼면 빈 상태와 함께 서랍이 열림, 빼면 되돌리기 토스트, 머리의 ⋯ 메뉴 '콘티 비우기'(확인 없이 비우고 되돌리기 토스트, `sessions`는 남음, 서랍이 열림), '곡 추가'). 상태는 `EditorPage` `setlist`(song_id 순서)와 `sessions`(song_id → {song, text, hist, histIdx, 커서·스크롤, kept, savedKey, dirty, slides, wraps, loading})에 세션 메모리로만 둔다. 곡마다 가사 텍스트가 유일한 원본이고 편집기는 고른 곡 하나만 다룬다 — 지금 곡은 화면이 최신이고 곡을 바꾸거나 서랍을 열 때 `storeCurrent()`로 보관. 콘티에서 뺀 곡도 `sessions`에 남아 다시 넣으면 이어서 편집
  - 곡 찾기 서랍(`SongDrawer`, `EditorPage.drawer`): 검색 화면은 따로 없고 편집 화면이 늘 보인다. '곡 추가'·⌘K/Ctrl+K가 콘티 패널 오른쪽에 서랍을 열고(폭 min(430, 남은 폭), 편집 영역을 덮되 아래 막대(`bottomBar`: 템플릿·프리셋·PPT 생성) 위까지만) 멜론 탭 검색칸에 포커스. 시작할 때 콘티가 비어 있으면 저절로 열림. 탭은 아이콘 + 초록 세그먼트(고른 탭으로 초록 칸이 미끄러짐): 멜론 검색(`SearchPanel`) | 직접 입력(`ManualForm`) | 저장한 곡(`PresetLibrary`, 키 `library`, 예전 이름 '보관함')이고 `EditorPage.openDrawer(tab, opts)` → `SongDrawer.show(tab, opts)`로 바꾼다(tab을 주지 않으면 열려 있을 때 탭을 그대로 둠). 서랍은 시그널(`songClicked`·`presetChosen`·`manualSubmitted`)만 내고 담는 일은 `Main`·`EditorPage`가 한다. 서랍에는 아래 막대가 없고 닫기는 머리의 ✕·Esc·바깥(어둡게 덮은 곳) 클릭. Esc는 드래그 취소 → 가사 칸에서 빠져나오기 → 서랍 안에서 먼저 처리할 것(`handleEscape`: 보관함 이름 고치기·삭제 확인 취소) → 서랍 닫기 순서. 머리의 ? 버튼(`HelpButton` '곡 추가')이 서랍 튜토리얼(`showHelp`: 검색 → ＋로 담기 → 보관함·직접 입력 탭 → ✕로 닫기)
    - 끌어다 넣기: 멜론 검색 결과 행과 저장한 곡의 프리셋 줄(`SongDragArea.qml`: 8px 넘게 움직이면 끌기, 아니면 평소 누르기, 목록 스크롤은 휠로)을 왼쪽 콘티로 끌어다 놓으면 놓은 자리(`SetlistPanel.gapAt`, 초록 줄 `externalDrop`)에 담는다. `EditorPage.beginSongDrag/moveSongDrag/endSongDrag`가 커서를 따라가는 표시(`dragGhost`)를 그리고, 놓으면 누를 때와 같은 신호(`songClicked`·`presetChosen`)로 담은 뒤 새로 담긴 곡을 그 자리로 옮긴다(`moveSong`). 콘티에 있는 곡의 프리셋이면 가사만 바뀌고 순서는 그대로. 직접 입력한 곡의 검색 결과는 프리셋을 골라야 해서 끌 수 없다
    - 곡을 연달아 담는다: 멜론 결과 행(오른쪽에 ＋ / 받는 중 / 담음 / 콘티에 있음)을 누르면 콘티 끝에 `loading: true` 세션으로 자리를 먼저 잡고(`addLoading`, 콘티 패널에 '가사 받는 중…') 가사를 받는다. 요청은 `Main` `detailRequests`(token → 곡)로 곡마다 따로 관리하고, 받으면 `fillLoading`이 `newEntry`로 채운다. 실패하면 자리를 빼고(`dropLoading`) 오류 창('다시 시도'·'직접 입력으로 열기'). 받는 중인 곡은 `setlistGroups`·PPT 생성·프리셋 저장에서 건너뛰고, 있으면 PPT 생성을 꺼 둔다(`anyLoading`). 전에 편집한 곡은 이어서 편집
    - 직접 입력 탭: `ManualForm.submitted(info, text)` → `Main.addManual`(song_id가 없으면 `manualId()`, `manual: true`) → `EditorPage.addManual`(늘 `newEntry`로 정리·2줄 나누기 — 끄는 옵션·입력칸 안내는 두지 않음(헷갈려서). 이미 편집하던 곡이면 `loadPreset`처럼 바꾸기) 후 입력칸을 비운다. 멜론 결과 없음·검색 실패(`SearchPanel.requestManual`)와 가사 불러오기 실패 오류 창의 '직접 입력으로 열기'는 이 탭을 열어 제목(검색어)·song_id·album과 안내 문구(`notice`)를 미리 채운다(`prefill`)
    - 서랍이 열려 있는 동안 담은 곡은 콘티에 쌓이기만 하고 편집기는 그대로(`addSong`·`loadPreset`·`addManual`의 open, 기본은 서랍이 닫혀 있을 때만 엶). 서랍을 닫으면 이번에 처음 담은 곡을 연다(`drawerAdded`, 아직 받는 중이면 다 받은 뒤 `pendingOpenId`). 담은 곡이 없으면 지금 곡 그대로
  - PPT 생성은 콘티 전체를 한 파일로(`writePpt` → `backend.generatePpt([{title, artist, chunks}])` → `ppt_engine.setlist_chunks`가 처음·곡 사이·끝에 가사 상자를 비운 검은 빈 슬라이드를 넣음, 곡이 하나여도 같음, 슬라이드 없는 곡은 건너뜀).
  - 앞·뒤에 붙일 PPT: 콘티 패널의 곡 목록 위('앞에 붙일 PPT')·아래('뒤에 붙일 PPT')의 `AttachList.qml`에 .pptx를 끌어다 놓거나 ＋로 골라 넣는다(여러 개, 끌어서 순서, 휴지통으로 빼기 — 되돌리기 토스트, 키보드 Delete·Alt+↑↓). 항목은 원본 파일 경로(PPT를 만들 때마다 새로 읽음) 또는 보관한 PPT `{saved: id}`이고 `state.json` `attachments`({before, after})에 기억한다(`Backend.setAttachments`, `clean_attach_lists`). 패널 이름은 '예배 PPT'(폭 280). 위에 '양식' 두 칸(`AttachList.qml` 카드: '찬양 전' = before, '찬양 후' = after, 파일 줄 30px · '＋ 양식 추가'), 그 아래 '찬양' 구역 제목을 지나는 화살표(찬양 전 칸에서 내려와 제목 오른쪽으로 나가 찬양 후 칸으로 올라감, Canvas), 아래에 같은 카드 모양의 곡 카드(곡 줄 40px · '＋ 곡 추가', 곡 수만큼만 차지하고 넘치면 목록만 스크롤). 넣기 칸은 모두 `AddRow.qml`(마우스·끌어다 놓기 중 초록). 줄 오른쪽 보관함 아이콘(`library`, 저장한 곡 탭과 같은 표시)으로 보관(보관한 것은 초록 아이콘이 늘 보이고 아닌 것은 마우스를 올렸을 때만, 화면 문구는 '보관', '저장'은 프리셋·PPT 저장과 헷갈려 쓰지 않음): 보관하면(`keepAttachment`) 파일을 앱 데이터 폴더에 복사하고 그 자리를 보관본으로 바꾼다 — 보관한 때 그대로 쓰고(원본을 고쳐도 따라가지 않음), 같은 이름을 다시 보관하면 그 보관본을 바꾼다. 끄면(`unkeepAttachment`, 확인창으로 한 번 더 물음) 원본 경로(`source`)로 되돌리고 보관본을 지운다(원본이 없으면 끌 수 없음, `hasSource`). 보관한 PPT는 '양식 추가' 칸 메뉴의 '보관한 PPT'에서 다시 넣고(이미 그 목록에 있으면 흐리게 '앞에 있음'), 지우기는 메뉴의 '보관한 PPT 관리…' 창(`SavedPptDialog.qml`, 휴지통 → 확인창, 지우면 양식에서도 빠짐). 보관한 PPT가 없으면 '양식 추가'는 바로 파일 대화상자. 보관하지 않은 파일을 `STALE_DAYS`(6)일 넘게 고치지 않았으면 ⚠로 표시(툴팁에 고친 날, 생성은 막지 않음). 목록 정보(장 수·문제)는 `describe_attachments`가 `ppt_merge.deck_info`(presentation.xml만 읽음)로 만들고, 앱으로 돌아올 때·생성 전에 다시 읽는다(`refreshAttachments`). 찾을 수 없거나 열 수 없는 파일이 있으면 생성을 막고 알린다. 붙일 PPT에 덮어써 저장하는 것도 막는다. 처음·끝 검은 빈 슬라이드는 그대로 둔다(앞 PPT → 빈 → 가사 … → 빈 → 뒤 PPT). 기본 파일 이름(`editor.js` `deckTitle`): 곡 하나 '제목 — 가수', 여럿 'YYYY-MM-DD 예배 가사'. 생성 전 3줄 확인은 콘티 전체를 보고(곡이 여럿이면 곡 제목을 붙임), 다른 곡을 나누면 그 곡의 히스토리에 남긴다(`rewriteStored`)
  - 프리셋(화면 문구는 '프리셋', '구성'이라고 쓰지 않음): 편집 화면 아래 `프리셋` 묶음(`presetGroup`: 불러오기 | 저장)의 `저장`(⌘S/Ctrl+S, `EditorPage.savePresets`)이 이름을 묻고(`PresetSaveDialog`, 기본값 'M월 D일', 한 번에 저장하는 곡 모두에 같은 이름) 콘티 곡마다 지금 텍스트(`E.serialize`)를 `Backend.savePresets`로 저장한다(PPT 생성과 따로, `dirty`와 무관). 곡마다 최근 10개, 같은 텍스트면 이름·시각만 갱신. 앨범아트는 저장하지 않는다. 이름 없는 프리셋(v1.4-beta.1)은 저장 날짜로 보인다
    - 멜론 곡: 검색 결과 행의 `프리셋 N` 배지(키보드는 목록에서 →) → 보관함 탭에 그 곡만(`filterSong`, '모든 프리셋'으로 전체. 탭을 직접 누르면 비움). 행을 누르면 멜론 가사
    - 직접 입력한 곡: song_id가 `manual-<시각·난수>`로 실행이 바뀌어도 고유하다(`Main.manualId`). 검색하면 `presets.search_manual`(제목·가수 또는 가사, 공백·대소문자 무시, 곡마다 최근 프리셋 기준)로 찾아 멜론 결과 위에 붙인다(`SearchPanel` `localCount`, '더 보기'·건수는 멜론 결과만으로). 행을 누르면 보관함 탭에서 그 곡의 프리셋. 멜론 검색이 실패해도 직접 입력 곡 결과는 보이고 머리글에 알린다(`melonError`)
    - 보관함(서랍의 `보관함` 탭, `PresetLibrary.qml`): 곡마다 카드 하나(앨범아트·제목·가수). 곡은 가나다순(한글 → 영문 → 숫자 등, `compareSongs`), 곡 안의 프리셋은 최근 저장한 것부터. 프리셋은 한 줄씩(이름·날짜, 이름 없으면 'M월 D일 저장'). 불러오기는 늘 보이고, 연필(이름 고치기, Enter 저장·Esc 취소)·휴지통(두 번 눌러 삭제)은 줄에 마우스를 올리거나 키보드로 왔을 때만 보인다. 슬라이드는 줄을 눌러 펼쳐야 슬라이드 번호와 가사 줄 목록으로 보인다(PPT 모양은 그리지 않음, 한 번에 하나, 높이 `previewHeight`까지이고 넘으면 그 안에서 스크롤, 펼치면 잘리지 않게 목록을 내림). 찾기는 곡 제목·가수가 맞으면 그 곡의 프리셋 모두, 프리셋 이름만 맞으면 그 프리셋만. 편집 중인 곡이 맨 위에 '편집 중'(`currentId`). 콘티 곡의 지금 가사와 같은 프리셋(`appliedTexts`: 서랍이 열려 있는 동안 `EditorPage`가 곡마다 넘김, 편집기에 열린 곡은 화면의 가사)은 줄을 연한 초록으로 칠하고 '이걸로 바꾸기' 대신 '✓ 적용 중'을 보인다. 편집 화면 아래 `불러오기`도 서랍을 보관함 탭으로 연다. 프리셋이 바뀌면(`presetsChanged`) 다시 읽는다
      - `PresetLibrary` 속성: `setlist`(콘티 곡 → '콘티 N번' 배지, 버튼 ＋ 대신 '이걸로 바꾸기')·`filterSong`(그 곡만)·`currentId`, 시그널 `addRequested`(＋)/`replaceRequested`('이걸로 바꾸기')(song, preset) — 서랍은 둘 다 `presetChosen`으로 내보내고 `loadPreset`이 콘티에 있는지·편집하던 곡인지로 나눈다, `refresh()`·`focusFilter()`
    - 앨범아트: 저장할 때 이번 실행에서 받은 곡 상세가 있으면 그림 주소(`image_url`)를 프리셋에 남기고, 보관함은 `Backend.loadArtFrom`으로 그림만 받는다(멜론 요청은 곡당 그림 1번, 없거나 실패하면 상세 페이지 1번 더 — 검색 결과 썸네일과 같은 수준). 보이는 카드만 만들어지므로 보이는 곡만 받는다
    - 불러오기 → `Main.openPreset` → `EditorPage.loadPreset`: 새 곡은 텍스트 그대로 세션을 만들어 콘티 끝에 더하고(`presetEntry`, 정리·2줄 자동 나누기 없음, 3줄 이상 슬라이드는 다시 묻지 않음), 이미 편집하던 곡은 히스토리에 남기고 바꾼다(지금 곡이면 되돌리기 토스트, 다른 곡이면 `rewriteStored` — 그 곡에서 되돌림). 서랍이 열려 있으면 편집기는 그대로
  - 마지막 PPT 생성 이후 바뀐 내용(`dirty`, 곡마다)이 있으면 창 닫기·업데이트 때(뺀 곡 포함, `anyDirty`) 확인
- 줄 드래그 규칙(`editor.js` `resolveDrop`/`planDrop`): 첫 줄은 앞 슬라이드 끝·앞쪽 새 슬라이드, 마지막 줄은 뒤 슬라이드 처음·뒤쪽 새 슬라이드로만 (꺼짐 상태에선 3줄이 돼도 그대로). "2줄 유지"(`keepTwo`, 기본 켜짐)를 켜면 2줄을 넘은 슬라이드는 같은 방향으로 연쇄 밀기(맨 앞/뒤는 새 슬라이드). 줄이 빠진 슬라이드는 채우지 않고 1줄로 남는다(당기기 연쇄 없음). 합치기·입력칸은 줄 수 제한 없음. 단 2줄 유지 중이면 3줄 이상이 생길 때 확인(`ConfirmDialog`, `editor.js` `longSlides`/`splitAsked`): 합치기는 실행 전, 입력은 입력칸 포커스가 빠질 때(창 전환·페이지 전환·PPT 생성 버튼 누름은 제외)와 PPT 생성 전에 한 번 — 생성은 답을 받은 뒤 저장 대화상자를 연다. '그대로 두기'한 슬라이드와 확인하고 합친 슬라이드는 다시 묻지 않고, '2줄씩 나누기'는 물어본 슬라이드만 나눈다. `ConfirmDialog`는 떠 있는 동안 들어온 질문을 덮어쓰지 않고 차례로 보여 준다

**리소스** (`assets/`): Pretendard 폰트(템플릿 폰트와 동일), SVG 아이콘.

**백엔드** (`src/utils/`):
- `melon_api.py` — `MelonScraper` 클래스가 멜론에서 노래 검색 결과와 가사/앨범아트를 스크래핑. 요청은 `MelonScraper`, HTML 해석은 순수 함수 `parse_search(html)`/`parse_detail(html)`로 나뉘어 있다. BeautifulSoup + 정규식 사용. 멜론 HTML 구조 변경 시 깨질 수 있음.
  - 곡 검색은 받은 행을 모두 돌려주고(자르지 않음, 한 쪽 50행) 다음 쪽은 멜론 '다음' 링크(`pageObj.sendPage`)와 같은 요청(`startIndex`·`pageSize`+정렬 매개변수)으로 목록 조각만 받는다. 첫 쪽만 `serch_totcnt`에 총 건수가 있다(멜론은 1,000건까지). 가사 검색(`/search/lyric/index.htm`, 한 쪽 15행)은 `parse_lyric_search`가 `dl.cntt_lyric`에서 곡 번호(`a.btn_icon_detail[data-song-no]`)·일치한 가사 일부(`snippet`, 일치 구절만 `<b>`인 이스케이프된 HTML)를 뽑는다. `Backend.searchPage(token, keyword, mode, start)`는 곡 검색 첫 쪽이 비면 가사 검색으로 자동 대체한다(`fallback`). 화면에는 검색 방식 토글이 없다: `SearchPanel`은 늘 곡 검색('song')으로 묻고, 결과가 0개일 때만 이 대체로 가사 결과가 나온다(직접 입력 곡도 대체됐을 때만 가사로 찾음, '더 보기'는 보이는 결과의 방식 `resultMode`로). `SearchPanel`은 목록을 `ListModel`에 이어 붙인다(배열을 통째로 바꾸면 '더 보기' 때 스크롤이 맨 위로 감)
- `ppt_merge.py` — 앞·뒤에 붙일 PPT를 가사 PPT에 끼워 넣는다(`attach_decks`, `PPTBuilder.generate_setlist_to_memory(before, after)`에서 호출). python-pptx에 슬라이드 복사가 없어 패키지 파트를 직접 복사한다: 슬라이드와 관계로 닿는 레이아웃·마스터·테마·그림·영상·차트 등을 원본 rId 그대로(파일마다 한 번씩), 노트는 대상의 노트 마스터로 잇고, 메모(댓글)는 뺀다. 복사한 마스터는 presentation.xml에 등록하고 마스터·레이아웃 id를 겹치지 않게 다시 매긴다. 구역·내장 글꼴 등 PPT 전체 설정은 가져오지 않는다. 슬라이드 크기는 처음 붙이는 PPT를 따르고 가사 PPT(마스터·레이아웃·슬라이드)를 같은 비율로 늘려 맞춘다(`fit_to_size`: 위치·크기·글자 크기·여백, 비율이 다르면 작은 쪽에 맞춰 가운데). 붙이는 PPT끼리 크기가 다르면 바꾸지 않고 화면에서 '슬라이드 크기가 달라요'로 알린다
- `ppt_engine.py` — `PPTBuilder` 클래스가 템플릿 PPTX를 로드하고, 슬라이드 구조를 딥카피하여 서식 유지, "가사" 플레이스홀더 텍스트를 교체, `BytesIO`로 메모리 내 슬라이드 생성.
- `line_fit.py` — PPT에서 가사 한 줄이 글상자 폭을 넘어 줄바꿈되는지 미리 계산(`LineFit.ratio`, 1 초과면 줄바꿈). 값은 코드에 두지 않고 템플릿 가사 글상자(`ppt_engine.find_lyrics_shape`, PPT 생성과 같은 글상자)에서 PowerPoint 상속 순서(런→문단→목록 스타일→레이아웃→마스터→텍스트 스타일→기본값, 테마 글꼴)대로 폭·안쪽 여백·글꼴·크기·굵게·자간·커닝 등을 읽는다. 폭은 PowerPoint 규칙 그대로(16.109 Mac에서 200줄로 확인): 글자별 설계 폭을 1/8pt로 반올림해 합산, 커닝은 글꼴에 예전 방식 `kern` 표가 있을 때만(GPOS 무시), 합 > 쓸 수 있는 폭이면 줄바꿈, `hangingPunct`면 줄 끝 문장부호 한 글자(`HANGING_PUNCT`)는 제외. 비율은 반올림하지 않는다(1/8pt만 넘어도 줄바꿈). 글꼴이 이 컴퓨터에 없으면 어림값(`exact=False`). 템플릿 내장 글꼴은 MTX 압축이라 쓰지 않음. 결과는 `SlideList`에 줄별 경고로 표시
- `helpers.py` — `resource_path()`가 프로젝트 루트(개발 모드·Nuitka 빌드 모두 이 파일 위치 기준) 아래 경로를 돌려준다.
- `version.py` — `get_version()`은 빌드 시 기록된 버전, 개발 모드에서는 "TEST". `parse_version()`/`is_newer()`로 릴리스 태그(v1.2.0, v1.2.0-beta.1, v1.1-beta) 비교.

**주요 패턴**:
- `src/`, `src/utils/`, `src/qml_ui/`에 빈 `__init__.py`가 있는 일반 패키지. 모듈은 `from src.utils.x import ...`로 불러온다(프로젝트 루트에서 실행). `sys.path` 주입 없음
- 프로젝트 루트의 `template.pptx`가 필수이며 실행 파일에 번들됨
- 라이선스: MIT(`LICENSE`). 빌드할 때 `scripts/third_party_notices.py`가 설치된 패키지(`requirements.txt`와 의존 패키지)에서 `THIRD_PARTY_NOTICES.txt`를 `build/`에 만들어 `LICENSE`와 함께 앱에 넣는다. 런타임 패키지를 추가·변경하면 고지가 자동으로 따라온다
- 메모리 내 PPT 생성(BytesIO), 임시 파일 미사용
- 앱 폴더 밖에 파일을 남기지 않는다: QML 디스크 캐시·GPU 파이프라인 캐시를 끈다(`app.py`). 설정 저장 등 새 기능을 넣을 때도 이 원칙을 지킨다(사용자 데이터는 아래 앱 데이터 폴더에만)
  - 예외로 허용한 앱 데이터 폴더(`src/utils/app_state.py` `data_dir`): Windows `%APPDATA%\LyricsSlideCreator`, macOS `~/Library/Application Support/LyricsSlideCreator`, 개발 모드는 프로젝트 안 `user_data/`(gitignore), `LSC_DATA_DIR`로 바꿀 수 있음(시험은 `tests/__init__.py`가 임시 폴더로). 앱 폴더는 업데이트 때 새로 깔려(Windows) 사용자 데이터를 둘 수 없어서다. Windows는 제거할 때 지운다(`windows.iss` `UninstallDelete`). 쓰기는 임시 파일 → `os.replace`(`write_json`), 쓸 수 없으면 무시
    - `state.json`: 튜토리얼을 봤는지(`tutorials_seen`), 창 크기·위치(`window`: 닫을 때 `app.py` `save_window`가 `Main.qml` `normalGeometry`(창 모드일 때만 갱신 = 최대화 전 크기)와 `lastMaximized`(닫으면 Hidden이 되므로 보이는 동안의 마지막 상태, 전체 화면 포함)를 기록, 열 때 `place_window`가 그 화면이 연결돼 있으면 작업 영역 안으로 넣어 연다. `--self-test`는 기록하지 않음). `Backend`가 시작할 때 한 번 읽어 메모리에 두므로 저장에 실패해도 그 실행에서는 튜토리얼이 다시 뜨지 않는다. v1.3.0까지 macOS 앱은 번들 ID 환경설정 plist에 썼다 — 처음 실행 때 `migrate_plist`가 옮기고 plist 키를 지운다(`BUNDLE_ID`는 `scripts/build.py`와 같게 유지)
    - `state.json`의 `attachments`: 앞·뒤에 붙일 PPT 경로 목록(위 '앞·뒤에 붙일 PPT')
    - `saved_ppts.json` + `saved_ppt/<id>.pptx`: 보관한 PPT(`src/utils/saved_ppts.py`)
    - `presets.json`: 저장한 프리셋(`src/utils/presets.py`) — 아래 '프리셋'
  - 첫 실행 튜토리얼(`Tour` `required`)은 닫기·Esc 없이 끝까지 보거나 '건너뛰기'로 끝낸다. 순서: 서랍이 처음 열리면 서랍 튜토리얼(`tutorials_seen` 키 'search' — 예전 검색 화면 튜토리얼의 기록을 그대로 씀) → 곡을 담고 서랍을 닫아 곡이 열리면 편집 화면 튜토리얼('editor'). 건너뛰면 모든 화면의 튜토리얼을 본 것으로 기록하고, 끝내거나 건너뛰면 "? 버튼으로 언제든 다시 볼 수 있어요" 토스트를 띄운다(`Main.qml` `finishTutorial`/`skipTutorial`)
  - 허용된 예외(OS가 남기는 기록): OS 기본 파일 대화상자의 마지막 폴더 기록(macOS `~/Library/Preferences/<앱>.plist`, Windows 레지스트리), macOS Metal 셰이더 캐시(`/var/folders/.../C/<앱>/com.apple.metal`)
- 화면 어디에도 슬라이드 장 수를 보이지 않는다(콘티 요약·곡·슬라이드 머리·앞뒤 PPT·프리셋·직접 입력 등, 사용자 결정). 줄바꿈 경고는 수 없이 '줄바꿈 있음'
- 사용자에게 보이는 문구(QML·backend.py·updater.py)는 해요체로 쓰고 제목에는 마침표를 붙이지 않는다. 용어는 '내 템플릿'·'PPT'로 통일
- 테스트: `tests/`(unittest). 프로젝트 루트에서 `python -m unittest discover -s tests -t .` (화면 없이 돌도록 `tests/__init__.py`가 `QT_QPA_PLATFORM=offscreen`을 설정하고 `QGuiApplication`을 만든다). 정적 검사는 `ruff check --select F401,E722 .`. 둘 다 PR·push 때 `.github/workflows/check.yml`이 돌린다(빌드는 하지 않음)
  - `test_editor_js.py`: `editor.js`에서 `.pragma library` 줄만 빼고 `QJSEngine`에 불러 시험(parseBlocks·serialize·regroup·resolveDrop·planDrop). 편집 규칙을 바꾸면 여기도 고칠 것
  - `test_melon_parse.py`: `melon_api.parse_search`/`parse_detail`을 `tests/fixtures/`의 HTML 조각으로 시험. 멜론 구조가 바뀌면 조각을 새로 떠서 갱신(개인정보 없는 최소 조각만)
  - `test_app_state.py`(데이터 폴더·plist 옮기기·창 위치), `test_presets.py`(프리셋 저장 규칙·직접 입력 곡 검색·백엔드)
  - 그 밖에 `test_version.py`, `test_line_fit.py`(기준 폭), `test_ppt_engine.py`(만든 PPT를 python-pptx로 다시 열어 확인)
  - `test_saved_ppts.py`: 보관(복사·같은 이름 바꾸기·지우기)과 목록의 보관본 해석
  - `test_ppt_merge.py`: 그림·차트·노트·링크·숨긴 슬라이드가 있는 PPT를 만들어 붙이고 순서·파트·마스터 id·크기 맞춤을 확인. 실제 PowerPoint에서 열리는지는 사람이 확인
  - Qt 글꼴·이미지 API를 쓰는 시험은 앱 객체가 먼저 있어야 한다. Python을 일부러 죽이는 시험은 쓰지 않는다
