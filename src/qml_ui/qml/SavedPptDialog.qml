import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import "."

// 보관한 PPT 관리: 앱에 보관한 앞·뒤 PPT를 보고 지운다 ('양식 추가' 메뉴의 '보관한 PPT 관리…').
// 휴지통을 누르면 확인창으로 한 번 더 묻고 지운다. 지우면 찬양 전·후 양식에서도 빠진다(EditorPage.deleteSavedPpt).
Popup {
    id: dialog
    property var items: []            // backend.savedPpts()
    property var placed: ({})         // id → '앞' | '뒤'

    signal deleteRequested(string id)

    onAboutToShow: contentItem.forceActiveFocus()

    parent: Overlay.overlay
    anchors.centerIn: parent
    width: Math.min(440, parent.width - 32)
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

    function savedDate(at) {
        const m = /^(\d+)-(\d+)-(\d+)/.exec(at || "")
        return m ? Number(m[2]) + "월 " + Number(m[3]) + "일 보관" : ""
    }

    contentItem: ColumnLayout {
        spacing: 8
        Keys.onEscapePressed: dialog.close()

        Text {
            Layout.fillWidth: true
            text: "보관한 PPT"
            color: Theme.text
            font.family: Theme.font
            font.pixelSize: 17
            font.weight: Font.Bold
        }
        Text {
            Layout.fillWidth: true
            text: "보관한 때의 파일 그대로 붙여요. 원본을 고쳤으면 그 파일을 다시 넣고 보관하면 바뀌어요."
            color: Theme.text2
            font.family: Theme.font
            font.pixelSize: 13
            wrapMode: Text.Wrap
            lineHeight: 1.3
        }

        Text {
            visible: dialog.items.length === 0
            Layout.fillWidth: true
            Layout.topMargin: 12
            Layout.bottomMargin: 12
            horizontalAlignment: Text.AlignHCenter
            text: "보관한 PPT가 없어요"
            color: Theme.text3
            font.family: Theme.font
            font.pixelSize: 13
        }

        ListView {
            id: list
            visible: dialog.items.length > 0
            Layout.fillWidth: true
            Layout.topMargin: 6
            Layout.preferredHeight: Math.min(contentHeight, 300)
            clip: true
            spacing: 4
            model: dialog.items
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollBar {}
            delegate: Rectangle {
                id: entry
                required property var modelData
                readonly property string where: dialog.placed[modelData.id] || ""
                width: ListView.view.width
                height: 50
                radius: Theme.radiusSm
                color: hover.hovered ? Theme.surface2 : Theme.surface2Clear
                HoverHandler { id: hover }
                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 12
                    anchors.rightMargin: 6
                    spacing: 8
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2
                        Text {
                            Layout.fillWidth: true
                            text: entry.modelData.name
                            textFormat: Text.PlainText
                            color: Theme.text
                            font.family: Theme.font
                            font.pixelSize: 13
                            font.weight: Font.DemiBold
                            elide: Text.ElideMiddle
                        }
                        Text {
                            Layout.fillWidth: true
                            text: dialog.savedDate(entry.modelData.saved_at)
                                  + (entry.where ? " · " + entry.where + "에 붙임" : "")
                            color: Theme.text3
                            font.family: Theme.font
                            font.pixelSize: 12
                            elide: Text.ElideRight
                        }
                    }
                    AppButton {
                        id: deleteButton
                        glyph: "trash"
                        variant: "ghost"
                        size: "small"
                        onClicked: dialog.deleteRequested(entry.modelData.id)
                        Accessible.name: "'" + entry.modelData.name + "' 보관함에서 지우기"
                        AppToolTip {
                            visible: deleteButton.hovered
                            text: entry.where ? "보관한 PPT를 지워요 (" + entry.where + "에 붙인 것도 빠져요)" : "보관한 PPT를 지워요"
                        }
                    }
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: 10
            Item { Layout.fillWidth: true }
            AppButton {
                text: "닫기"
                onClicked: dialog.close()
            }
        }
    }
}
