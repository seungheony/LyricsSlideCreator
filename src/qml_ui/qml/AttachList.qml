import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import "."

// 콘티 패널의 '앞에 붙일 PPT' / '뒤에 붙일 PPT' 목록. PPT 파일을 끌어다 놓거나 ＋로 골라 넣고,
// 끌어서 순서를 바꾸고, 휴지통으로 뺀다. 줄마다 늘 보이는 [보관]을 켜면 앱에 복사해 두어(saved_ppts)
// 목록에서 빼도 ＋ 메뉴의 '보관한 PPT'에서 다시 불러온다. 보관하지 않은 파일은 PPT를 만들 때마다 원본을 읽고,
// 오래 고치지 않았으면(stale) 주황색으로 알린다. 목록은 EditorPage가 갖고 있고(backend.setAttachments로 저장),
// 여기서는 신호로 알리기만 한다.
ColumnLayout {
    id: box

    property string title: ""
    property var items: []            // [{ path, name, slides, error, missing, sizeMismatch, stale, saved, id, hasSource }] (backend.describe_attachments)
    property var savedItems: []       // 보관한 PPT [{ id, name, slides }] (backend.savedPpts)
    property var placed: ({})         // 보관한 PPT id → 지금 있는 곳 ('앞' | '뒤') — ＋ 메뉴에 표시
    property string sideName: ""      // 이 목록: '앞' | '뒤'

    signal filesDropped(var urls)
    signal browseRequested()
    signal removeRequested(int index)
    signal moveRequested(int from, int to)
    signal keepRequested(int index)            // 앱에 보관
    signal unkeepRequested(int index)          // 보관 풀기 (원본 파일로 돌아간다)
    signal savedChosen(string id)              // 보관한 PPT를 목록에 넣기
    signal manageRequested()                   // 보관한 PPT 관리 창

    // ＋·빈 칸: 보관한 PPT가 있으면 메뉴, 없으면 바로 파일 고르기
    function openAdd() {
        if (!savedItems.length) { browseRequested(); return }
        addMenu.popup(addButton, addButton.width - addMenu.width, addButton.height + 4)
    }

    // 누르거나 끄는 중 (EditorPage가 입력칸에서 벗어날 때의 3줄 확인을 미룬다)
    readonly property bool busy: pressedRow || dragFrom >= 0 || addButton.pressed || addMenu.opened
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
        return item.sizeMismatch ? "슬라이드 크기가 달라요" : item.stale ? item.stale + "에 고친 파일" : ""
    }

    function tooltip(item) {
        const where = item.saved ? "앱에 보관한 PPT예요 (보관한 때의 파일 그대로)" : item.path
        if (item.error) return item.error + "\n" + where
        if (item.sizeMismatch) return "처음 붙이는 PPT와 슬라이드 크기가 달라서 모양이 어긋날 수 있어요.\n" + where
        if (item.stale) return "오래 고치지 않은 파일이에요. 이번 주 PPT가 맞는지 확인해 주세요.\n" + where
        return where
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
            onClicked: addMenu.opened ? addMenu.close() : box.openAdd()
            Accessible.name: box.title + " 넣기"
            AppToolTip { visible: addButton.hovered && !addMenu.opened; delay: 600; text: box.savedItems.length ? "보관한 PPT · 파일 고르기" : "PPT 파일 고르기" }
        }
    }

    Menu {
        id: addMenu
        popupType: Popup.Item
        padding: 6
        implicitWidth: 250
        background: Rectangle { radius: 10; color: Theme.surface; border.width: 1; border.color: Theme.border }

        MenuItem {
            enabled: false
            implicitHeight: 26
            leftPadding: 10
            contentItem: Text { text: "보관한 PPT"; color: Theme.text3; font.family: Theme.font; font.pixelSize: 11; font.weight: Font.DemiBold; verticalAlignment: Text.AlignVCenter }
            background: Item {}
        }
        Repeater {
            model: box.savedItems
            delegate: MenuItem {
                id: savedEntry
                required property var modelData
                readonly property string where: box.placed[modelData.id] || ""
                enabled: where !== box.sideName       // 이 목록에 이미 있으면 못 고른다
                implicitHeight: 36
                leftPadding: 10
                rightPadding: 10
                onTriggered: box.savedChosen(modelData.id)
                contentItem: RowLayout {
                    spacing: 6
                    Text {
                        Layout.fillWidth: true
                        text: savedEntry.modelData.name
                        textFormat: Text.PlainText
                        color: savedEntry.enabled ? Theme.text : Theme.text3
                        font.family: Theme.font
                        font.pixelSize: 13
                        elide: Text.ElideMiddle
                    }
                    Text {
                        visible: savedEntry.where !== ""
                        text: savedEntry.where + "에 있음"
                        color: savedEntry.where ? Theme.primaryText : Theme.text3
                        font.family: Theme.font
                        font.pixelSize: savedEntry.where ? 11 : 12
                        font.weight: savedEntry.where ? Font.Bold : Font.Normal
                    }
                }
                background: Rectangle { radius: 6; color: savedEntry.highlighted ? Theme.surface2 : "transparent" }
            }
        }
        MenuSeparator {
            contentItem: Rectangle { implicitHeight: 1; color: Theme.border }
        }
        MenuItem {
            id: browseEntry
            implicitHeight: 34
            leftPadding: 10
            onTriggered: box.browseRequested()
            contentItem: RowLayout {
                spacing: 6
                Icon { glyph: "plus"; size: 13; color: Theme.text2 }
                Text { Layout.fillWidth: true; text: "파일에서 고르기…"; color: Theme.text; font.family: Theme.font; font.pixelSize: 13 }
            }
            background: Rectangle { radius: 6; color: browseEntry.highlighted ? Theme.surface2 : "transparent" }
        }
        MenuItem {
            id: manageEntry
            implicitHeight: 34
            leftPadding: 10
            onTriggered: box.manageRequested()
            contentItem: Text { text: "보관한 PPT 관리…"; color: Theme.text2; font.family: Theme.font; font.pixelSize: 13; verticalAlignment: Text.AlignVCenter }
            background: Rectangle { radius: 6; color: manageEntry.highlighted ? Theme.surface2 : "transparent" }
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
                onClicked: box.openAdd()
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
                // 키보드: Delete로 빼기, Alt+↑↓로 순서 바꾸기 (Tab으로 보관·빼기 버튼)
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
                    border.color: row.activeFocus ? Theme.primary : row.problem ? Theme.danger
                                : row.modelData.stale ? Qt.rgba(Theme.warning.r, Theme.warning.g, Theme.warning.b, 0.5) : Theme.border
                    opacity: row.dragged ? 0.9 : 1
                    Behavior on color { ColorAnimation { duration: Theme.fast } }

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 8
                        anchors.rightMargin: 6
                        spacing: 7
                        Icon { visible: row.problem; glyph: "alert"; size: 14; color: Theme.danger }
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
                                visible: text !== ""
                                text: box.subtitle(row.modelData)
                                color: row.problem ? Theme.danger : row.modelData.sizeMismatch || row.modelData.stale ? Theme.warning : Theme.text3
                                font.family: Theme.font
                                font.pixelSize: 11
                                elide: Text.ElideRight
                            }
                        }
                        Item { Layout.preferredWidth: rowButtons.width; Layout.preferredHeight: 1 }
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
                    AppToolTip { visible: area.containsMouse && box.dragFrom < 0 && !removeButton.hovered && !keepPill.hovered; delay: 600; text: box.tooltip(row.modelData) }

                    Row {
                        id: rowButtons
                        anchors.right: parent.right
                        anchors.rightMargin: 4
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 2
                        // 보관 켜고 끄기 (늘 보인다). 보관을 풀면 원본 파일로 돌아가므로 원본이 없으면 끌 수 없다
                        Button {
                            id: keepPill
                            readonly property bool on: !!row.modelData.saved
                            visible: !row.problem
                            readonly property bool locked: on && !row.modelData.hasSource    // 원본이 없어 풀 수 없음
                            anchors.verticalCenter: parent.verticalCenter
                            implicitHeight: 24
                            leftPadding: 8
                            rightPadding: 8
                            topPadding: 0
                            bottomPadding: 0
                            hoverEnabled: true
                            focusPolicy: Qt.TabFocus
                            checkable: false
                            text: on ? "✓ 보관됨" : "보관"
                            font.family: Theme.font
                            font.pixelSize: 11
                            font.weight: Font.Bold
                            HoverHandler { cursorShape: keepPill.locked ? Qt.ArrowCursor : Qt.PointingHandCursor }
                            Keys.onReturnPressed: click()
                            Keys.onEnterPressed: click()
                            onClicked: {
                                if (locked) return
                                if (on) box.unkeepRequested(row.index)
                                else box.keepRequested(row.index)
                            }
                            contentItem: Text {
                                text: keepPill.text
                                font: keepPill.font
                                color: keepPill.on ? Theme.primaryText : keepPill.hovered ? Theme.text : Theme.text2
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                            }
                            background: Rectangle {
                                radius: height / 2
                                color: keepPill.on ? (keepPill.hovered && !keepPill.locked ? Theme.primarySoftHover : Theme.primarySoft)
                                                   : keepPill.hovered ? Theme.surface2 : Theme.surfaceClear
                                border.width: keepPill.visualFocus ? 2 : keepPill.on ? 0 : 1
                                border.color: keepPill.visualFocus ? Theme.primary : Theme.border
                            }
                            Accessible.name: "'" + row.modelData.name + "' " + (on ? "보관 풀기" : "앱에 보관")
                            AppToolTip {
                                visible: keepPill.hovered
                                text: !keepPill.on ? "앱에 보관하면 원본을 지우거나 목록에서 빼도 ＋에서 다시 불러와요"
                                    : row.modelData.hasSource ? "보관을 풀면 원본 파일을 그때그때 읽어요"
                                    : "원본 파일이 없어서 보관을 풀 수 없어요"
                            }
                        }
                        AppButton {
                            id: removeButton
                            visible: box.dragFrom < 0 && (area.containsMouse || hovered || keepPill.hovered
                                                          || row.activeFocus || activeFocus || keepPill.activeFocus)
                            glyph: "trash"
                            variant: "ghost"
                            size: "small"
                            implicitHeight: 26
                            onClicked: box.removeRequested(row.index)
                            Accessible.name: "'" + row.modelData.name + "' 빼기"
                            AppToolTip { visible: removeButton.hovered; text: row.modelData.saved ? "목록에서 빼기 (보관한 PPT에는 남아요)" : "빼기" }
                        }
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
