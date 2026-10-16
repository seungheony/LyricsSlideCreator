import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import "."

// 예배 PPT 패널의 양식 칸 하나('찬양 전' / '찬양 후'). 곡 카드와 같은 카드 모양:
// 칸 제목 → 파일 줄(30px: 이름 · ⚠ · 책갈피 · 휴지통) → 끝의 '＋ 양식 추가' 칸(AddRow).
// PPT 파일을 구역에 끌어다 놓거나 넣기 칸으로 골라 넣고, 끌어서 순서를 바꾸고, 휴지통으로 뺀다.
// 오른쪽 책갈피로 앱에 보관하면(saved_ppts, 보관한 것은 초록 책갈피가 늘 보임) 목록에서 빼도 넣기 메뉴의
// '보관한 PPT'에서 다시 불러온다. 보관하지 않은 파일은 PPT를 만들 때마다 원본을 읽고, 오래 고치지 않았으면(stale)
// '⚠ 지난 파일'로 알린다. 목록은 EditorPage가 갖고 있고(backend.setAttachments로 저장), 여기서는 신호로 알리기만 한다.
Rectangle {
    id: box
    implicitHeight: col.implicitHeight + 16
    radius: 12
    color: Theme.surface2

    property string title: ""
    property var items: []            // [{ path, name, slides, error, missing, sizeMismatch, stale, saved, id, hasSource }] (backend.describe_attachments)
    property var savedItems: []       // 보관한 PPT [{ id, name, slides }] (backend.savedPpts)
    property var placed: ({})         // 보관한 PPT id → 지금 있는 곳 ('앞' | '뒤') — 넣기 메뉴에 표시
    property string sideName: ""      // 이 목록: '앞' | '뒤'

    signal filesDropped(var urls)
    signal browseRequested()
    signal removeRequested(int index)
    signal moveRequested(int from, int to)
    signal keepRequested(int index)            // 앱에 보관
    signal unkeepRequested(int index)          // 보관 풀기 (원본 파일로 돌아간다)
    signal savedChosen(string id)              // 보관한 PPT를 목록에 넣기
    signal manageRequested()                   // 보관한 PPT 관리 창

    // 넣기 칸: 보관한 PPT가 있으면 메뉴, 없으면 바로 파일 고르기
    function openAdd() {
        if (!savedItems.length) { browseRequested(); return }
        addMenu.popup(addButton, 0, addButton.height + 4)
    }

    // 누르거나 끄는 중 (EditorPage가 입력칸에서 벗어날 때의 3줄 확인을 미룬다)
    readonly property bool busy: pressedRow || dragFrom >= 0 || addButton.pressed || addMenu.opened
    readonly property bool dropHover: drop.containsDrag

    // ── 끌어서 순서 바꾸기 ── (SetlistPanel과 같은 방식)
    property bool pressedRow: false
    property int dragFrom: -1
    property real dragDy: 0
    readonly property int rowHeight: 30
    readonly property int rowGap: 3
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

    // 오른쪽 상태 (짧게, 자세한 것은 툴팁)
    function status(item) {
        if (item.error) return item.missing ? "없음" : "열 수 없음"
        if (item.sizeMismatch) return "크기 다름"
        if (item.stale) return "지난 파일"
        return ""
    }

    function tooltip(item) {
        const where = item.saved ? "앱에 보관한 PPT예요 (보관한 때의 파일 그대로)" : item.path
        if (item.error) return item.error + "\n" + where
        if (item.sizeMismatch) return "처음 붙이는 PPT와 슬라이드 크기가 달라서 모양이 어긋날 수 있어요.\n" + where
        if (item.stale) return item.stale + "에 고친 파일이에요. 이번 주 PPT가 맞는지 확인해 주세요.\n" + where
        return where
    }

    ColumnLayout {
    id: col
    anchors.fill: parent
    anchors.margins: 8
    spacing: 4

    Text {
        Layout.leftMargin: 2
        Layout.bottomMargin: 2
        text: box.title
        color: Theme.text2
        font.family: Theme.font
        font.pixelSize: 12
        font.weight: Font.Bold
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

    // 줄들과 넣기 칸 (구역 전체가 PPT 파일을 놓는 자리)
    Item {
        id: body
        Layout.fillWidth: true
        implicitHeight: content.implicitHeight

        ColumnLayout {
            id: content
            width: parent.width
            spacing: box.rowGap

            Item {
                id: rows
                visible: box.items.length > 0
                Layout.fillWidth: true
                implicitHeight: box.items.length * box.step - box.rowGap

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
                        readonly property bool hot: area.containsMouse || keepButton.hovered || removeButton.hovered
                        readonly property string state_: box.status(modelData)
                        y: index * box.step
                        width: parent.width
                        height: box.rowHeight
                        z: dragged ? 2 : 0
                        activeFocusOnTab: true
                        Accessible.role: Accessible.ListItem
                        Accessible.name: modelData.name + (state_ ? ", " + state_ : "") + (modelData.saved ? ", 보관됨" : "")
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
                            color: row.hot || row.dragged ? Theme.border : Theme.surface
                            radius: 8
                            border.width: row.activeFocus ? 2 : 0
                            border.color: Theme.primary
                            opacity: row.dragged ? 0.9 : 1
                            Behavior on color { ColorAnimation { duration: Theme.fast } }

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 8
                                anchors.rightMargin: 2
                                spacing: 2
                                Text {
                                    Layout.fillWidth: true
                                    text: row.modelData.name
                                    textFormat: Text.PlainText
                                    color: row.problem ? Theme.danger : Theme.text
                                    font.family: Theme.font
                                    font.pixelSize: 12
                                    font.weight: Font.DemiBold
                                    elide: Text.ElideRight
                                }
                                // 상태: 곡 줄의 '⚠ 줄바꿈'과 같은 모양 (마우스를 올리면 버튼 자리를 내준다)
                                // 상태는 ⚠만 (무엇인지는 툴팁)
                                Icon { visible: row.state_ !== "" && !row.hot; glyph: "alert"; size: 12; color: row.problem ? Theme.danger : Theme.warning; Layout.rightMargin: 4 }
                                // 보관: 보관한 것은 초록 책갈피가 늘 보이고, 아닌 것은 마우스를 올렸을 때만
                                AppButton {
                                    id: keepButton
                                    readonly property bool on: !!row.modelData.saved
                                    readonly property bool locked: on && !row.modelData.hasSource    // 원본이 없어 풀 수 없음
                                    visible: !row.problem && (on || row.hot || row.activeFocus || activeFocus || removeButton.activeFocus)
                                    glyph: "library"                  // 저장한 곡(보관함)과 같은 표시
                                    variant: "ghost"
                                    size: "small"
                                    implicitHeight: 24
                                    tint: on ? Theme.primaryText : "transparent"
                                    onClicked: {
                                        if (locked) return
                                        if (on) box.unkeepRequested(row.index)
                                        else box.keepRequested(row.index)
                                    }
                                    Accessible.name: "'" + row.modelData.name + "' " + (on ? "보관함에서 지우기" : "보관함에 넣기")
                                    AppToolTip {
                                        visible: keepButton.hovered
                                        text: !keepButton.on ? "보관함에 넣기 · 원본을 지우거나 빼도 '양식 추가'에서 다시 불러와요"
                                            : row.modelData.hasSource ? "보관함에 있어요 · 누르면 보관함에서 지우고 원본 파일을 그때그때 읽어요"
                                            : "보관함에 있어요 · 원본 파일이 없어서 보관함에서 지울 수 없어요"
                                    }
                                }
                                AppButton {
                                    id: removeButton
                                    visible: box.dragFrom < 0 && (row.hot || row.activeFocus || activeFocus || keepButton.activeFocus)
                                    glyph: "x"                    // 이번 예배 PPT에서 빼기 (영구 삭제는 휴지통)
                                    variant: "ghost"
                                    size: "small"
                                    implicitHeight: 24
                                    onClicked: box.removeRequested(row.index)
                                    Accessible.name: "'" + row.modelData.name + "' 이번 예배 PPT에서 빼기"
                                    AppToolTip { visible: removeButton.hovered; text: row.modelData.saved ? "이번 예배 PPT에서 빼기 · 보관함에는 남아요" : "이번 예배 PPT에서 빼기 · 원본 파일은 그대로예요" }
                                }
                            }

                            MouseArea {
                                id: area
                                z: -1
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
                            AppToolTip { visible: area.containsMouse && box.dragFrom < 0; delay: 600; text: box.tooltip(row.modelData) }
                        }
                    }
                }
            }

            AddRow {
                id: addButton
                Layout.fillWidth: true
                implicitHeight: box.rowHeight
                small: true
                text: drop.containsDrag ? "여기에 놓기" : "양식 추가"
                lit: drop.containsDrag
                onClicked: addMenu.opened ? addMenu.close() : box.openAdd()
                AppToolTip { visible: addButton.hovered && !addMenu.opened; delay: 600; text: "PPT 파일을 끌어다 놓거나 눌러서 골라요" }
            }
        }

        DropArea {
            id: drop
            parent: box
            anchors.fill: parent
            onEntered: (drag) => { drag.accepted = drag.hasUrls }
            onDropped: (event) => {
                if (!event.hasUrls) return
                event.acceptProposedAction()
                box.filesDropped(event.urls)
            }
        }
    }
    Item { Layout.fillHeight: true }    // 칸이 옆 칸보다 낮으면 줄을 위에서부터 쌓는다
    }
}
