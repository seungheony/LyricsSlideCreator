# Lyrics Slide Creator

Lyrics Slide Creator는 Melon.com에서 노래 가사를 검색하고, 편집하여 PowerPoint 프레젠테이션 슬라이드로 자동 생성해주는 데스크톱 애플리케이션입니다. 교회, 학교, 행사 등에서 노래 가사를 효과적으로 전달해야 할 때 유용하게 활용할 수 있습니다.

## 주요 기능

*   **Melon.com 노래 검색**: 노래 제목 또는 가수 이름으로 검색하고 앨범아트와 함께 결과를 보여줍니다.
*   **가사 편집**: 빈 줄로 슬라이드를 나누는 가사 편집기와 실시간 슬라이드 미리보기. 미리보기에서 줄 사이를 눌러 나누기, 슬라이드 사이를 눌러 합치기, 줄을 끌어 옮기기, 되돌리기(⌘Z / Ctrl+Z)를 지원합니다.
*   **PowerPoint 생성**: 템플릿(`.pptx`) 서식을 그대로 유지한 채 가사 슬라이드를 만듭니다. 기본 템플릿과 앱 화면은 Pretendard 서체를 사용합니다.
*   **자동 업데이트**: 새 버전이 나오면 앱에서 알려주고, [업데이트] 버튼 하나로 받아서 설치·재시작합니다.
*   **깔끔한 설치/제거**: 앱은 설치 폴더(.app) 밖에 파일을 남기지 않으며, Windows에서는 제어판에서 제거하면 관련 파일이 모두 지워집니다.

## 설치 (사용자)

[Releases](https://github.com/seungheony/lyricsSlide_Creator/releases)에서 최신 버전을 받습니다.

*   **Windows**: `LyricsSlideCreator-<버전>-Setup.exe` 실행. 관리자 권한 없이 현재 사용자 계정에 설치됩니다. 제거는 `설정 → 앱` 또는 `제어판 → 프로그램 제거`에서 합니다.
    *   서명되지 않은 설치 파일이라 "Windows의 PC 보호" 창이 뜰 수 있습니다. **추가 정보 → 실행**을 누르면 설치됩니다.
*   **macOS (Apple Silicon, macOS 15 이상)**: `LyricsSlideCreator-<버전>-macOS.zip`을 풀고 `Lyrics Slide Creator.app`을 **응용 프로그램 폴더로 옮긴 뒤** 실행합니다. 제거는 앱을 휴지통으로 옮기면 됩니다.
    *   서명되지 않은 앱이라 처음 실행하면 "열 수 없습니다" 경고가 뜹니다. **시스템 설정 → 개인정보 보호 및 보안**으로 가서 아래쪽의 **그래도 열기**를 누른 뒤 다시 실행하세요. 한 번만 하면 됩니다. (macOS 15부터는 우클릭 → 열기로는 실행되지 않습니다.)
    *   응용 프로그램 폴더로 옮기지 않고 다운로드 폴더에서 바로 실행하면 자동 업데이트가 동작하지 않습니다.

### PowerPoint 서체

기본 템플릿(`template.pptx`)에는 Pretendard 서체가 포함되어 있어, 발표하는 PC에 Pretendard가 없어도 PowerPoint에서 서체가 유지됩니다. (Keynote, Google Slides, 오래된 PowerPoint는 포함된 서체를 쓰지 않으므로 그 PC에 Pretendard를 설치해야 합니다.)

다른 템플릿을 쓸 때 같은 효과를 내려면, 그 템플릿을 PowerPoint에서 열고 **글꼴 포함 → 모든 문자 포함**으로 저장하세요 (Windows: 파일 → 옵션 → 저장 / macOS: PowerPoint → 설정 → 저장). 서체는 `.ttf`로 설치되어 있어야 포함할 수 있습니다.

## 개발

### 1. 종속성 설치

Python 3.12 이상이 필요합니다.

```bash
python -m venv venv
# Windows: .\venv\Scripts\activate
source venv/bin/activate
pip install -r requirements.txt
```

### 2. 개발 모드 실행

```bash
python run.py
```

개발 모드에서는 버전이 `TEST`로 표시되고 업데이트 확인을 하지 않습니다. `python run.py --self-test`는 화면·폰트·템플릿이 모두 로드되는지 점검하고 종료 코드로 결과를 알려줍니다.

### 3. 배포 빌드

```bash
python scripts/build.py 1.2.0
```

*   **macOS**: `dist/Lyrics Slide Creator.app`, `dist/LyricsSlideCreator-1.2.0-macOS.zip`
*   **Windows**: `dist/LyricsSlideCreator-1.2.0-Setup.exe` ([Inno Setup 6](https://jrsoftware.org/isinfo.php) 필요)

Nuitka로 C 컴파일하므로 macOS는 Xcode Command Line Tools, Windows는 Visual Studio Build Tools(C++)가 필요합니다.

### 4. 릴리스

배포되는 파일을 직접 테스트한 뒤 공개하는 방식입니다. 테스트한 파일이 다시 빌드되지 않고 그대로 배포됩니다.

1. `develop` → `master` PR을 머지합니다.
2. master에서 버전 태그를 올립니다. 베타는 `v1.2.0-beta.1`처럼 `-`를 붙이면 프리릴리스가 됩니다.

    ```bash
    git checkout master && git pull
    git tag v1.2.0
    git push origin v1.2.0
    ```

3. GitHub Actions가 Windows/macOS 빌드 → 검증(Windows는 설치·실행·제거 후 남은 파일 확인) → **초안(Draft) 릴리스**를 만듭니다. 초안은 저장소 관리자에게만 보이며, 앱도 업데이트 대상으로 보지 않습니다.
4. [Releases](https://github.com/seungheony/lyricsSlide_Creator/releases)에서 초안의 파일을 받아 [릴리스 체크리스트](docs/RELEASE_CHECKLIST.md)대로 테스트합니다.
5. 문제가 없으면 초안에서 **Publish release**를 누릅니다. 이때부터 설치된 앱들이 업데이트 알림을 받습니다.

    문제가 있으면 초안과 태그를 지우고(`git push origin :v1.2.0`) 고친 뒤 다시 태그를 올립니다.

릴리스 노트는 직전 태그 이후 머지된 PR 제목으로 자동 생성되며(공개 전에 초안에서 고칠 수 있음), 앱의 업데이트 창에 그대로 표시됩니다. 정식 버전 사용자에게는 정식 릴리스만, 베타 사용자에게는 베타 릴리스도 알립니다. master·develop으로 가는 PR에서는 릴리스 없이 빌드·검증만 실행됩니다.

## 사용 방법

1.  **노래 검색**: 검색창에 노래 제목이나 가수를 입력하고 `검색`을 누릅니다.
2.  **노래 선택**: 결과에서 노래를 누르면 가사가 2줄씩 나뉘어 편집 화면이 열립니다.
3.  **가사 편집**: 왼쪽 가사 입력칸에서 빈 줄로 슬라이드를 나누거나, 오른쪽 미리보기에서 나누기·합치기·줄 옮기기·삭제를 합니다. `자동 나누기`로 1~3줄씩 다시 나눌 수 있습니다.
4.  **템플릿 선택**: 하단 `변경` 버튼으로 다른 PowerPoint 템플릿을 고를 수 있습니다. 템플릿에는 "가사"라는 글자가 들어간 텍스트 상자가 있어야 합니다.
5.  **PPT 생성**: `PPT 생성`(⌘Enter / Ctrl+Enter)을 눌러 저장합니다.

## 기술 스택

*   **PySide6 (Qt Quick / QML)**: 사용자 인터페이스
*   **requests, beautifulsoup4**: Melon.com 검색·가사 수집
*   **python-pptx**: PowerPoint 생성
*   **Nuitka, Inno Setup, GitHub Actions**: 빌드·설치 파일·자동 릴리스
