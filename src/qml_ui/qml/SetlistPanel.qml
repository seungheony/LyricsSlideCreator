import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import "."

// 편집 화면 왼쪽의 콘티(곡 목록). 곡을 누르면 그 곡을 편집하고, 끌어서 순서를 바꾸고, 휴지통으로 뺀다 (0곡까지).
// 가사를 받는 중인 곡은 '가사 받는 중…'으로 자리만 보인다. 머리의 ⋯ 메뉴: 콘티 비우기·곡 추가.
// 곡 목록 위·아래에 PPT 앞·뒤에 붙일 PPT 목록(AttachList)을 두어 만들어질 PPT 순서대로 보인다.
// 목록은 EditorPage가 갖고 있고, 여기서는 신호로 알리기만 한다.
ColumnLayout {
    id: panel

    property var entries: []          // [{ id, title, artist, slides, wraps, loading }] (콘티 순서)
    property string current: ""       // 편집 중인 곡
    property string pendingId: ""     // 가사를 다 받으면 열 곡
    property alias addButton: addButton
    property alias listView: list
    property alias attachBefore: attachBefore
    property alias attachAfter: attachAfter
    property var attachments: ({ before: [], after: [] })    // backend.attachments()

    signal selected(string id)
    signal removeRequested(int index)
    signal moveRequested(int from, int to)
    signal addRequested()
    signal clearRequested()
    signal helpRequested()
    // 앞·뒤에 붙일 PPT (side: 'before' | 'after')
    signal attachDropped(string side, var urls)
    signal attachBrowse(string side)
    signal attachRemove(string side, int index)
    signal attachMove(string side, int from, int to)

    // 누르거나 끄는 중 (EditorPage가 입력칸에서 벗어날 때의 3줄 확인을 미룬다)
    readonly property bool busy: pressedRow || dragFrom >= 0 || addButton.pressed || menuButton.pressed
                                 || attachBefore.busy || attachAfter.busy

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
        HelpButton { label: "콘티"; onClicked: panel.helpRequested() }
        Item { Layout.fillWidth: true }
        AppButton {
            id: menuButton
            objectName: "setlistMenuButton"
            glyph: "more"
            variant: "ghost"
            size: "small"
            onClicked: setlistMenu.opened ? setlistMenu.close() : setlistMenu.popup(menuButton, menuButton.width - setlistMenu.width, menuButton.height + 4)
            Accessible.name: "콘티 메뉴"
            AppToolTip { visible: menuButton.hovered && !setlistMenu.opened; delay: 600; text: "콘티 메뉴" }
        }
    }

    Menu {
        id: setlistMenu
        objectName: "setlistMenu"
        popupType: Popup.Item
        padding: 6
        implicitWidth: 180
        background: Rectangle { radius: 10; color: Theme.surface; border.width: 1; border.color: Theme.border }
        component Entry: MenuItem {
            id: entry
            property string hint: ""
            implicitHeight: 34
            leftPadding: 12
            rightPadding: 12
            contentItem: RowLayout {
                spacing: 8
                Text {
                    Layout.fillWidth: true
                    text: entry.text
                    font.family: Theme.font
                    font.pixelSize: 13
                    color: entry.enabled ? Theme.text : Theme.text3
                }
                Text { text: entry.hint; visible: entry.hint !== ""; font.family: Theme.font; font.pixelSize: 12; color: Theme.text3 }
            }
            background: Rectangle { radius: 6; color: entry.highlighted ? Theme.surface2 : "transparent" }
        }
        Entry { text: "곡 추가"; hint: Theme.mod + "K"; onTriggered: panel.addRequested() }
        Entry { objectName: "clearSetlistItem"; text: "콘티 비우기"; enabled: panel.entries.length > 0; onTriggered: panel.clearRequested() }
    }

    AttachList {
        id: attachBefore
        objectName: "attachBefore"
        Layout.fillWidth: true
        title: "앞에 붙일 PPT"
        items: panel.attachments.before
        onFilesDropped: (urls) => panel.attachDropped("before", urls)
        onBrowseRequested: panel.attachBrowse("before")
        onRemoveRequested: (index) => panel.attachRemove("before", index)
        onMoveRequested: (from, to) => panel.attachMove("before", from, to)
    }

    // 키보드로 고른 줄 (모델이 새로 만들어져도 유지하려고 ListView의 currentIndex를 쓰지 않는다)
    property int focusRow: -1
    function moveFocusRow(delta) {
        focusRow = Math.max(0, Math.min(entries.length - 1, focusRow + delta))
        list.positionViewAtIndex(focusRow, ListView.Contain)
    }

    ListView {
        id: list
        objectName: "setlistList"
        visible: panel.entries.length > 0
        Layout.fillWidth: true
        Layout.fillHeight: true
        model: panel.entries
        // 키보드: Tab으로 들어와 ↑↓로 고르고 Enter·Space로 그 곡을 편집, Delete로 콘티에서 빼기, Alt+↑↓로 순서 바꾸기
        activeFocusOnTab: count > 0
        keyNavigationEnabled: false
        Accessible.role: Accessible.List
        Accessible.name: "콘티"
        onActiveFocusChanged: {
            if (!activeFocus) return
            const at = panel.entries.findIndex(e => e.id === panel.current)
            if (panel.focusRow < 0 || panel.focusRow >= panel.entries.length) panel.focusRow = Math.max(0, at)
        }
        Keys.onPressed: (event) => {
            const alt = (event.modifiers & Qt.AltModifier) !== 0
            if (event.key === Qt.Key_Up || event.key === Qt.Key_Down) {
                const delta = event.key === Qt.Key_Up ? -1 : 1
                const to = panel.focusRow + delta
                if (alt) {
                    if (to >= 0 && to < panel.entries.length) {
                        panel.moveRequested(panel.focusRow, to)
                        panel.focusRow = to
                    }
                } else panel.moveFocusRow(delta)
                event.accepted = true
            } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
                if (panel.entries[panel.focusRow]) panel.selected(panel.entries[panel.focusRow].id)
                event.accepted = true
            } else if (event.key === Qt.Key_Delete || event.key === Qt.Key_Backspace) {
                if (panel.entries[panel.focusRow]) {
                    panel.removeRequested(panel.focusRow)
                    panel.focusRow = Math.min(panel.focusRow, panel.entries.length - 1)    // 빼고 난 뒤의 곡 수 기준
                }
                event.accepted = true
            }
        }
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
            readonly property bool focused: list.activeFocus && panel.focusRow === index
            width: ListView.view.width
            height: panel.rowHeight
            z: dragged ? 2 : 0

            Rectangle {
                id: card
                width: parent.width
                height: parent.height
                y: row.dragged ? panel.dragDy : 0
                radius: Theme.radiusSm
                color: row.isCurrent ? Theme.primarySoft : area.containsMouse || row.dragged ? Theme.surface2 : Theme.surface2Clear
                border.width: row.focused ? 2 : row.isCurrent || row.dragged || row.modelData.loading ? 1 : 0
                border.color: row.focused ? Theme.primary : row.isCurrent || row.modelData.loading ? Theme.focusBorder : Theme.border
                Accessible.role: Accessible.ListItem
                Accessible.name: row.modelData.title + (row.modelData.loading ? ", 가사 받는 중" : ", " + row.modelData.slides + "장")
                Accessible.selected: row.isCurrent
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
                            visible: !row.modelData.loading
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
                        // 멜론에서 가사를 받는 중 (다 받으면 장 수가 보인다)
                        Row {
                            visible: row.modelData.loading
                            spacing: 4
                            Icon {
                                id: loadingIcon
                                glyph: "loader"
                                size: 12
                                color: Theme.primaryText
                                anchors.verticalCenter: parent.verticalCenter
                                RotationAnimation on rotation { running: row.modelData.loading; from: 0; to: 360; duration: 800; loops: Animation.Infinite; onStopped: loadingIcon.rotation = 0 }
                            }
                            Text {
                                text: panel.pendingId === row.modelData.id ? "가사 받는 중… 받으면 열어요" : "가사 받는 중…"
                                color: Theme.primaryText
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

                // 콘티에서 빼기 (다 빼면 빈 상태와 함께 곡 찾기 서랍이 열린다)
                AppButton {
                    id: removeButton
                    anchors.right: parent.right
                    anchors.rightMargin: 4
                    anchors.verticalCenter: parent.verticalCenter
                    visible: panel.dragFrom < 0 && (area.containsMouse || hovered)
                    glyph: "trash"
                    variant: "ghost"
                    size: "small"
                    onClicked: panel.removeRequested(row.index)
                    Accessible.name: "'" + row.modelData.title + "' 콘티에서 빼기"
                    AppToolTip { visible: removeButton.hovered; text: "콘티에서 빼기" }
                }
            }
        }
    }

    // 빈 콘티
    Rectangle {
        objectName: "setlistEmpty"
        visible: panel.entries.length === 0
        Layout.fillWidth: true
        Layout.fillHeight: true
        radius: 12
        color: "transparent"
        border.width: 1.5
        border.color: Theme.border
        Column {
            anchors.centerIn: parent
            spacing: 8
            Icon { anchors.horizontalCenter: parent.horizontalCenter; glyph: "music"; size: 26; color: Theme.text3; opacity: 0.7 }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                horizontalAlignment: Text.AlignHCenter
                text: "담은 곡이 여기에\n순서대로 쌓여요"
                color: Theme.text2
                font.family: Theme.font
                font.pixelSize: 13
                lineHeight: 1.4
            }
        }
    }

    AppButton {
        id: addButton
        Layout.fillWidth: true
        text: "곡 추가"
        glyph: "plus"
        variant: panel.entries.length ? "secondary" : "primary"
        onClicked: panel.addRequested()
        AppToolTip { visible: addButton.hovered; delay: 600; text: "곡 추가 (" + Theme.mod + "K)" }
    }

    AttachList {
        id: attachAfter
        objectName: "attachAfter"
        Layout.fillWidth: true
        Layout.topMargin: 4
        title: "뒤에 붙일 PPT"
        items: panel.attachments.after
        onFilesDropped: (urls) => panel.attachDropped("after", urls)
        onBrowseRequested: panel.attachBrowse("after")
        onRemoveRequested: (index) => panel.attachRemove("after", index)
        onMoveRequested: (from, to) => panel.attachMove("after", from, to)
    }
}
