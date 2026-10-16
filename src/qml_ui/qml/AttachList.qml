import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import "."

// 콘티 패널의 '앞에 붙일 PPT' / '뒤에 붙일 PPT' 목록. PPT 파일을 끌어다 놓거나 ＋로 골라 넣고,
// 끌어서 순서를 바꾸고, 휴지통으로 뺀다. 목록은 EditorPage가 갖고 있고(backend.setAttachments로 저장),
// 여기서는 신호로 알리기만 한다.
ColumnLayout {
    id: box

    property string title: ""
    property var items: []            // [{ path, name, slides, error, missing, sizeMismatch }] (backend.describe_attachments)

    signal filesDropped(var urls)
    signal browseRequested()
    signal removeRequested(int index)
    signal moveRequested(int from, int to)

    // 누르거나 끄는 중 (EditorPage가 입력칸에서 벗어날 때의 3줄 확인을 미룬다)
    readonly property bool busy: pressedRow || dragFrom >= 0 || addButton.pressed
    readonly property bool dropHover: drop.containsDrag

    // ── 끌어서 순서 바꾸기 ── (SetlistPanel과 같은 방식)
    property bool pressedRow: false
    property int dragFrom: -1
    property real dragDy: 0
    readonly property int rowHeight: 42
    readonly property int rowGap: 4
    readonly property int step: rowHeight + rowGap
    readonly property int dropIndex: dragFrom < 0 ? -1
        : Math.max(0, Math.min(items.length - 1, Math.round((dragFrom * step + dragDy) / step)))

    function endDrag(commit) {
        const from = dragFrom
        const to = dropIndex
        dragFrom = -1
        dragDy = 0
        pressedRow = false
        if (commit && from >= 0 && to !== from) moveRequested(from, to)
    }

    function subtitle(item) {
        if (item.error) return item.missing ? "파일을 찾을 수 없어요" : "넣을 수 없는 파일이에요"
        return item.slides + "장" + (item.sizeMismatch ? " · 슬라이드 크기가 달라요" : "")
    }

    function tooltip(item) {
        if (item.error) return item.error + "\n" + item.path
        if (item.sizeMismatch) return "처음 붙이는 PPT와 슬라이드 크기가 달라서 모양이 어긋날 수 있어요.\n" + item.path
        return item.path
    }

    spacing: 6

    RowLayout {
        Layout.fillWidth: true
        spacing: 6
        Text {
            text: box.title
            color: Theme.text2
            font.family: Theme.font
            font.pixelSize: 12
            font.weight: Font.DemiBold
        }
        Item { Layout.fillWidth: true }
        AppButton {
            id: addButton
            glyph: "plus"
            variant: "ghost"
            size: "small"
            implicitHeight: 24
            onClicked: box.browseRequested()
            Accessible.name: box.title + " 고르기"
            AppToolTip { visible: addButton.hovered; delay: 600; text: "PPT 파일 고르기" }
        }
    }

    Item {
        Layout.fillWidth: true
        implicitHeight: box.items.length ? box.items.length * box.step - box.rowGap : 40

        // 빈 목록: 끌어다 놓을 자리
        Rectangle {
            anchors.fill: parent
            visible: box.items.length === 0
            radius: Theme.radiusSm
            color: drop.containsDrag ? Theme.primarySoft : Theme.surface2Clear
            border.width: 1.5
            border.color: drop.containsDrag ? Theme.primary : Theme.border
            Text {
                anchors.centerIn: parent
                width: parent.width - 16
                horizontalAlignment: Text.AlignHCenter
                text: drop.containsDrag ? "여기에 놓기" : "PPT 파일을 끌어다 놓기"
                color: drop.containsDrag ? Theme.primaryText : Theme.text3
                font.family: Theme.font
                font.pixelSize: 12
                elide: Text.ElideRight
            }
            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: box.browseRequested()
            }
        }

        // 목록 위로 끌어 올 때 (놓으면 끝에 더한다)
        Rectangle {
            anchors.fill: parent
            anchors.margins: -3
            visible: box.items.length > 0 && drop.containsDrag
            z: 5
            radius: Theme.radiusSm + 2
            color: "transparent"
            border.width: 2
            border.color: Theme.primary
        }

        // 놓을 자리 표시
        Rectangle {
            readonly property int gap: box.dropIndex > box.dragFrom ? box.dropIndex + 1 : box.dropIndex
            visible: box.dragFrom >= 0 && box.dropIndex !== box.dragFrom
            z: 3
            x: 4
            width: parent.width - 8
            height: 2
            radius: 1
            color: Theme.primary
            y: gap * box.step - box.rowGap / 2 - 1
        }

        Repeater {
            model: box.items
            delegate: Item {
                id: row
                required property int index
                required property var modelData
                readonly property bool dragged: box.dragFrom === index
                readonly property bool problem: !!modelData.error
                y: index * box.step
                width: parent.width
                height: box.rowHeight
                z: dragged ? 2 : 0
                activeFocusOnTab: true
                Accessible.role: Accessible.ListItem
                Accessible.name: row.modelData.name + ", " + box.subtitle(row.modelData)
                // 키보드: Delete로 빼기, Alt+↑↓로 순서 바꾸기
                Keys.onPressed: (event) => {
                    const alt = (event.modifiers & Qt.AltModifier) !== 0
                    if (alt && (event.key === Qt.Key_Up || event.key === Qt.Key_Down)) {
                        const to = row.index + (event.key === Qt.Key_Up ? -1 : 1)
                        if (to >= 0 && to < box.items.length) box.moveRequested(row.index, to)
                        event.accepted = true
                    } else if (event.key === Qt.Key_Delete || event.key === Qt.Key_Backspace) {
                        box.removeRequested(row.index)
                        event.accepted = true
                    }
                }

                Rectangle {
                    id: card
                    width: parent.width
                    height: parent.height
                    y: row.dragged ? box.dragDy : 0
                    radius: Theme.radiusSm
                    color: area.containsMouse || row.dragged ? Theme.surface2 : Theme.surface2Clear
                    border.width: row.activeFocus ? 2 : 1
                    border.color: row.activeFocus ? Theme.primary : row.problem ? Theme.danger : Theme.border
                    opacity: row.dragged ? 0.9 : 1
                    Behavior on color { ColorAnimation { duration: Theme.fast } }

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 8
                        anchors.rightMargin: 6
                        spacing: 7
                        Icon {
                            glyph: row.problem ? "alert" : "monitor"
                            size: 14
                            color: row.problem ? Theme.danger : Theme.text3
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 1
                            Text {
                                Layout.fillWidth: true
                                text: row.modelData.name
                                textFormat: Text.PlainText
                                color: row.problem ? Theme.text3 : Theme.text
                                font.family: Theme.font
                                font.pixelSize: 12
                                font.weight: Font.DemiBold
                                elide: Text.ElideMiddle
                            }
                            Text {
                                Layout.fillWidth: true
                                text: box.subtitle(row.modelData)
                                color: row.problem ? Theme.danger : row.modelData.sizeMismatch ? Theme.warning : Theme.text3
                                font.family: Theme.font
                                font.pixelSize: 11
                                elide: Text.ElideRight
                            }
                        }
                        Item { Layout.preferredWidth: removeButton.visible ? removeButton.width : 0; Layout.preferredHeight: 1 }
                    }

                    MouseArea {
                        id: area
                        anchors.fill: parent
                        hoverEnabled: true
                        preventStealing: true
                        cursorShape: box.dragFrom >= 0 ? Qt.ClosedHandCursor : box.items.length > 1 ? Qt.OpenHandCursor : Qt.ArrowCursor
                        property real pressY: 0
                        onPressed: (mouse) => { pressY = mouse.y; box.pressedRow = true }
                        onPositionChanged: (mouse) => {
                            if (!pressed) return
                            const dy = mouse.y - pressY + (row.dragged ? box.dragDy : 0)
                            if (box.dragFrom < 0 && Math.abs(mouse.y - pressY) > 6 && box.items.length > 1) box.dragFrom = row.index
                            if (row.dragged) box.dragDy = Math.max(-row.index * box.step,
                                Math.min((box.items.length - 1 - row.index) * box.step, dy))
                        }
                        onReleased: {
                            if (box.dragFrom >= 0) box.endDrag(true)
                            else box.pressedRow = false
                        }
                        onCanceled: box.endDrag(false)
                    }
                    AppToolTip { visible: area.containsMouse && box.dragFrom < 0 && !removeButton.hovered; delay: 600; text: box.tooltip(row.modelData) }

                    AppButton {
                        id: removeButton
                        anchors.right: parent.right
                        anchors.rightMargin: 4
                        anchors.verticalCenter: parent.verticalCenter
                        visible: box.dragFrom < 0 && (area.containsMouse || hovered)
                        glyph: "trash"
                        variant: "ghost"
                        size: "small"
                        implicitHeight: 26
                        onClicked: box.removeRequested(row.index)
                        Accessible.name: "'" + row.modelData.name + "' 빼기"
                        AppToolTip { visible: removeButton.hovered; text: "빼기" }
                    }
                }
            }
        }

        DropArea {
            id: drop
            anchors.fill: parent
            anchors.margins: -6
            onEntered: (drag) => { drag.accepted = drag.hasUrls }
            onDropped: (event) => {
                if (!event.hasUrls) return
                event.acceptProposedAction()
                box.filesDropped(event.urls)
            }
        }
    }
}
