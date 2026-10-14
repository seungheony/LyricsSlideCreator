import QtQuick
import QtQuick.Controls.Basic
import "."

ApplicationWindow {
    id: win
    width: 1100
    height: 800
    minimumWidth: 760
    minimumHeight: 560
    visible: true
    title: "가사 슬라이드 생성기"
    color: Theme.bg
    font.family: Theme.font

    property bool editorActive: false
    property var pendingSong: null
    property int detailToken: 0
    // 곡별 편집 상태 (song_id → { song, state }). 같은 곡을 다시 열면 이어서 편집한다.
    // 세션 메모리에만 두고 파일로 남기지 않는다 (앱을 닫으면 사라짐 → 닫을 때 확인)
    property var sessions: ({})
    property var lastSession: null      // 검색 화면의 '이어서 편집' 칩
    property bool closeConfirmed: false
    // 편집 화면 밖에 보관된 곡 중 PPT로 만들지 않은 편집이 있는지
    readonly property bool storedDirty: {
        const cur = editorActive && editorPage.song ? editorPage.song.song_id : ""
        return Object.keys(sessions).some(id => id !== cur && sessions[id].state.dirty)
    }

    // 곡 열기. 불러오는 중에 다른 곡을 누르면 마지막에 누른 곡을 연다 (늦게 온 응답은 detailToken으로 버림)
    function openSong(song) {
        if (pendingSong && pendingSong.song_id === song.song_id) return
        cancelOpen()
        const saved = sessions[song.song_id]
        if (saved) {
            enterEditor(() => editorPage.resume(song, saved.state))
            return
        }
        pendingSong = song
        searchPage.loadingId = song.song_id
        backend.songDetail(detailToken, song.song_id)
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

    // 편집 화면을 떠나며 지금 상태를 보관한다
    function leaveEditor() {
        const song = editorPage.song
        if (song) {
            const next = Object.assign({}, sessions)
            next[song.song_id] = { song: song, state: editorPage.saveState() }
            sessions = next
            lastSession = next[song.song_id]
        }
        editorPage.dismissUndoToast()    // 검색 화면에서 편집기의 되돌리기가 눌리지 않도록
        editorActive = false
        searchPage.focusSearch()
    }

    // 뒤로·Esc: PPT로 만들지 않은 편집이 있으면 한 번 확인한다 (편집 내용은 보관돼 다시 열면 이어서 편집)
    function requestBack() {
        editorPage.prepareEdit()
        if (!editorPage.dirty) {
            leaveEditor()
            return
        }
        confirmDialog.ask({
            title: "아직 PPT로 만들지 않았어요",
            message: "편집한 내용은 앱을 닫기 전까지 남아 있어서, 이 곡을 다시 열면 이어서 편집할 수 있어요. 검색 화면으로 갈까요?",
            confirmText: "검색으로",
            cancelText: "계속 편집",
            onConfirm: () => win.leaveEditor()
        })
    }

    // 창 닫기: PPT로 만들지 않은 편집이 있으면 확인한다
    onClosing: (close) => {
        if (closeConfirmed) return
        if (editorActive) editorPage.prepareEdit()
        if (!(editorActive && editorPage.dirty) && !storedDirty) return
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
                dialog.showError(det.error, det.detail)
                return
            }
            win.enterEditor(() => editorPage.load(song, det.lyrics))
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
        anchors.fill: parent
        enabled: !win.editorActive
        opacity: win.editorActive ? 0 : 1
        transform: Translate { x: win.editorActive ? -24 : 0; Behavior on x { NumberAnimation { duration: Theme.normal; easing.type: Easing.OutCubic } } }
        Behavior on opacity { NumberAnimation { duration: Theme.normal; easing.type: Easing.OutCubic } }
        onSongClicked: (song) => win.openSong(song)
        tour: tour
    }

    EditorPage {
        id: editorPage
        anchors.fill: parent
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
    }

    // 검색 화면: 편집하던 곡으로 돌아가기
    Rectangle {
        id: resumeChip
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 24
        z: 50
        width: Math.min(chipRow.implicitWidth + 36, parent.width - 32)
        height: 40
        radius: 20
        color: chipArea.containsMouse ? Theme.primarySoft : Theme.surface
        border.width: 1
        border.color: chipArea.containsMouse ? Theme.primary : Theme.border
        opacity: !win.editorActive && win.lastSession && !searchPage.loadingId ? 1 : 0
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: Theme.normal } }
        Row {
            id: chipRow
            anchors.centerIn: parent
            spacing: 8
            Text { text: "편집 중"; color: Theme.text3; font.family: Theme.font; font.pixelSize: 13; anchors.verticalCenter: parent.verticalCenter }
            Text {
                text: win.lastSession ? win.lastSession.song.title + " — " + win.lastSession.song.artist : ""
                textFormat: Text.PlainText
                width: Math.min(implicitWidth, resumeChip.parent.width - 240)
                elide: Text.ElideRight
                color: Theme.text
                font.family: Theme.font
                font.pixelSize: 13
                font.weight: Font.DemiBold
                anchors.verticalCenter: parent.verticalCenter
            }
            Text { text: "· 이어서 편집"; color: Theme.primaryText; font.family: Theme.font; font.pixelSize: 13; font.weight: Font.Bold; anchors.verticalCenter: parent.verticalCenter }
        }
        MouseArea {
            id: chipArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: win.openSong(win.lastSession.song)
        }
    }

    Text {
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.margins: 10
        anchors.rightMargin: 14
        Component.onCompleted: text = "v" + backend.version()
        color: Theme.text3
        font.family: Theme.font
        font.pixelSize: 11
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
    UpdateBanner {
        id: updateBanner
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.topMargin: 30
        anchors.rightMargin: 16
        z: 90
        onUpdateClicked: { shown = false; updateDialog.openConfirm() }
        onNotesClicked: updateDialog.openNotes()
    }

    UpdateDialog {
        id: updateDialog
        editing: (win.editorActive && editorPage.dirty) || win.storedDirty
    }

    Connections {
        target: backend
        function onUpdateAvailable(json) {
            const info = JSON.parse(json)
            updateBanner.version = info.version
            updateDialog.version = info.version
            updateDialog.notes = info.notes
            updateDialog.page = info.page
            updateBanner.shown = true
        }
    }

    // ── 첫 실행 튜토리얼 ── 화면마다 처음 들어갈 때 한 번씩, 끝까지 봐야 넘어간다 (기록: src/utils/app_state.py)
    // 페이지 전환 애니메이션이 끝난 뒤에 시작해야 강조할 위치가 맞는다
    Timer {
        interval: 600
        Component.onCompleted: if (!backend.tutorialSeen("search")) start()
        onTriggered: searchPage.showHelp({ required: true, onFinished: () => backend.markTutorialSeen("search") })
    }
    Timer { id: editorTourTimer; interval: Theme.normal + 200; onTriggered: editorPage.showFirstRunTour() }

    // 시작 직후가 아니라 화면이 뜬 뒤에 조용히 확인
    Timer { interval: 1500; running: true; onTriggered: backend.checkForUpdate() }

    // ── 단축키 ──
    Shortcut {
        sequences: [StandardKey.Undo]
        enabled: win.editorActive && !editorPage.dragging && !dialog.opened && !updateDialog.opened && !confirmDialog.visible && !tour.opened
        onActivated: editorPage.undo()
    }
    Shortcut {
        sequences: [StandardKey.Redo]
        enabled: win.editorActive && !editorPage.dragging && !dialog.opened && !updateDialog.opened && !confirmDialog.visible && !tour.opened
        onActivated: editorPage.redo()
    }
    Shortcut {
        sequences: ["Ctrl+Return", "Ctrl+Enter"]
        enabled: win.editorActive && editorPage.blocks.length > 0 && !dialog.opened && !updateDialog.opened && !confirmDialog.visible && !tour.opened
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
}
