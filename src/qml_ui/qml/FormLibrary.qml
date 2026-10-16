import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import "."

// 양식 보관함: 곡 찾기 서랍의 '양식 보관함' 화면 (예배 PPT 패널의 '양식' 제목 옆 보관함 아이콘으로 연다).
// 보관한 PPT(saved_ppts)를 찬양 전·후에 넣고, 이름을 고치고, 영구 삭제한다(빨간 휴지통 → 확인창, EditorPage).
// 위 칸에 PPT 파일을 끌어다 놓거나 눌러서 고르면 목록에 넣지 않고 보관함에만 넣는다.
// 줄 모양은 찬양 보관함(PresetLibrary)의 프리셋 줄과 같다: 이름·날짜, 마우스를 올리면 연필·휴지통.
ColumnLayout {
    id: lib

    property var items: []            // 보관한 PPT [{ id, name, saved_at, slides }] (backend.savedPpts)
    property var placed: ({})         // id → 지금 붙어 있는 곳 ('앞' | '뒤')
    property string focusId: ""       // 줄의 보관함 아이콘으로 왔을 때 강조할 양식
    property string renamingId: ""
    property int sideMargin: 20

    signal insertRequested(string id, string side)      // side: 'before' | 'after'
    signal deleteRequested(string id)
    signal renameRequested(string id, string name)
    signal filesDropped(var urls)
    signal browseRequested()

    function dateText(at) {
        const m = /^(\d+)-(\d+)-(\d+)/.exec(at || "")
        return m ? Number(m[2]) + "월 " + Number(m[3]) + "일 보관" : ""
    }
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
        text: "보관한 양식 " + lib.items.length + "개"
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
        BalancedText {
            maxWidth: parent.width
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
            readonly property string where: lib.placed[modelData.id] || ""
            readonly property bool renaming: lib.renamingId === modelData.id
            readonly property bool showTools: hover.hovered || renameButton.activeFocus || deleteButton.activeFocus
            width: ListView.view.width
            height: 52

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

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 12
                    anchors.rightMargin: 6
                    spacing: 4

                    ColumnLayout {
                        visible: !row.renaming
                        Layout.fillWidth: true
                        spacing: 2
                        Text {
                            Layout.fillWidth: true
                            text: row.modelData.name
                            textFormat: Text.PlainText
                            color: Theme.text
                            font.family: Theme.font
                            font.pixelSize: 13
                            font.weight: Font.DemiBold
                            elide: Text.ElideMiddle
                        }
                        Text {
                            Layout.fillWidth: true
                            text: lib.dateText(row.modelData.saved_at)
                                  + (row.where ? " · 찬양 " + (row.where === "앞" ? "전" : "후") + "에 있음" : "")
                            color: row.where ? Theme.primaryText : Theme.text3
                            font.family: Theme.font
                            font.pixelSize: 11
                            elide: Text.ElideRight
                        }
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
                        opacity: row.showTools ? 1 : 0
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
                        opacity: row.showTools ? 1 : 0
                        glyph: "trash"
                        variant: "ghost"
                        destructive: true
                        size: "small"
                        onClicked: lib.deleteRequested(row.modelData.id)
                        Accessible.name: "보관함에서 영구 삭제: " + row.modelData.name
                        AppToolTip { visible: deleteButton.hovered; delay: 400; text: "보관함에서 영구 삭제" }
                    }
                    // 찬양 전·후에 넣기 (이미 그쪽에 있으면 ✓)
                    Repeater {
                        model: [{ side: "before", label: "찬양 전", key: "앞" }, { side: "after", label: "찬양 후", key: "뒤" }]
                        delegate: AppButton {
                            id: putButton
                            required property var modelData
                            readonly property bool there: row.where === modelData.key
                            visible: !row.renaming
                            Layout.leftMargin: 2
                            glyph: there ? "check" : "plus"
                            text: modelData.label
                            variant: there ? "ghost" : "primary"
                            size: "small"
                            enabled: !there
                            onClicked: lib.insertRequested(row.modelData.id, modelData.side)
                            Accessible.name: row.modelData.name + " " + modelData.label + "에 넣기"
                            AppToolTip { visible: putButton.hovered; delay: 400; text: putButton.modelData.label + " 양식에 넣어요" }
                        }
                    }
                }
            }
        }
    }
}
