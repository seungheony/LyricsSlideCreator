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
    title: "Lyrics Slide Creator"
    color: Theme.bg
    font.family: Theme.font

    // 기본 1100×800, 작은 화면에서는 작업 영역의 92%×90%까지 줄여 가운데에 둔다 (제목 표시줄·작업 표시줄 몫을 남김).
    // 최소 크기(900×560)도 같은 한도로 낮춰, 작은 화면에서 창이 작업 영역 밖으로 나가지 않게 한다.
    // 작업 영역(workArea)은 app.py가 창이 열릴 화면에서 읽어 넣는다 (QML의 Screen.desktopAvailable*은 모니터가 여럿이면 전체 합이라 쓰지 않음)
    // 지난번에 닫을 때의 크기·위치(savedGeometry, 그 화면이 지금도 연결돼 있을 때만)가 있으면 그대로 열되 작업 영역 안으로 넣는다
    property rect workArea: Qt.rect(0, 0, 0, 0)
    property rect savedGeometry: Qt.rect(0, 0, 0, 0)
    property bool savedMaximized: false
    function fitToScreen() {
        const a = workArea
        if (a.width > 0 && a.height > 0) {
            const maxW = Math.floor(a.width * 0.92), maxH = Math.floor(a.height * 0.90)
            minimumWidth = Math.min(900, maxW)
            minimumHeight = Math.min(560, maxH)
            const s = savedGeometry
            if (s.width > 0 && s.height > 0) {
                width = Math.max(minimumWidth, Math.min(s.width, a.width))
                height = Math.max(minimumHeight, Math.min(s.height, a.height))
                x = Math.max(a.x, Math.min(s.x, a.x + a.width - width))
                y = Math.max(a.y, Math.min(s.y, a.y + a.height - height))
            } else {
                width = Math.min(1100, maxW)
                height = Math.min(800, maxH)
                x = a.x + Math.floor((a.width - width) / 2)
                y = a.y + Math.floor((a.height - height) / 2)
            }
        }
        normalGeometry = Qt.rect(x, y, width, height)
        if (savedMaximized) showMaximized()
        else visible = true
    }

    // 최대화하지 않았을 때의 크기·위치와 최대화 여부 (닫을 때 app.py가 읽어 기록한다. 최대화 중이면 그 전 크기를 남긴다)
    // 닫으면 visibility가 Hidden이 되므로 최대화 여부는 보이는 동안의 마지막 상태로 둔다. 전체 화면(macOS)도 최대화로 다시 연다
    property rect normalGeometry: Qt.rect(0, 0, 0, 0)
    property bool lastMaximized: false
    function rememberGeometry() {
        if (visibility === Window.Windowed) normalGeometry = Qt.rect(x, y, width, height)
    }
    onVisibilityChanged: (v) => {
        if (v === Window.Maximized || v === Window.FullScreen) lastMaximized = true
        else if (v === Window.Windowed) lastMaximized = false
        Qt.callLater(rememberGeometry)
    }
    // 최대화할 때 크기가 먼저 바뀌고 visibility가 뒤따라오기도 해서, 한 박자 늦게 확인한다
    onXChanged: Qt.callLater(rememberGeometry)
    onYChanged: Qt.callLater(rememberGeometry)
    onWidthChanged: Qt.callLater(rememberGeometry)
    onHeightChanged: Qt.callLater(rememberGeometry)

    // 편집 화면이 늘 보이는 기본 화면이다. 곡은 '곡 추가'(⌘K/Ctrl+K)로 여는 곡 찾기 서랍(EditorPage.drawer)에서 연달아 담는다
    // 콘티와 곡별 편집 상태는 editorPage(sessions·setlist)가 세션 메모리에만 둔다 (앱을 닫으면 사라짐 → 닫을 때 확인)
    property bool closeConfirmed: false
    // 가사를 받는 중인 요청: token → song_id. 곡마다 따로 받아 여러 곡을 연달아 담을 수 있다
    property int detailToken: 0
    property var detailRequests: ({})

    // 멜론 검색 결과에서 곡을 눌렀을 때: 콘티 끝에 담는다. 전에 편집한 곡이면 이어서, 처음이면 자리를 먼저 잡고 가사를 받는다
    function openSong(song) {
        const id = song.song_id
        if (editorPage.setlist.indexOf(id) >= 0) {
            toast.show(editorPage.isLoading(id) ? "가사를 받는 중이에요" : "이미 콘티에 있는 곡이에요")
            return
        }
        if (editorPage.sessions[id] && !editorPage.isLoading(id)) {
            editorPage.addSong(song, null)
            return
        }
        editorPage.addLoading(song)
        const token = ++detailToken
        const next = Object.assign({}, detailRequests)
        next[token] = song
        detailRequests = next
        backend.songDetail(token, id)
    }

    // 멜론 없이 가사를 직접 입력해서 담는다 (서랍의 '직접 입력' 탭. 검색 결과 없음·검색 실패·가사를 불러오지 못했을 때도 이 탭으로).
    // info: { title, artist, album, song_id } — 멜론 곡에서 왔으면 song_id·앨범을 이어받는다 (앨범아트·같은 곡 이어서 편집)
    // 직접 입력한 곡의 song_id는 실행이 바뀌어도 겹치지 않게 만든다 (프리셋으로 저장하면 같은 곡으로 묶이고 검색 결과·보관함에서 다시 연다)
    function manualId() {
        return "manual-" + Date.now().toString(36) + Math.floor(Math.random() * 1679616).toString(36)
    }
    function addManual(info, text) {
        const song = {
            song_id: info.song_id || manualId(),
            title: info.title || "", artist: info.artist || "", album: info.album || "",
            manual: !info.song_id
        }
        editorPage.addManual(song, text)
    }

    // 프리셋 불러오기 (서랍의 보관함 탭): 저장할 때의 슬라이드 그대로 콘티에 담는다 (제목·가수도 저장할 때의 것).
    // 콘티에 있거나 전에 편집한 곡이면 그 곡의 히스토리에 남기고 가사를 바꾼다 (EditorPage.loadPreset)
    function openPreset(song, preset) {
        const s = Object.assign({}, song, { title: preset.title || song.title, artist: preset.artist || song.artist,
                                           manual: song.manual === true || preset.manual === true })
        if (!s.manual) backend.loadArtFrom(s.song_id, preset.image_url || "")
        editorPage.loadPreset(s, preset.text)
    }

    // 창 닫기: PPT로 만들지 않은 편집이 있으면 확인한다
    onClosing: (close) => {
        if (closeConfirmed) return
        editorPage.prepareEdit()
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
            const song = win.detailRequests[token]
            if (!song) return
            const next = Object.assign({}, win.detailRequests)
            delete next[token]
            win.detailRequests = next
            const det = JSON.parse(json)
            if (det.error) {
                // 자리를 뺀다. 그 사이 콘티에서 뺐거나 프리셋으로 채웠으면 알리지 않는다
                if (!editorPage.dropLoading(song.song_id)) return
                dialog.showError(det.error, det.detail, { text: "직접 입력으로 열기", handler: () => editorPage.openDrawer("manual", { manual: {
                                     title: song.title, artist: song.artist, album: song.album, song_id: song.song_id,
                                     notice: "멜론에서 '" + (song.title || "이 곡") + "' 가사를 불러오지 못했어요. 가사를 붙여 넣으면 이 곡으로 담아요" } }) },
                                 det.retry ? { handler: () => win.openSong(song) } : null)
                return
            }
            editorPage.fillLoading(song.song_id, det.lyrics)
        }
        // 업데이트 설치가 시작되면 확인 없이 닫는다 (편집 경고는 업데이트 확인창에서 이미 보여 줌)
        function onUpdateReady() { win.closeConfirmed = true }
    }

    EditorPage {
        id: editorPage
        objectName: "editorPage"
        anchors.top: updateBanner.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        toastHost: toast
        onFeedbackRequested: feedbackDialog.open()
        dialog: dialog
        tour: tour
        confirmDialog: confirmDialog
    }

    // 곡 찾기 서랍의 멜론 탭·보관함 탭·직접 입력 탭
    Connections {
        target: editorPage.drawer
        function onSongClicked(song) { win.openSong(song) }
        function onPresetChosen(song, preset) { win.openPreset(song, preset) }
        function onManualSubmitted(info, text) { win.addManual(info, text) }
    }

    // 버전 표시. 누르면 업데이트를 직접 확인한다 (알림을 닫았으면 다시 연다)
    Text {
        id: versionLabel
        anchors.top: updateBanner.bottom
        anchors.right: parent.right
        anchors.topMargin: 19    // 편집 화면 머리글(52) 가운데
        anchors.rightMargin: 20
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

    // '문의하기' 창: 편집 화면 아래 막대의 버튼(EditorPage feedbackRequested)으로 연다 (오류 창의 '문제 알리기'는 바로 GitHub를 연다)
    FeedbackDialog { id: feedbackDialog; objectName: "feedbackDialog" }

    ToastHost {
        id: toast
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 96
        z: 100
    }

    AppDialog { id: dialog; objectName: "errorDialog" }
    ConfirmDialog { id: confirmDialog; objectName: "confirmDialog" }

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

    // ── 첫 실행 튜토리얼 ── 끝까지 보거나 건너뛰면 다시 나오지 않는다 (기록: src/utils/app_state.py)
    // 곡 찾기 서랍 튜토리얼(기록 이름 'search': 예전 검색 화면 튜토리얼과 같은 기록)은 서랍이 처음 열렸을 때,
    // 편집 화면 튜토리얼('editor')은 곡을 담고 서랍을 닫아 처음 곡을 열었을 때 보여 준다. 건너뛰면 모두 본 것으로 기록한다
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
    function maybeDrawerTour() {
        if (editorPage.drawerOpen && !tour.opened && !backend.tutorialSeen("search")) drawerTourTimer.restart()
    }
    function maybeEditorTour() {
        if (editorPage.song && !editorPage.drawerOpen && !tour.opened && !backend.tutorialSeen("editor")) editorTourTimer.restart()
    }
    Connections {
        target: editorPage
        function onSongChanged() { win.maybeEditorTour() }
        function onDrawerOpenChanged() { win.maybeDrawerTour(); win.maybeEditorTour() }
    }
    // 서랍이 열리는 애니메이션이 끝난 뒤에 시작한다 (시작할 때 콘티가 비어 있으면 서랍이 저절로 열린다)
    Timer {
        id: drawerTourTimer
        interval: Theme.normal + 200
        onTriggered: {
            if (editorPage.drawerOpen && !tour.opened && !backend.tutorialSeen("search"))
                editorPage.drawer.showHelp({ required: true, onFinished: () => win.finishTutorial("search"), onSkipped: win.skipTutorial })
        }
    }
    // 서랍이 닫히는 애니메이션이 끝난 뒤에 시작해야 강조할 위치가 맞는다
    Timer {
        id: editorTourTimer
        interval: Theme.normal + 200
        onTriggered: {
            if (editorPage.song && !editorPage.drawerOpen && !tour.opened && !backend.tutorialSeen("editor"))
                editorPage.showFirstRunTour(() => win.finishTutorial("editor"), win.skipTutorial)
        }
    }

    // 시작 직후가 아니라 화면이 뜬 뒤에 조용히 확인
    Timer { interval: 1500; running: true; onTriggered: backend.checkForUpdate(false) }

    // ── 단축키 ──
    readonly property bool modalOpen: editorPage.presetSaveOpen || dialog.opened || updateDialog.opened || confirmDialog.visible || tour.opened
    Shortcut {
        sequences: [StandardKey.Undo]
        enabled: !editorPage.drawerOpen && !editorPage.dragging && !win.modalOpen
        onActivated: editorPage.undo()
    }
    Shortcut {
        sequences: [StandardKey.Redo]
        enabled: !editorPage.drawerOpen && !editorPage.dragging && !win.modalOpen
        onActivated: editorPage.redo()
    }
    Shortcut {
        sequences: [StandardKey.Save]
        enabled: editorPage.deckSize > 0 && !editorPage.dragging && !win.modalOpen
        onActivated: editorPage.savePresets()
    }
    Shortcut {
        sequences: ["Ctrl+Return", "Ctrl+Enter"]
        enabled: editorPage.deckSize > 0 && !editorPage.anyLoading && !editorPage.drawerOpen && !win.modalOpen
        onActivated: editorPage.generate()
    }
    // 곡 추가: 곡 찾기 서랍을 열고 검색칸에 포커스 (열려 있으면 검색칸으로)
    Shortcut {
        sequence: "Ctrl+K"
        enabled: !editorPage.dragging && !win.modalOpen
        onActivated: editorPage.openDrawer("melon")
    }
    Shortcut {
        sequence: "Escape"
        enabled: !win.modalOpen
        onActivated: {
            // 드래그 중이면 취소, 가사 입력 중이면 입력칸에서만 빠져나오고, 서랍이 열려 있으면 (보관함의 이름 고치기·삭제 확인을 먼저 취소하고) 닫는다
            if (editorPage.dragging) editorPage.cancelDrag()
            else if (editorPage.drawerOpen && editorPage.drawer.handleEscape()) return
            else if (editorPage.lyricsFocused) editorPage.blurLyrics()
            else if (editorPage.drawerOpen) editorPage.closeDrawer()
        }
    }
}
