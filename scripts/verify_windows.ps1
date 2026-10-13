# Windows 설치 파일 검증 (GitHub Actions에서 실행)
#  1. 조용히 설치 → 2. 자체 점검(--self-test) → 3. 조용히 제거
#  4. 앱 폴더·바로가기·제거 등록 정보가 사라졌는지, 사용자 폴더에 앱 관련 파일이 남지 않았는지 확인
param([Parameter(Mandatory = $true)][string]$Version)
$ErrorActionPreference = 'Stop'

$setup = Join-Path $PSScriptRoot "..\dist\LyricsSlideCreator-$Version-Setup.exe"
$installDir = Join-Path $env:LOCALAPPDATA 'Programs\LyricsSlideCreator'
$exe = Join-Path $installDir 'LyricsSlideCreator.exe'
$uninstallKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\{99E90106-8A80-4B53-92E4-ADE0CCB80F0F}_is1'
$shortcut = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\가사 슬라이드 생성기.lnk'
$watched = @($env:LOCALAPPDATA, $env:APPDATA, $env:TEMP)
$appPattern = 'Lyrics|PySide|Nuitka|qmlcache|pipelinecache'

function Snapshot {
    $watched | ForEach-Object { Get-ChildItem $_ -Recurse -Depth 3 -Force -ErrorAction SilentlyContinue | ForEach-Object FullName }
}
function Fail($msg) { Write-Host "FAIL: $msg"; exit 1 }

$before = Snapshot

Write-Host '== 설치'
$p = Start-Process $setup -ArgumentList '/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART', '/NOLAUNCH' -Wait -PassThru
if ($p.ExitCode -ne 0) { Fail "설치 종료 코드 $($p.ExitCode)" }
if (-not (Test-Path $exe)) { Fail "설치 후 실행 파일이 없음: $exe" }
if (-not (Test-Path $uninstallKey)) { Fail '제어판 제거 목록에 등록되지 않음' }
if (-not (Test-Path $shortcut)) { Fail '시작 메뉴 바로가기가 없음' }
Write-Host ("설치 크기: {0:N1}MB" -f ((Get-ChildItem $installDir -Recurse | Measure-Object Length -Sum).Sum / 1MB))

Write-Host '== 자체 점검 (2회: 두 번째는 Windows 보안 검사 후 시작 시간 참고용)'
$env:QT_QPA_PLATFORM = 'offscreen'
# 앱은 콘솔 없이 빌드되어 오류 메시지가 보이지 않으므로, 출력을 파일로 받아 실패하면 보여준다.
# Qt 메시지는 stderr로(QT_FORCE_STDERR_LOGGING), 강제 종료(abort 등) 때는 Python 호출 위치도 남긴다(PYTHONFAULTHANDLER).
# 사용자 폴더 감시 대상이 아닌 빌드 폴더에 쓴다
$env:QT_FORCE_STDERR_LOGGING = '1'
$env:PYTHONFAULTHANDLER = '1'
$logDir = Join-Path $PSScriptRoot '..\build'
foreach ($i in 1..2) {
    $out = Join-Path $logDir "self-test-$i-stdout.txt"
    $err = Join-Path $logDir "self-test-$i-stderr.txt"
    $sw = [Diagnostics.Stopwatch]::StartNew()
    $p = Start-Process $exe -ArgumentList '--self-test' -Wait -PassThru -RedirectStandardOutput $out -RedirectStandardError $err
    $sw.Stop()
    # 자체 점검은 화면을 띄운 뒤 1.5초 기다렸다 종료한다
    Write-Host ("실행 {0}: 종료 코드 {1}, {2:N1}초 (그중 1.5초는 점검 대기)" -f $i, $p.ExitCode, $sw.Elapsed.TotalSeconds)
    if ($p.ExitCode -ne 0) {
        Write-Host '--- 앱 출력 (stdout)'; Get-Content $out -ErrorAction SilentlyContinue | Write-Host
        Write-Host '--- 앱 오류 (stderr)'; Get-Content $err -ErrorAction SilentlyContinue | Write-Host
        Fail "자체 점검 실패 (종료 코드 $($p.ExitCode))"
    }
}
Remove-Item Env:QT_QPA_PLATFORM, Env:QT_FORCE_STDERR_LOGGING, Env:PYTHONFAULTHANDLER

Write-Host '== 제거'
$uninstaller = Join-Path $installDir 'unins000.exe'
Start-Process $uninstaller -ArgumentList '/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART' -Wait
# 제거 프로그램은 임시 폴더에 자신을 복사해 실행하므로 끝날 때까지 기다린다
foreach ($i in 1..60) { if (-not (Test-Path $installDir)) { break }; Start-Sleep -Seconds 1 }

if (Test-Path $installDir) { Fail "제거 후 설치 폴더가 남음: $installDir" }
if (Test-Path $uninstallKey) { Fail '제거 후 제어판 등록 정보가 남음' }
if (Test-Path $shortcut) { Fail '제거 후 시작 메뉴 바로가기가 남음' }

Write-Host '== 남은 파일 확인'
# 제거 프로그램은 %TEMP%\is-XXXX-uninstall.tmp 에 자신을 복사해 실행하고, 끝난 뒤 그 사본을 스스로 지운다.
# 지워질 때까지 잠시 기다린 뒤 비교한다 (30초 안에 안 지워지면 남은 파일로 보고 실패)
$innoTemp = '\\is-[^\\]+\.tmp'
foreach ($i in 1..30) {
    $after = Snapshot
    $added = Compare-Object @($before) @($after) | Where-Object SideIndicator -eq '=>' | ForEach-Object InputObject
    if (-not ($added | Where-Object { $_ -match $innoTemp })) { break }
    Start-Sleep -Seconds 1
}
$leftovers = $added | Where-Object { $_ -match $appPattern -or $_ -match $innoTemp }
if ($leftovers) {
    $leftovers | ForEach-Object { Write-Host "  남음: $_" }
    Fail '제거 후 앱 관련 파일이 남음'
}
Write-Host "참고: 검사 중 새로 생긴 기타 파일 $(@($added).Count)개 (다른 프로세스·OS가 만든 것 포함)"
$added | Select-Object -First 30 | ForEach-Object { Write-Host "  $_" }
Write-Host 'PASS: 설치 → 실행 → 제거 후 앱 관련 파일 없음'
