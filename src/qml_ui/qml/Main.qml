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
    title: "Lyrics Slide Creator"
    color: Theme.bg
    font.family: Theme.font

    property bool editorActive: false
    property var pendingSong: null
    property int detailToken: 0

    function openSong(song) {
        if (pendingSong) return
        pendingSong = song
        searchPage.loadingId = song.song_id
        detailToken++
        backend.songDetail(detailToken, song.song_id)
    }

    function showSearch() {
        editorActive = false
        searchPage.focusSearch()
    }

    Connections {
        target: backend
        function onDetailFinished(token, json) {
            if (token !== win.detailToken) return
            const song = win.pendingSong
            win.pendingSong = null
            searchPage.loadingId = ""
            const det = JSON.parse(json)
            if (det.error) {
                dialog.showError(det.error, det.detail)
                return
            }
            editorPage.load(song, det.lyrics)
            win.editorActive = true
        }
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
        onBackRequested: win.showSearch()
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
        editing: win.editorActive && editorPage.blocks.length > 0
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

    // 시작 직후가 아니라 화면이 뜬 뒤에 조용히 확인
    Timer { interval: 1500; running: true; onTriggered: backend.checkForUpdate() }

    // ── 단축키 ──
    Shortcut {
        sequences: [StandardKey.Undo]
        enabled: win.editorActive && !dialog.opened && !updateDialog.opened
        onActivated: editorPage.undo()
    }
    Shortcut {
        sequences: [StandardKey.Redo, "Ctrl+Shift+Z"]
        enabled: win.editorActive && !dialog.opened && !updateDialog.opened
        onActivated: editorPage.redo()
    }
    Shortcut {
        sequences: ["Ctrl+Return", "Ctrl+Enter"]
        enabled: win.editorActive && !dialog.opened && !updateDialog.opened
        onActivated: editorPage.generate()
    }
    Shortcut {
        sequence: "Escape"
        enabled: win.editorActive && !dialog.opened && !updateDialog.opened
        onActivated: {
            // 드래그 중이면 취소, 가사 입력 중이면 입력칸에서만 빠져나오고, 아니면 검색 화면으로
            if (editorPage.dragging) editorPage.cancelDrag()
            else if (editorPage.lyricsFocused) editorPage.blurLyrics()
            else win.showSearch()
        }
    }
}
