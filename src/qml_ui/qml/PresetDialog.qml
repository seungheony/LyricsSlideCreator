import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import "."

// 프리셋 고르기 창. 불러오면 그 프리셋의 슬라이드 그대로 편집 화면이 열린다. 내용은 PresetLibrary(보관함)를 그대로 쓴다.
//   openFor(song): 한 곡의 프리셋 (검색 결과의 '프리셋 N' 배지). song은 검색 결과의 곡 { song_id, title, artist, album, manual }
//   openLibrary(opts): 보관함 — 모든 곡의 프리셋, 곡 제목·가수·프리셋 이름으로 찾기.
//     opts.currentId: 편집 중인 곡(맨 위에 '편집 중'), opts.fromEditor: 편집 화면에서 열었다(불러오면 콘티에 바로 더함)
Popup {
    id: dialog
    property var song: null             // 한 곡 보기일 때의 곡 (보관함이면 null)
    readonly property bool library: song === null
    property string currentId: ""
    property bool fromEditor: false
    signal loadRequested(var song, var preset, bool fromEditor)

    function show() {
        lib.filterSong = song ? song.song_id : ""
        lib.currentId = currentId
        lib.reset()
        lib.refresh()
    }

    function openFor(s) {
        song = s
        currentId = ""
        fromEditor = false
        show()
        if (lib.songs.length) open()
    }

    function openLibrary(opts) {
        opts = opts || {}
        song = null
        currentId = opts.currentId || ""
        fromEditor = opts.fromEditor === true
        show()
        open()
    }

    // 한 곡 보기에서는 검색 결과의 곡 그대로 연다
    function load(s, preset) {
        const editor = fromEditor
        if (!dialog.library) s = song
        close()
        loadRequested(s, preset, editor)
    }

    onAboutToShow: dialog.library && lib.totalCount ? lib.focusFilter() : contentItem.forceActiveFocus()

    parent: Overlay.overlay
    anchors.centerIn: parent
    width: Math.min(600, parent.width - 32)
    // 내용에 맞추되, 찾는 동안 창이 출렁이지 않게 보관함은 최소 높이를 둔다
    height: Math.min(Math.max(implicitHeight, library ? 420 : 0), 720, parent.height - 64)
    modal: true
    focus: true
    padding: 0
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
    Overlay.modal: Rectangle { color: Qt.rgba(0, 0, 0, 0.4) }
    enter: Transition {
        NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 200 }
        NumberAnimation { property: "scale"; from: 0.96; to: 1; duration: 250; easing.type: Easing.OutCubic }
    }
    exit: Transition { NumberAnimation { property: "opacity"; to: 0; duration: 150 } }
    background: Rectangle { radius: 18; color: Theme.surface }

    contentItem: ColumnLayout {
        spacing: 0
        focus: true
        // Enter: 맨 위 곡의 맨 위 프리셋을 불러온다
        Keys.onReturnPressed: lib.loadFirst()
        Keys.onEnterPressed: lib.loadFirst()

        // ── 머리글: 제목·개수·닫기 ──
        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: 24
            Layout.rightMargin: 14
            Layout.topMargin: 18
            spacing: 8
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2
                Text {
                    text: dialog.library ? "보관함" : "프리셋"
                    color: Theme.text
                    font.family: Theme.font
                    font.pixelSize: 18
                    font.weight: Font.Bold
                }
                Text {
                    Layout.fillWidth: true
                    text: dialog.library
                          ? (lib.totalCount ? "곡 " + lib.songCount + "개 · 프리셋 " + lib.totalCount + "개" : "저장한 프리셋이 없어요")
                          : (dialog.song ? [dialog.song.title, dialog.song.artist].filter(Boolean).join(" — ") : "")
                    textFormat: Text.PlainText
                    color: Theme.text3
                    font.family: Theme.font
                    font.pixelSize: 13
                    elide: Text.ElideRight
                }
            }
            AppButton {
                Layout.alignment: Qt.AlignTop
                glyph: "x"
                variant: "ghost"
                onClicked: dialog.close()
                Accessible.name: "닫기"
                AppToolTip { visible: parent.hovered; delay: 600; text: "닫기 (Esc)" }
            }
        }

        PresetLibrary {
            id: lib
            Layout.fillWidth: true
            Layout.fillHeight: true
            loadLabel: "불러오기"
            onAddRequested: (s, preset) => dialog.load(s, preset)
            onReplaceRequested: (s, preset) => dialog.load(s, preset)
            // 한 곡 보기에서 마지막 프리셋을 지우면 닫는다
            onSongsChanged: if (dialog.opened && !dialog.library && !lib.songs.length) dialog.close()
        }

        // 편집 화면에서 열었을 때만: 불러오면 어떻게 되는지
        Text {
            visible: dialog.fromEditor && lib.songs.length > 0
            Layout.fillWidth: true
            Layout.leftMargin: 24
            Layout.rightMargin: 24
            Layout.bottomMargin: 16
            text: "불러오면 콘티에 더해요. 편집 중인 곡이면 가사를 그 프리셋으로 바꿔요(되돌릴 수 있어요)."
            color: Theme.text3
            font.family: Theme.font
            font.pixelSize: 12
            wrapMode: Text.Wrap
        }
    }
}
