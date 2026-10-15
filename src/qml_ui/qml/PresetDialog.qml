import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import "."
import "editor.js" as E

// 저장한 곡 구성 고르기 (검색 결과의 '저장된 구성' 배지). 불러오면 그 구성 그대로 편집 화면이 열린다.
// openFor(song): song은 검색 결과의 곡 { song_id, title, artist, album }
Popup {
    id: dialog
    property var song: null
    property var presets: []
    property string deletingId: ""     // 삭제를 한 번 더 확인하는 중인 구성
    signal loadRequested(var song, var preset)

    function openFor(s) {
        song = s
        deletingId = ""
        refresh()
        if (presets.length) open()
    }

    function refresh() {
        presets = song ? JSON.parse(backend.presetsFor(song.song_id)) : []
        if (!presets.length) close()
    }

    function load(preset) {
        const s = song
        close()
        loadRequested(s, preset)
    }

    function remove(preset) {
        if (deletingId !== preset.id) { deletingId = preset.id; return }
        deletingId = ""
        backend.deletePreset(preset.id)
        refresh()
    }

    // '2026-10-15T14:03:00' → '2026년 10월 15일 오후 2:03'
    function dateText(iso) {
        const m = /^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2})/.exec(iso || "")
        if (!m) return ""
        const h = Number(m[4])
        return m[1] + "년 " + Number(m[2]) + "월 " + Number(m[3]) + "일 " + (h < 12 ? "오전 " : "오후 ")
               + ((h % 12) || 12) + ":" + m[5]
    }

    onAboutToShow: contentItem.forceActiveFocus()

    parent: Overlay.overlay
    anchors.centerIn: parent
    width: Math.min(480, parent.width - 32)
    height: Math.min(implicitHeight, parent.height - 64)
    modal: true
    focus: true
    padding: 24
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
    Overlay.modal: Rectangle { color: Qt.rgba(0, 0, 0, 0.4) }
    enter: Transition {
        NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 200 }
        NumberAnimation { property: "scale"; from: 0.96; to: 1; duration: 250; easing.type: Easing.OutCubic }
    }
    exit: Transition { NumberAnimation { property: "opacity"; to: 0; duration: 150 } }
    background: Rectangle { radius: 18; color: Theme.surface }

    contentItem: ColumnLayout {
        spacing: 6
        focus: true
        // Enter: 가장 최근 구성을 불러온다
        Keys.onReturnPressed: if (dialog.presets.length) dialog.load(dialog.presets[0])
        Keys.onEnterPressed: if (dialog.presets.length) dialog.load(dialog.presets[0])

        Text {
            Layout.fillWidth: true
            text: "저장된 구성"
            color: Theme.text
            font.family: Theme.font
            font.pixelSize: 17
            font.weight: Font.Bold
        }
        Text {
            Layout.fillWidth: true
            text: dialog.song ? [dialog.song.title, dialog.song.artist].filter(Boolean).join(" — ") : ""
            textFormat: Text.PlainText
            color: Theme.text3
            font.family: Theme.font
            font.pixelSize: 13
            elide: Text.ElideRight
        }
        Text {
            Layout.fillWidth: true
            Layout.bottomMargin: 8
            text: "불러오면 저장할 때의 슬라이드 구성 그대로 편집 화면이 열려요."
            color: Theme.text2
            font.family: Theme.font
            font.pixelSize: 13
            wrapMode: Text.Wrap
        }

        ListView {
            id: list
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.preferredHeight: contentHeight
            implicitHeight: contentHeight
            clip: true
            spacing: 8
            boundsBehavior: Flickable.StopAtBounds
            model: dialog.presets
            ScrollBar.vertical: ScrollBar {}

            delegate: Rectangle {
                id: item
                required property var modelData
                required property int index
                readonly property var groups: E.linesOf(E.parseBlocks(modelData.text))
                width: ListView.view.width
                height: itemRow.implicitHeight + 24
                radius: Theme.radiusSm
                color: Theme.surface2
                RowLayout {
                    id: itemRow
                    anchors.fill: parent
                    anchors.margins: 12
                    spacing: 10
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 4
                        Text {
                            Layout.fillWidth: true
                            text: dialog.dateText(item.modelData.saved_at) + " · " + item.groups.length + "장"
                                  + (item.index === 0 ? "  (최근)" : "")
                            color: Theme.text
                            font.family: Theme.font
                            font.pixelSize: 14
                            font.weight: Font.DemiBold
                        }
                        // 처음 두 슬라이드 미리보기 (슬라이드 사이는 /)
                        Text {
                            Layout.fillWidth: true
                            text: item.groups.slice(0, 2).map(lines => lines.join(" ")).join("  /  ")
                            textFormat: Text.PlainText
                            color: Theme.text3
                            font.family: Theme.font
                            font.pixelSize: 12
                            elide: Text.ElideRight
                        }
                    }
                    AppButton {
                        glyph: "trash"
                        text: dialog.deletingId === item.modelData.id ? "삭제" : ""
                        variant: dialog.deletingId === item.modelData.id ? "danger" : "ghost"
                        size: "small"
                        onClicked: dialog.remove(item.modelData)
                        Accessible.name: dialog.deletingId === item.modelData.id ? "삭제 확인" : "이 구성 삭제"
                        AppToolTip { visible: parent.hovered && dialog.deletingId !== item.modelData.id; delay: 400; text: "이 구성 삭제" }
                    }
                    AppButton {
                        text: "불러오기"
                        variant: "primary"
                        size: "small"
                        onClicked: dialog.load(item.modelData)
                    }
                }
            }
        }

        AppButton {
            Layout.alignment: Qt.AlignRight
            Layout.topMargin: 10
            text: "닫기"
            variant: "ghost"
            onClicked: dialog.close()
        }
    }
}
