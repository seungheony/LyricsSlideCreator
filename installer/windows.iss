; 가사 슬라이드 생성기 (Lyrics Slide Creator) — Windows 설치 파일 (Inno Setup 6)
; 한글 이름을 읽을 수 있도록 UTF-8(BOM)으로 저장한다
; scripts/build.py 가 /DAppVersion, /DAppNumericVersion, /DSourceDir, /DOutputDir 를 넘겨 컴파일한다.
;
; - 사용자 계정에만 설치 (관리자 권한 불필요): %LOCALAPPDATA%\Programs\LyricsSlideCreator
; - 제어판에서 제거하면 앱 관련 파일을 모두 지운다
; - 앱의 [업데이트] 버튼은 새 설치 파일을 /SILENT /SUPPRESSMSGBOXES 로 실행한다 (src/utils/updater.py, 진행 창만 보임)

#ifndef AppVersion
  #define AppVersion "0.0.0"
#endif
#ifndef AppNumericVersion
  #define AppNumericVersion "0.0.0.0"
#endif

; 화면에 보이는 이름. AppId·설치 폴더·실행 파일 이름은 업데이트와 연결되므로 바꾸지 않는다
#define AppName "가사 슬라이드 생성기"
#define AppExe "LyricsSlideCreator.exe"

[Setup]
; AppId는 절대 바꾸지 않는다 (바꾸면 업데이트가 아닌 별도 프로그램으로 설치됨)
AppId={{99E90106-8A80-4B53-92E4-ADE0CCB80F0F}
AppName={#AppName}
AppVersion={#AppVersion}
AppVerName={#AppName} {#AppVersion}
VersionInfoVersion={#AppNumericVersion}
AppPublisher=seungheony
AppPublisherURL=https://github.com/seungheony/LyricsSlideCreator
AppSupportURL=https://github.com/seungheony/LyricsSlideCreator/issues
AppUpdatesURL=https://github.com/seungheony/LyricsSlideCreator/releases
PrivilegesRequired=lowest
DefaultDirName={localappdata}\Programs\LyricsSlideCreator
DisableDirPage=yes
DisableProgramGroupPage=yes
OutputDir={#OutputDir}
OutputBaseFilename=LyricsSlideCreator-{#AppVersion}-Setup
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
UninstallDisplayName={#AppName}
UninstallDisplayIcon={app}\{#AppExe}
SetupIconFile=..\assets\app-icon\AppIcon.ico
CloseApplications=yes
RestartApplications=no
; 앱이 실행 중이면 설치·제거를 시작하기 전에 알린다. 앱이 만드는 뮤텍스 이름(src/utils/updater.py APP_MUTEX)과 같아야 한다.
; 자동 업데이트는 설치 파일을 실행하기 직전에 앱이 뮤텍스를 놓으므로 막히지 않는다
AppMutex=LyricsSlideCreator.AppMutex

[Languages]
Name: "korean"; MessagesFile: "compiler:Languages\Korean.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[InstallDelete]
; 업데이트할 때 이전 버전 파일이 섞이지 않도록 앱 폴더를 비우고 새로 설치한다
Type: filesandordirs; Name: "{app}\*"
; 영문 이름(Lyrics Slide Creator) 시절의 바로가기 (이름이 바뀌어 새 바로가기와 따로 남으므로 지운다)
Type: files; Name: "{autoprograms}\Lyrics Slide Creator.lnk"
Type: files; Name: "{autodesktop}\Lyrics Slide Creator.lnk"

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\{#AppName}"; Filename: "{app}\{#AppExe}"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#AppExe}"; Tasks: desktopicon

[Run]
; 설치 마지막 화면의 "실행" 체크박스. 자동 업데이트(/SILENT)에서는 묻지 않고 바로 다시 실행된다
; (CI 검증용 /NOLAUNCH 를 주면 실행하지 않음)
Filename: "{app}\{#AppExe}"; Description: "{cm:LaunchProgram,{#AppName}}"; Flags: nowait postinstall; Check: ShouldLaunch

[UninstallDelete]
; 설치 폴더 전체 (설치 후 생긴 파일 포함)
Type: filesandordirs; Name: "{app}"
; 업데이트 다운로드 임시 폴더
Type: filesandordirs; Name: "{%TEMP}\LyricsSlideCreator-update"
; 앱은 사용자 폴더에 캐시를 만들지 않지만(src/qml_ui/app.py), 혹시 남았을 경우를 대비해 함께 지운다
Type: filesandordirs; Name: "{localappdata}\Lyrics Slide Creator"
Type: filesandordirs; Name: "{localappdata}\LyricsSlideCreator"

[Code]
function ShouldLaunch: Boolean;
begin
  Result := Pos('/NOLAUNCH', UpperCase(GetCmdTail)) = 0;
end;

procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
var
  TempDir: String;
  ResultCode: Integer;
begin
  if CurUninstallStep = usDone then
  begin
    // 제거 프로그램은 %TEMP%\is-XXXX-uninstall.tmp 에 복사된 자신을 실행하므로 그 폴더를 스스로 지울 수 없다.
    // 제거가 끝나고 몇 초 뒤 폴더를 지우는 일을 별도 프로세스에 맡긴다 (자기 폴더일 때만).
    TempDir := ExtractFileDir(ParamStr(0));
    if Pos('-uninstall.tmp', Lowercase(TempDir)) > 0 then
      Exec(ExpandConstant('{cmd}'), '/c ping 127.0.0.1 -n 5 >nul & rmdir /s /q "' + TempDir + '"',
        ExpandConstant('{%TEMP}'), SW_HIDE, ewNoWait, ResultCode);
  end;
end;
