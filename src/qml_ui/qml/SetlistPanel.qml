import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import "."

// 편집 화면 왼쪽의 콘티(곡 목록). 곡을 누르면 그 곡을 편집하고, 끌어서 순서를 바꾸고, 휴지통으로 뺀다.
// 목록은 EditorPage가 갖고 있고, 여기서는 신호로 알리기만 한다.
ColumnLayout {
    id: panel

    property var entries: []          // [{ id, title, artist, slides, wraps }] (콘티 순서)
    property string current: ""       // 편집 중인 곡
    property int deckSize: 0          // PPT 전체 장 수 (빈 슬라이드 포함)
    property alias addButton: addButton
    property alias listView: list

    signal selected(string id)
    signal removeRequested(int index)
    signal moveRequested(int from, int to)
    signal addRequested()
    signal helpRequested()

    // 누르거나 끄는 중 (EditorPage가 입력칸에서 벗어날 때의 3줄 확인을 미룬다)
    readonly property bool busy: pressedRow || dragFrom >= 0 || addButton.pressed

    // ── 끌어서 순서 바꾸기 ──
    property bool pressedRow: false
    property int dragFrom: -1         // 끄는 곡
    property real dragDy: 0           // 누른 곳에서 움직인 거리
    readonly property int rowHeight: 56
    readonly property int rowGap: 4
    readonly property int step: rowHeight + rowGap
    // 놓으면 들어갈 자리 (뺀 뒤 기준)
    readonly property int dropIndex: dragFrom < 0 ? -1
        : Math.max(0, Math.min(entries.length - 1, Math.round((dragFrom * step + dragDy) / step)))

    function endDrag(commit) {
        const from = dragFrom
        const to = dropIndex
        dragFrom = -1
        dragDy = 0
        pressedRow = false
        if (commit && from >= 0 && to !== from) moveRequested(from, to)
    }

    spacing: 10

    RowLayout {
        Layout.fillWidth: true
        Layout.preferredHeight: 34
        spacing: 6
        Text { text: "콘티"; color: Theme.text; font.family: Theme.font; font.pixelSize: 15; font.weight: Font.Bold }
        Rectangle {
            visible: panel.entries.length > 0
            width: songCount.implicitWidth + 16; height: 20; radius: 10
            color: Theme.surface2
            Text { id: songCount; anchors.centerIn: parent; text: panel.entries.length + "곡"; color: Theme.text2; font.family: Theme.font; font.pixelSize: 12; font.weight: Font.DemiBold }
        }
        HelpButton { onClicked: panel.helpRequested() }
        Item { Layout.fillWidth: true }
    }

    ListView {
        id: list
        Layout.fillWidth: true
        Layout.fillHeight: true
        model: panel.entries
        spacing: panel.rowGap
        clip: true
        interactive: panel.dragFrom < 0
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: ScrollBar {}

        // 놓을 자리 표시 (ListView 안의 항목은 내용 좌표로 놓인다)
        Rectangle {
            readonly property int gap: panel.dropIndex > panel.dragFrom ? panel.dropIndex + 1 : panel.dropIndex
            visible: panel.dragFrom >= 0 && panel.dropIndex !== panel.dragFrom
            z: 3
            x: 4
            width: list.width - 8
            height: 2
            radius: 1
            color: Theme.primary
            y: gap * panel.step - panel.rowGap / 2 - 1
        }

        delegate: Item {
            id: row
            required property int index
            required property var modelData
            readonly property bool isCurrent: modelData.id === panel.current
            readonly property bool dragged: panel.dragFrom === index
            width: ListView.view.width
            height: panel.rowHeight
            z: dragged ? 2 : 0

            Rectangle {
                id: card
                width: parent.width
                height: parent.height
                y: row.dragged ? panel.dragDy : 0
                radius: Theme.radiusSm
                color: row.isCurrent ? Theme.primarySoft : area.containsMouse || row.dragged ? Theme.surface : Theme.surfaceClear
                border.width: row.isCurrent || row.dragged ? 1 : 0
                border.color: row.isCurrent ? Theme.focusBorder : Theme.border
                opacity: row.dragged ? 0.9 : 1
                Behavior on color { ColorAnimation { duration: Theme.fast } }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 6
                    anchors.rightMargin: 6
                    spacing: 6
                    Icon {
                        glyph: "grip"
                        size: 14
                        color: Theme.text3
                        opacity: panel.entries.length > 1 && (area.containsMouse || row.dragged) ? 1 : 0.35
                    }
                    Text {
                        text: row.index + 1
                        color: row.isCurrent ? Theme.primaryText : Theme.text3
                        font.family: Theme.font
                        font.pixelSize: 12
                        font.weight: Font.Bold
                        Layout.preferredWidth: 14
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2
                        Text {
                            Layout.fillWidth: true
                            text: row.modelData.title
                            textFormat: Text.PlainText
                            color: Theme.text
                            font.family: Theme.font
                            font.pixelSize: 13
                            font.weight: row.isCurrent ? Font.Bold : Font.DemiBold
                            elide: Text.ElideRight
                        }
                        Row {
                            spacing: 4
                            Text {
                                text: row.modelData.slides + "장"
                                color: Theme.text3
                                font.family: Theme.font
                                font.pixelSize: 12
                            }
                            // 이 곡에 PPT에서 줄바꿈되는 슬라이드가 있으면
                            Text {
                                visible: row.modelData.wraps > 0
                                text: "· 줄바꿈 " + row.modelData.wraps + "장"
                                color: Theme.warning
                                font.family: Theme.font
                                font.pixelSize: 12
                            }
                        }
                    }
                    Item { Layout.preferredWidth: removeButton.visible ? removeButton.width : 0; Layout.preferredHeight: 1 }
                }

                MouseArea {
                    id: area
                    anchors.fill: parent
                    hoverEnabled: true
                    preventStealing: true
                    cursorShape: panel.dragFrom >= 0 ? Qt.ClosedHandCursor : Qt.PointingHandCursor
                    property real pressY: 0
                    onPressed: (mouse) => { pressY = mouse.y; panel.pressedRow = true }
                    onPositionChanged: (mouse) => {
                        if (!pressed) return
                        const dy = mouse.y - pressY + (row.dragged ? panel.dragDy : 0)
                        if (panel.dragFrom < 0 && Math.abs(mouse.y - pressY) > 6 && panel.entries.length > 1) panel.dragFrom = row.index
                        // card가 따라 움직이므로 card 안의 좌표는 그대로 → 움직인 거리를 더해 간다
                        if (row.dragged) panel.dragDy = Math.max(-row.index * panel.step,
                            Math.min((panel.entries.length - 1 - row.index) * panel.step, dy))
                    }
                    onReleased: {
                        if (panel.dragFrom >= 0) panel.endDrag(true)
                        else { panel.pressedRow = false; panel.selected(row.modelData.id) }
                    }
                    onCanceled: panel.endDrag(false)
                }

                // 콘티에서 빼기 (곡이 하나뿐이면 뺄 수 없다)
                AppButton {
                    id: removeButton
                    anchors.right: parent.right
                    anchors.rightMargin: 4
                    anchors.verticalCenter: parent.verticalCenter
                    visible: panel.entries.length > 1 && panel.dragFrom < 0 && (area.containsMouse || hovered)
                    glyph: "trash"
                    variant: "ghost"
                    size: "small"
                    onClicked: panel.removeRequested(row.index)
                    ToolTip.visible: hovered
                    ToolTip.delay: 500
                    ToolTip.text: "콘티에서 빼기"
                }
            }
        }
    }

    AppButton {
        id: addButton
        Layout.fillWidth: true
        text: "곡 추가"
        glyph: "plus"
        onClicked: panel.addRequested()
    }

    Text {
        Layout.fillWidth: true
        visible: panel.deckSize > 0
        text: "PPT " + panel.deckSize + "장 · 처음·곡 사이·끝에 빈 슬라이드"
        color: Theme.text3
        font.family: Theme.font
        font.pixelSize: 11
        wrapMode: Text.Wrap
    }
}
