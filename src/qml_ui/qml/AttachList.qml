import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import "."

// 예배 PPT 패널의 양식 칸 하나('찬양 전' / '찬양 후'). 곡 카드와 같은 카드 모양:
// 칸 제목 → 파일 줄(30px: 이름 · ⚠ · 책갈피 · 휴지통) → 끝의 '＋ 양식 추가' 칸(AddRow).
// PPT 파일을 구역에 끌어다 놓거나 넣기 칸으로 골라 넣고, 끌어서 순서를 바꾸고, 휴지통으로 뺀다.
// 오른쪽 보관함 아이콘으로 양식 보관함에 넣으면(saved_ppts, 보관한 것은 초록 아이콘) 빼도 양식 보관함
// (곡 찾기 서랍의 '양식 보관함' 화면)에서 다시 꺼내 쓴다. 초록 아이콘을 누르면 보관함에서 그 양식을 보여 준다. 보관하지 않은 파일은 PPT를 만들 때마다 원본을 읽고, 오래 고치지 않았으면(stale)
// '⚠ 지난 파일'로 알린다. 목록은 EditorPage가 갖고 있고(backend.setAttachments로 저장), 여기서는 신호로 알리기만 한다.
Rectangle {
    id: box
    readonly property bool empty: items.length === 0
    implicitHeight: empty ? 72 : col.implicitHeight + 16
    radius: 12
    color: Theme.surface2
    border.width: externalHover && !empty ? 2 : 0
    border.color: Theme.primary

    property string title: ""
    property bool externalHover: false    // 양식 보관함에서 끌어 온 양식이 이 칸 위에 있다
    property var items: []            // [{ path, name, slides, error, missing, sizeMismatch, stale, saved, id, hasSource }] (backend.describe_attachments)

    signal filesDropped(var urls)
    signal browseRequested()                   // '＋ 양식 추가': 양식 보관함 열기 (SetlistPanel)
    signal removeRequested(int index)
    signal moveRequested(int from, int to)
    signal keepRequested(int index)            // 양식 보관함에 넣기
    signal libraryRequested(string id)         // 보관한 양식: 양식 보관함에서 보기 (지우기는 보관함에서만)

    // 누르거나 끄는 중 (EditorPage가 입력칸에서 벗어날 때의 3줄 확인을 미룬다)
    readonly property bool busy: pressedRow || dragFrom >= 0 || addButton.pressed
    readonly property bool dropHover: drop.containsDrag

    // ── 끌어서 순서 바꾸기 · 칸 밖으로 끌어내 빼기 ── (SetlistPanel과 같은 방식)
    property bool pressedRow: false
    property int dragFrom: -1
    property real dragDy: 0
    property bool dragOut: false      // 칸 밖에 있음: 놓으면 뺀다
    property var dragHost: null       // EditorPage: 칸 밖에 있는 동안 커서를 따라가는 표시 (showOutDrag / hideOutDrag)
    readonly property int rowHeight: 30
    readonly property int rowGap: 3
    readonly property int step: rowHeight + rowGap
    readonly property int dropIndex: dragFrom < 0 ? -1
        : Math.max(0, Math.min(items.length - 1, Math.round((dragFrom * step + dragDy) / step)))

    function endDrag(commit) {
        const from = dragFrom
        const to = dropIndex
        const out = dragOut
        dragFrom = -1
        dragDy = 0
        dragOut = false
        pressedRow = false
        if (dragHost) dragHost.hideOutDrag()
        if (!commit || from < 0) return
        if (out) removeRequested(from)
        else if (to !== from) moveRequested(from, to)
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

    // 빈 칸: 회색 바탕 가운데에 칸 이름, 마우스를 올리면(또는 끌어 오면) 초록으로 '＋ 양식 추가' (찬양 카드와 같은 방식)
    Rectangle {
        id: emptyFace
        readonly property bool lit: emptyHover.containsMouse || activeFocus || drop.containsDrag || box.externalHover
        visible: box.empty
        anchors.fill: parent
        radius: box.radius
        color: lit ? Theme.primarySoft : "transparent"
        border.width: lit ? 2 : 0
        border.color: Theme.primary
        activeFocusOnTab: true
        Accessible.role: Accessible.Button
        Accessible.name: box.title + " 양식 추가"
        Keys.onReturnPressed: box.browseRequested()
        Keys.onEnterPressed: box.browseRequested()
        Keys.onSpacePressed: box.browseRequested()
        Behavior on color { ColorAnimation { duration: Theme.fast } }
        Text {
            anchors.centerIn: parent
            visible: !emptyFace.lit
            text: box.title
            color: Theme.text2
            font.family: Theme.font
            font.pixelSize: 13
            font.weight: Font.Bold
        }
        Row {
            anchors.centerIn: parent
            visible: emptyFace.lit
            spacing: 5
            Icon { glyph: "plus"; size: 13; color: Theme.primaryText; anchors.verticalCenter: parent.verticalCenter }
            Text {
                text: drop.containsDrag || box.externalHover ? "여기에 놓기" : "양식 추가"
                color: Theme.primaryText
                font.family: Theme.font
                font.pixelSize: 13
                font.weight: Font.Bold
                anchors.verticalCenter: parent.verticalCenter
            }
        }
        MouseArea {
            id: emptyHover
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: box.browseRequested()
        }
        AppToolTip { visible: emptyHover.containsMouse; delay: 600; text: "눌러서 양식 보관함에서 골라요 · PPT 파일을 끌어다 놓아도 돼요" }
    }

    ColumnLayout {
    id: col
    visible: !box.empty
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
                    visible: box.dragFrom >= 0 && box.dropIndex !== box.dragFrom && !box.dragOut
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
                            y: row.dragged && !box.dragOut ? box.dragDy : 0     // 칸 밖으로 끌어냈으면 제자리에서 빨갛게
                            readonly property bool out: row.dragged && box.dragOut     // 놓으면 빠진다
                            color: out ? Qt.rgba(Theme.danger.r, Theme.danger.g, Theme.danger.b, 0.15)
                                 : row.hot || row.dragged ? Theme.border : Theme.surface
                            radius: 8
                            border.width: row.activeFocus ? 2 : out ? 1 : 0
                            border.color: out ? Theme.danger : Theme.primary
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
                                Text {
                                    visible: card.out
                                    Layout.rightMargin: 6
                                    text: "놓으면 빼요"
                                    color: Theme.danger
                                    font.family: Theme.font
                                    font.pixelSize: 11
                                    font.weight: Font.Bold
                                }
                                Icon { visible: row.state_ !== "" && !row.hot && !card.out; glyph: "alert"; size: 12; color: row.problem ? Theme.danger : Theme.warning; Layout.rightMargin: 4 }
                                // 보관: 보관한 것은 초록, 아닌 것은 회색. 빼기(×)처럼 마우스를 올리거나 키보드로 왔을 때만
                                AppButton {
                                    id: keepButton
                                    readonly property bool on: !!row.modelData.saved
                                    visible: !row.problem && box.dragFrom < 0 && (row.hot || row.activeFocus || activeFocus || removeButton.activeFocus)
                                    glyph: "library"                  // 찬양 보관함과 같은 표시
                                    variant: "ghost"
                                    size: "small"
                                    implicitHeight: 24
                                    tint: on ? Theme.primaryText : "transparent"
                                    onClicked: {
                                        if (on) box.libraryRequested(row.modelData.id)
                                        else box.keepRequested(row.index)
                                    }
                                    Accessible.name: "'" + row.modelData.name + "' " + (on ? "양식 보관함에서 보기" : "양식 보관함에 넣기")
                                    AppToolTip {
                                        visible: keepButton.hovered
                                        text: !keepButton.on ? "양식 보관함에 넣기 · 원본을 지우거나 빼도 보관함에서 다시 꺼내 써요"
                                            : "양식 보관함에 있어요 · 누르면 보관함에서 보여 줘요"
                                    }
                                }
                                AppButton {
                                    id: removeButton
                                    visible: box.dragFrom < 0 && (row.hot || row.activeFocus || activeFocus || keepButton.activeFocus)
                                    glyph: "x"                    // 이번 예배 PPT에서 빼기 (삭제는 휴지통)
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
                                cursorShape: box.dragFrom >= 0 ? Qt.ClosedHandCursor : Qt.OpenHandCursor
                                property real pressX: 0
                                property real pressY: 0
                                onPressed: (mouse) => { pressX = mouse.x; pressY = mouse.y; box.pressedRow = true }
                                onPositionChanged: (mouse) => {
                                    if (!pressed) return
                                    // card가 위아래로 따라 움직이므로 card 안의 좌표는 그대로 → 움직인 거리를 더해 간다 (옆으로는 움직이지 않고, 밖으로 나가면 빨갛게)
                                    const dy = mouse.y - pressY + card.y
                                    if (box.dragFrom < 0 && Math.max(Math.abs(mouse.x - pressX), Math.abs(mouse.y - pressY)) > 6) box.dragFrom = row.index
                                    if (!row.dragged) return
                                    box.dragDy = Math.max(-row.index * box.step,
                                        Math.min((box.items.length - 1 - row.index) * box.step, dy))
                                    // 포인터가 이 칸(찬양 전·후) 밖으로 16px 넘게 나가면 놓았을 때 뺀다
                                    const p = mapToItem(box, mouse.x, mouse.y)
                                    box.dragOut = p.x < -16 || p.x > box.width + 16 || p.y < -16 || p.y > box.height + 16
                                    if (!box.dragHost) return
                                    const sp = mapToItem(null, mouse.x, mouse.y)
                                    if (box.dragOut) box.dragHost.showOutDrag(row.modelData.name, "library", sp.x, sp.y)
                                    else box.dragHost.hideOutDrag()
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
                text: drop.containsDrag || box.externalHover ? "여기에 놓기" : "양식 추가"
                lit: drop.containsDrag || box.externalHover
                onClicked: box.browseRequested()
                AppToolTip { visible: addButton.hovered; delay: 600; text: "눌러서 양식 보관함에서 골라요 · PPT 파일을 끌어다 놓아도 돼요" }
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
