import QtQuick
import QtQuick.Controls.Basic
import "."

ApplicationWindow {
    id: win
    width: 1100
    height: 800
    minimumWidth: 900
    minimumHeight: 560
    visible: false   // 크기를 정한 뒤(fitToScreen) 보인다
    title: "가사 슬라이드 생성기"
    color: Theme.bg
    font.family: Theme.font

    // 기본 1100×800, 작은 화면에서는 작업 영역의 92%×90%까지 줄여 가운데에 둔다 (제목 표시줄·작업 표시줄 몫을 남김).
    // 최소 크기(900×560)도 같은 한도로 낮춰, 작은 화면에서 창이 작업 영역 밖으로 나가지 않게 한다.
    // 작업 영역(workArea)은 app.py가 창이 열릴 화면에서 읽어 넣는다 (QML의 Screen.desktopAvailable*은 모니터가 여럿이면 전체 합이라 쓰지 않음)
    property rect workArea: Qt.rect(0, 0, 0, 0)
    function fitToScreen() {
        const a = workArea
        if (a.width > 0 && a.height > 0) {
            const maxW = Math.floor(a.width * 0.92), maxH = Math.floor(a.height * 0.90)
            minimumWidth = Math.min(900, maxW)
            minimumHeight = Math.min(560, maxH)
            width = Math.min(1100, maxW)
            height = Math.min(800, maxH)
            x = a.x + Math.floor((a.width - width) / 2)
            y = a.y + Math.floor((a.height - height) / 2)
        }
        visible = true
    }

    property bool editorActive: false
    property var pendingSong: null
    property bool pendingFresh: false   // 불러온 곡으로 새 콘티를 시작한다 (아니면 콘티에 더함)
    property int detailToken: 0
    // 콘티와 곡별 편집 상태는 editorPage(sessions·setlist)가 세션 메모리에만 둔다 (앱을 닫으면 사라짐 → 닫을 때 확인)
    property bool closeConfirmed: false
    // 편집 화면의 '곡 추가'로 검색 화면에 왔다: 고른 곡을 콘티에 더하고 편집 화면으로 돌아간다
    property bool addMode: false
    readonly property bool hasSetlist: editorPage.setlist.length > 0

    // 검색 결과에서 곡을 눌렀을 때. 콘티가 있으면 더할지 새로 시작할지 묻는다 ('곡 추가'로 왔거나 이미 콘티에 있는 곡이면 묻지 않음)
    function openSong(song) {
        if (pendingSong && pendingSong.song_id === song.song_id) return
        cancelOpen()
        chooseDestination(song, (fresh) => win.loadSong(song, fresh))
    }

    // 멜론 없이 가사를 직접 입력해서 연다 (가사 직접 입력, 가사를 불러오지 못했을 때, 검색 실패).
    // info: { title, artist, album, song_id } — 멜론 곡에서 왔으면 song_id·앨범을 이어받는다 (앨범아트·같은 곡 이어서 편집)
    property int manualSeq: 0
    function openManual(info) {
        cancelOpen()
        const song = {
            song_id: info.song_id || "manual-" + (++manualSeq),
            title: info.title || "", artist: info.artist || "", album: info.album || "",
            manual: !info.song_id
        }
        chooseDestination(song, (fresh) => win.placeSong(song, "", fresh))
    }

    // 고른 곡을 콘티에 더할지 새 콘티로 시작할지 정해 open(fresh)를 부른다
    function chooseDestination(song, open) {
        const list = editorPage.setlist
        if (addMode || !list.length || list.indexOf(song.song_id) >= 0) {
            open(false)
            return
        }
        confirmDialog.ask({
            title: "콘티에 더할까요?",
            message: "편집 중인 콘티(" + list.length + "곡)에 이 곡을 더할까요, 이 곡으로 새 콘티를 시작할까요?\n"
                     + "새로 시작해도 곡마다 편집한 가사는 앱을 닫기 전까지 남아 있어요.",
            confirmText: "콘티에 추가",
            cancelText: "새 콘티 시작",
            onConfirm: () => open(false),
            onCancel: () => open(true),
            onDismiss: null
        })
    }

    // 곡을 콘티에 더하거나(fresh: 새 콘티로) 편집 화면을 연다. 전에 편집한 곡이면 이어서, 처음이면 가사를 받아 온다
    // 불러오는 중에 다른 곡을 누르면 마지막에 누른 곡을 연다 (늦게 온 응답은 detailToken으로 버림)
    function loadSong(song, fresh) {
        if (editorPage.sessions[song.song_id]) {
            placeSong(song, null, fresh)
            return
        }
        pendingSong = song
        pendingFresh = fresh
        searchPage.loadingId = song.song_id
        backend.songDetail(detailToken, song.song_id)
    }

    function placeSong(song, lyricsText, fresh) {
        const adding = addMode
        addMode = false
        enterEditor(() => {
            if (fresh) editorPage.startSetlist(song, lyricsText)
            else if (!editorPage.addSong(song, lyricsText) && adding) toast.show("이미 콘티에 있는 곡이라 그 곡을 열었어요")
        })
    }

    // '곡 추가': 검색 화면으로 가서 고른 곡을 콘티에 더한다
    function startAddSong() {
        leaveEditor()
        addMode = true
    }

    // 곡 추가를 그만두고 편집 화면으로 돌아간다
    function cancelAddSong() {
        cancelOpen()
        addMode = false
        enterEditor(() => {})
    }

    // 진행 중인 곡 열기를 취소 (새 검색, 검색 화면의 Esc)
    function cancelOpen() {
        detailToken++
        pendingSong = null
        searchPage.loadingId = ""
    }

    function enterEditor(fill) {
        fill()
        editorActive = true
        if (!backend.tutorialSeen("editor")) editorTourTimer.start()
    }

    // 편집 화면을 떠나며 지금 곡의 상태를 보관한다 (콘티는 그대로 남아 '이어서 편집'으로 돌아온다)
    function leaveEditor() {
        editorPage.storeCurrent()
        editorPage.dismissUndoToast()    // 검색 화면에서 편집기의 되돌리기가 눌리지 않도록
        editorActive = false
        searchPage.focusSearch()
    }

    // 뒤로·Esc: PPT로 만들지 않은 편집이 있으면 한 번 확인한다 (편집 내용은 보관돼 다시 열면 이어서 편집)
    function requestBack() {
        editorPage.prepareEdit()
        if (!editorPage.setlistDirty) {
            leaveEditor()
            return
        }
        confirmDialog.ask({
            title: "아직 PPT로 만들지 않았어요",
            message: "편집한 콘티는 앱을 닫기 전까지 남아 있어서, 검색 화면 아래 '이어서 편집'으로 돌아올 수 있어요. 검색 화면으로 갈까요?",
            confirmText: "검색으로",
            cancelText: "계속 편집",
            onConfirm: () => win.leaveEditor()
        })
    }

    // 창 닫기: PPT로 만들지 않은 편집이 있으면 확인한다
    onClosing: (close) => {
        if (closeConfirmed) return
        if (editorActive) editorPage.prepareEdit()
        if (!editorPage.anyDirty) return
        close.accepted = false
        confirmDialog.ask({
            title: "PPT로 만들지 않은 편집이 있어요",
            message: "창을 닫으면 편집한 가사가 사라져요. 그래도 닫을까요?",
            confirmText: "닫기",
            cancelText: "취소",
            onConfirm: () => { win.closeConfirmed = true; win.close() }
        })
    }

    Connections {
        target: backend
        function onDetailFinished(token, json) {
            if (token !== win.detailToken || !win.pendingSong) return
            const song = win.pendingSong
            win.pendingSong = null
            searchPage.loadingId = ""
            const det = JSON.parse(json)
            if (det.error) {
                dialog.showError(det.error, det.detail, { text: "직접 입력으로 열기", handler: () => win.openManual(song) })
                return
            }
            win.placeSong(song, det.lyrics, win.pendingFresh)
        }
        // 업데이트 설치가 시작되면 확인 없이 닫는다 (편집 경고는 업데이트 확인창에서 이미 보여 줌)
        function onUpdateReady() { win.closeConfirmed = true }
    }

    // 새로 검색하면 진행 중인 곡 열기를 취소한다 (SearchPage.doSearch가 token을 올림)
    Connections {
        target: searchPage
        function onTokenChanged() { win.cancelOpen() }
    }

    // ── 페이지 (좌우로 살짝 밀리며 전환) ──
    SearchPage {
        id: searchPage
        bottomInset: resumeChip.visible ? resumeChip.height + 12 : 0
        anchors.top: updateBanner.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        enabled: !win.editorActive
        opacity: win.editorActive ? 0 : 1
        transform: Translate { x: win.editorActive ? -24 : 0; Behavior on x { NumberAnimation { duration: Theme.normal; easing.type: Easing.OutCubic } } }
        Behavior on opacity { NumberAnimation { duration: Theme.normal; easing.type: Easing.OutCubic } }
        onSongClicked: (song) => win.openSong(song)
        onManualRequested: (info) => win.openManual(info)
        tour: tour
    }

    EditorPage {
        id: editorPage
        objectName: "editorPage"
        anchors.top: updateBanner.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        enabled: win.editorActive
        visible: opacity > 0
        opacity: win.editorActive ? 1 : 0
        transform: Translate { x: win.editorActive ? 0 : 24; Behavior on x { NumberAnimation { duration: Theme.normal; easing.type: Easing.OutCubic } } }
        Behavior on opacity { NumberAnimation { duration: Theme.normal; easing.type: Easing.OutCubic } }
        toastHost: toast
        dialog: dialog
        tour: tour
        confirmDialog: confirmDialog
        onBackRequested: win.requestBack()
        onAddSongRequested: win.startAddSong()
    }

    // 검색 화면: 편집하던 콘티로 돌아가기. '곡 추가' 중에는 고를 곡을 안내하고 누르면 편집 화면으로 돌아간다
    Rectangle {
        id: resumeChip
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 24
        z: 50
        width: Math.min(chipRow.implicitWidth + 36, parent.width - 32)
        height: 40
        radius: 20
        // 올렸을 때도 뒤의 목록이 비치지 않도록 불투명한 색으로 섞는다
        color: chipArea.containsMouse || win.addMode ? Qt.tint(Theme.surface, Theme.primarySoft) : Theme.surface
        border.width: 1
        border.color: chipArea.containsMouse || win.addMode ? Theme.primary : Theme.border
        opacity: !win.editorActive && win.hasSetlist && !searchPage.loadingId ? 1 : 0
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: Theme.normal } }
        Row {
            id: chipRow
            anchors.centerIn: parent
            spacing: 8
            Text { text: win.addMode ? "곡 추가" : "편집 중"; color: Theme.text3; font.family: Theme.font; font.pixelSize: 13; anchors.verticalCenter: parent.verticalCenter }
            Text {
                text: win.addMode ? "콘티에 더할 곡을 골라 주세요" : win.setlistLabel()
                textFormat: Text.PlainText
                width: Math.min(implicitWidth, resumeChip.parent.width - 240)
                elide: Text.ElideRight
                color: Theme.text
                font.family: Theme.font
                font.pixelSize: 13
                font.weight: Font.DemiBold
                anchors.verticalCenter: parent.verticalCenter
            }
            Text { text: win.addMode ? "· 편집으로 돌아가기" : "· 이어서 편집"; color: Theme.primaryText; font.family: Theme.font; font.pixelSize: 13; font.weight: Font.Bold; anchors.verticalCenter: parent.verticalCenter }
        }
        MouseArea {
            id: chipArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: win.addMode ? win.cancelAddSong() : win.enterEditor(() => {})
        }
    }

    // '이어서 편집' 칩: 곡이 하나면 '제목 — 가수', 여럿이면 '콘티 N곡 · 첫 곡 외 N-1곡'
    function setlistLabel() {
        const list = editorPage.setlistEntries
        if (!list.length) return ""
        if (list.length === 1) return [list[0].title, list[0].artist].filter(Boolean).join(" — ")
        return "콘티 " + list.length + "곡 · " + list[0].title + " 외 " + (list.length - 1) + "곡"
    }

    // 버전 표시. 누르면 업데이트를 직접 확인한다 (알림을 닫았으면 다시 연다)
    Text {
        id: versionLabel
        anchors.top: updateBanner.bottom
        anchors.right: parent.right
        anchors.topMargin: 10
        anchors.rightMargin: 14
        z: 60
        property string version: ""
        Component.onCompleted: version = backend.version()
        text: win.updateChecking ? "업데이트 확인 중…"
            : "v" + version + (win.updateInfo && !updateBanner.shown ? " · 새 버전 있음" : "")
        color: versionArea.containsMouse || (win.updateInfo && !updateBanner.shown) ? Theme.primaryText : Theme.text3
        font.family: Theme.font
        font.pixelSize: 11
        font.underline: versionArea.containsMouse
        MouseArea {
            id: versionArea
            anchors.fill: parent
            anchors.margins: -6
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: win.checkUpdateManually()
        }
    }

    ToastHost {
        id: toast
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 96
        z: 100
    }

    AppDialog { id: dialog }
    ConfirmDialog { id: confirmDialog }

    Tour { id: tour }

    // ── 업데이트 ──
    property var updateInfo: null        // 새 버전 정보 (없으면 null)
    property bool updateChecking: false  // 버전 표시를 눌러 확인하는 중
    property var afterTour: []           // 튜토리얼이 끝난 뒤 보여 줄 것 (막대가 화면을 밀면 강조 위치가 어긋나므로)

    function whenTourClosed(fn) {
        if (tour.opened) afterTour = afterTour.concat([fn])
        else fn()
    }
    Connections {
        target: tour
        function onOpenedChanged() {
            if (tour.opened) return
            const queued = win.afterTour
            win.afterTour = []
            queued.forEach(fn => fn())
        }
    }

    // 미루거나(나중에·닫기) 실패해도 알림 막대를 다시 보여 준다. 막대의 ✕로 닫으면 버전 표시에 '새 버전 있음'이 남는다
    function showUpdateBanner() {
        if (!updateInfo) return
        whenTourClosed(() => { if (!updateDialog.opened) updateBanner.shown = true })
    }

    function checkUpdateManually() {
        if (updateInfo) {
            updateBanner.shown = false
            updateDialog.openConfirm()
            return
        }
        if (updateChecking) return
        updateChecking = true
        backend.checkForUpdate(true)
    }

    UpdateBanner {
        id: updateBanner
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        z: 90
        onUpdateClicked: { shown = false; updateDialog.openConfirm() }
        onNotesClicked: { shown = false; updateDialog.openNotes() }
        onDismissed: shown = false
    }

    UpdateDialog {
        id: updateDialog
        editing: editorPage.anyDirty
        onClosed: if (stage !== "installing") win.showUpdateBanner()
    }

    Connections {
        target: backend
        function onUpdateAvailable(json) {
            const info = JSON.parse(json)
            win.updateChecking = false
            win.updateInfo = info
            updateBanner.version = info.version
            updateDialog.version = info.version
            updateDialog.notes = info.notes
            updateDialog.page = info.page
            if (info.manual) {
                updateBanner.shown = false
                updateDialog.openConfirm()
            } else {
                win.showUpdateBanner()
            }
        }
        function onUpdateChecked(json) {
            win.updateChecking = false
            const r = JSON.parse(json)
            toast.show(r.message, { error: r.status === "error" })
        }
    }

    // 지난 업데이트 결과 (업데이트하고 다시 켜졌을 때 한 번)
    Timer {
        interval: 800
        running: true
        onTriggered: {
            const json = backend.lastUpdateResult()
            if (!json) return
            const r = JSON.parse(json)
            win.whenTourClosed(() => {
                if (r.ok) toast.show("v" + r.version + " 버전으로 업데이트했어요")
                else dialog.showError("업데이트를 마치지 못했어요\n이전 버전을 그대로 쓰고 있어요. 다시 시도하거나 릴리스 페이지에서 새 버전을 받아 직접 설치해 주세요.", r.detail)
            })
        }
    }

    // ── 첫 실행 튜토리얼 ── 화면마다 처음 들어갈 때 한 번씩, 끝까지 보거나 건너뛰면 다시 나오지 않는다 (기록: src/utils/app_state.py)
    // 건너뛰면 모든 화면의 튜토리얼을 본 것으로 기록한다
    readonly property string tutorialHint: "사용 방법은 화면 곳곳의 ? 버튼을 누르면 언제든 다시 볼 수 있어요"
    function finishTutorial(name) {
        backend.markTutorialSeen(name)
        toast.show(tutorialHint, { duration: 4500 })
    }
    function skipTutorial() {
        backend.markTutorialSeen("search")
        backend.markTutorialSeen("editor")
        toast.show(tutorialHint, { duration: 4500 })
    }
    // 페이지 전환 애니메이션이 끝난 뒤에 시작해야 강조할 위치가 맞는다
    Timer {
        interval: 600
        Component.onCompleted: if (!backend.tutorialSeen("search")) start()
        onTriggered: searchPage.showHelp({ required: true, onFinished: () => finishTutorial("search"), onSkipped: skipTutorial })
    }
    Timer { id: editorTourTimer; interval: Theme.normal + 200; onTriggered: editorPage.showFirstRunTour(() => finishTutorial("editor"), skipTutorial) }

    // 시작 직후가 아니라 화면이 뜬 뒤에 조용히 확인
    Timer { interval: 1500; running: true; onTriggered: backend.checkForUpdate(false) }

    // ── 단축키 ──
    Shortcut {
        sequences: [StandardKey.Undo]
        enabled: win.editorActive && !editorPage.dragging && !editorPage.headerFocused && !dialog.opened && !updateDialog.opened && !confirmDialog.visible && !tour.opened
        onActivated: editorPage.undo()
    }
    Shortcut {
        sequences: [StandardKey.Redo]
        enabled: win.editorActive && !editorPage.dragging && !editorPage.headerFocused && !dialog.opened && !updateDialog.opened && !confirmDialog.visible && !tour.opened
        onActivated: editorPage.redo()
    }
    Shortcut {
        sequences: ["Ctrl+Return", "Ctrl+Enter"]
        enabled: win.editorActive && editorPage.deckSize > 0 && !dialog.opened && !updateDialog.opened && !confirmDialog.visible && !tour.opened
        onActivated: editorPage.generate()
    }
    Shortcut {
        sequence: "Escape"
        enabled: win.editorActive && !dialog.opened && !updateDialog.opened && !confirmDialog.visible && !tour.opened
        onActivated: {
            // 드래그 중이면 취소, 가사 입력 중이면 입력칸에서만 빠져나오고, 아니면 검색 화면으로
            if (editorPage.dragging) editorPage.cancelDrag()
            else if (editorPage.lyricsFocused) editorPage.blurLyrics()
            else win.requestBack()
        }
    }
    Shortcut {
        sequence: "Escape"
        enabled: !win.editorActive && win.pendingSong !== null && !dialog.opened && !updateDialog.opened && !confirmDialog.visible && !tour.opened
        onActivated: win.cancelOpen()    // 불러오는 중인 곡 열기 취소
    }
    Shortcut {
        sequence: "Escape"
        enabled: !win.editorActive && win.addMode && win.pendingSong === null && !dialog.opened && !updateDialog.opened && !confirmDialog.visible && !tour.opened
        onActivated: win.cancelAddSong()    // 곡 추가를 그만두고 편집 화면으로
    }
}
