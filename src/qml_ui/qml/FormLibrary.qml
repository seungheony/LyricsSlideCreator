import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import "."

// 양식 보관함: 곡 찾기 서랍의 '양식 보관함' 화면 (예배 PPT 패널의 '양식' 제목 옆 보관함 아이콘으로 연다).
// 보관한 PPT(saved_ppts)를 왼쪽 찬양 전·후 칸으로 끌어다 놓아 넣고(SongDragArea → EditorPage), 이름을 고치고,
// 삭제한다(빨간 휴지통 → 확인창). 위 칸에 PPT 파일을 끌어다 놓거나 눌러서 고르면 보관함에만 넣는다.
// 줄: 이름 · 연필 · 휴지통 (늘 보인다).
ColumnLayout {
    id: lib

    property var items: []            // 보관한 PPT [{ id, name, saved_at, slides }] (backend.savedPpts)
    property string focusId: ""       // 줄의 보관함 아이콘으로 왔을 때 강조할 양식
    property string renamingId: ""
    property int sideMargin: 20
    property var dragHost: null       // 줄을 찬양 전·후 칸으로 끌어다 놓기 (EditorPage)

    signal deleteRequested(string id)
    signal renameRequested(string id, string name)
    signal filesDropped(var urls)
    signal browseRequested()

    function reveal() {
        const i = items.findIndex(x => x.id === focusId)
        if (i >= 0) list.positionViewAtIndex(i, ListView.Contain)
    }
    onFocusIdChanged: Qt.callLater(reveal)

    spacing: 10

    // 끌어다 놓거나 눌러서 보관하기
    Rectangle {
        id: dropBox
        readonly property bool lit: drop.containsDrag || dropArea.containsMouse
        Layout.fillWidth: true
        Layout.leftMargin: lib.sideMargin
        Layout.rightMargin: lib.sideMargin
        implicitHeight: 64
        radius: 12
        color: lit ? Theme.primarySoft : Theme.surface2Clear
        border.width: 1.5
        border.color: lit ? Theme.primary : Qt.rgba(Theme.text3.r, Theme.text3.g, Theme.text3.b, 0.4)
        Behavior on color { ColorAnimation { duration: Theme.fast } }
        Row {
            anchors.centerIn: parent
            spacing: 8
            Icon { glyph: "library"; size: 16; color: dropBox.lit ? Theme.primaryText : Theme.text2; anchors.verticalCenter: parent.verticalCenter }
            Text {
                text: drop.containsDrag ? "여기에 놓으면 보관해요" : "PPT 파일을 끌어다 놓거나 눌러서 보관하기"
                color: dropBox.lit ? Theme.primaryText : Theme.text2
                font.family: Theme.font
                font.pixelSize: 13
                font.weight: Font.DemiBold
                anchors.verticalCenter: parent.verticalCenter
            }
        }
        MouseArea {
            id: dropArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: lib.browseRequested()
        }
        DropArea {
            id: drop
            anchors.fill: parent
            onEntered: (drag) => { drag.accepted = drag.hasUrls }
            onDropped: (event) => {
                if (!event.hasUrls) return
                event.acceptProposedAction()
                lib.filesDropped(event.urls)
            }
        }
    }

    Text {
        visible: lib.items.length > 0
        Layout.leftMargin: lib.sideMargin + 2
        text: "보관한 양식 " + lib.items.length + "개 · 왼쪽 찬양 전·후 칸으로 끌어다 놓아 넣어요"
        color: Theme.text3
        font.family: Theme.font
        font.pixelSize: 12
    }

    // 빈 보관함
    ColumnLayout {
        visible: lib.items.length === 0
        Layout.fillWidth: true
        Layout.leftMargin: lib.sideMargin
        Layout.rightMargin: lib.sideMargin
        Layout.topMargin: 30
        spacing: 6
        Icon { Layout.alignment: Qt.AlignHCenter; glyph: "library"; size: 28; color: Theme.text3; opacity: 0.6 }
        Text {
            Layout.alignment: Qt.AlignHCenter
            text: "아직 보관한 양식이 없어요"
            color: Theme.text2
            font.family: Theme.font
            font.pixelSize: 14
            font.weight: Font.DemiBold
        }
        // 안쪽 레이아웃은 가장 넓은 항목보다 넓어지지 않는다: 폭을 채워 아래 글들이 가운데에 오게
        Item { Layout.fillWidth: true; implicitHeight: 0 }
        BalancedText {
            maxWidth: Math.min(360, parent.width)
            Layout.preferredWidth: fitWidth
            Layout.alignment: Qt.AlignHCenter
            horizontalAlignment: Text.AlignHCenter
            source: "'예배 준비중'처럼 매주 쓰는 PPT를 보관해 두면 여기서 찬양 전·후에 바로 넣을 수 있어요. 양식 줄의 보관함 아이콘을 눌러도 보관돼요."
            color: Theme.text3
            font.family: Theme.font
            font.pixelSize: 13
            lineHeight: 1.4
        }
    }
    Item { visible: lib.items.length === 0; Layout.fillHeight: true }

    ListView {
        id: list
        objectName: "formLibraryList"
        visible: lib.items.length > 0
        Layout.fillWidth: true
        Layout.fillHeight: true
        clip: true
        spacing: 4
        model: lib.items
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: ScrollBar {}
        delegate: Item {
            id: row
            required property var modelData
            readonly property bool renaming: lib.renamingId === modelData.id
            width: ListView.view.width
            height: 44

            Rectangle {
                anchors.fill: parent
                anchors.leftMargin: lib.sideMargin
                anchors.rightMargin: lib.sideMargin
                radius: 10
                color: lib.focusId === row.modelData.id ? Theme.primarySoft : hover.hovered ? Theme.surface2 : Theme.surface2Clear
                border.width: lib.focusId === row.modelData.id ? 1 : 0
                border.color: Theme.focusBorder
                Behavior on color { ColorAnimation { duration: Theme.fast } }
                HoverHandler { id: hover }
                // 끌어서 찬양 전·후 칸에 놓으면 넣는다
                SongDragArea {
                    anchors.fill: parent
                    z: -1
                    enabled: !row.renaming
                    cursorShape: dragging ? Qt.ClosedHandCursor : Qt.OpenHandCursor
                    dragHost: lib.dragHost
                    payload: ({ kind: "form", id: row.modelData.id, name: row.modelData.name })
                    dragLabel: row.modelData.name
                }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 12
                    anchors.rightMargin: 6
                    spacing: 4

                    Text {
                        visible: !row.renaming
                        Layout.fillWidth: true
                        text: row.modelData.name
                        textFormat: Text.PlainText
                        color: Theme.text
                        font.family: Theme.font
                        font.pixelSize: 13
                        font.weight: Font.DemiBold
                        elide: Text.ElideMiddle
                    }

                    // 이름 고치기 (Enter 저장, Esc 취소 — SongDrawer.handleEscape)
                    TextField {
                        id: renameField
                        visible: row.renaming
                        Layout.fillWidth: true
                        font.family: Theme.font
                        font.pixelSize: 13
                        color: Theme.text
                        selectByMouse: true
                        placeholderText: "양식 이름"
                        placeholderTextColor: Theme.text3
                        background: Rectangle { radius: 8; color: Theme.surface; border.width: 1; border.color: Theme.focusBorder }
                        onVisibleChanged: if (visible) { text = row.modelData.name; forceActiveFocus(); selectAll() }
                        Keys.onReturnPressed: { lib.renameRequested(row.modelData.id, text); lib.renamingId = "" }
                        Keys.onEnterPressed: { lib.renameRequested(row.modelData.id, text); lib.renamingId = "" }
                        Accessible.name: "양식 이름"
                        ContextMenu.menu: AppTextMenu { editor: renameField }
                    }

                    AppButton {
                        id: renameButton
                        visible: !row.renaming
                        glyph: "pencil"
                        variant: "ghost"
                        size: "small"
                        onClicked: lib.renamingId = row.modelData.id
                        Accessible.name: "이름 고치기: " + row.modelData.name
                        AppToolTip { visible: renameButton.hovered; delay: 400; text: "이름 고치기" }
                    }
                    AppButton {
                        id: deleteButton
                        visible: !row.renaming
                        glyph: "trash"
                        variant: "ghost"
                        destructive: true
                        size: "small"
                        onClicked: lib.deleteRequested(row.modelData.id)
                        Accessible.name: "보관함에서 삭제: " + row.modelData.name
                        AppToolTip { visible: deleteButton.hovered; delay: 400; text: "보관함에서 삭제" }
                    }
                }
            }
        }
    }
}
