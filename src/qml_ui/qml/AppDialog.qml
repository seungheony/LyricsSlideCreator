import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import "."

// 오류 안내용 모달. 자세한 내용(트레이스백)은 접어서 보여준다.
Popup {
    id: dialog
    property string title: ""
    property string message: ""
    property string detail: ""
    // 확인 옆에 둘 수 있는 두 번째 동작 (예: '직접 입력으로 열기'). 누르면 창을 닫고 handler를 부른다
    property string actionText: ""
    property var actionHandler: null

    function showError(title, detail, action) {
        dialog.actionText = action ? action.text : ""
        dialog.actionHandler = action ? action.handler : null
        const parts = title.split('\n')
        dialog.title = parts[0]
        dialog.message = parts.slice(1).join('\n')
        dialog.detail = detail || ""
        detailBox.visible = false
        open()
    }

    parent: Overlay.overlay
    anchors.centerIn: parent
    width: Math.min(420, parent.width - 32)
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
        spacing: 8
        Text {
            text: dialog.title
            color: Theme.text
            font.family: Theme.font
            font.pixelSize: 17
            font.weight: Font.Bold
            wrapMode: Text.Wrap
            Layout.fillWidth: true
        }
        Text {
            visible: dialog.message !== ""
            text: dialog.message
            color: Theme.text2
            font.family: Theme.font
            font.pixelSize: 14
            lineHeight: 1.4
            wrapMode: Text.Wrap
            Layout.fillWidth: true
        }
        Text {
            visible: dialog.detail !== ""
            text: detailBox.visible ? "▾ 자세히 보기" : "▸ 자세히 보기"
            color: Theme.text3
            font.family: Theme.font
            font.pixelSize: 12
            Layout.topMargin: 6
            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: detailBox.visible = !detailBox.visible }
        }
        ScrollView {
            id: detailBox
            visible: false
            Layout.fillWidth: true
            Layout.preferredHeight: 160
            background: Rectangle { radius: 8; color: Theme.surface2 }
            TextArea {
                text: dialog.detail
                readOnly: true
                selectByMouse: true
                wrapMode: TextEdit.Wrap
                color: Theme.text2
                font.pixelSize: 11
                background: null
            }
        }
        RowLayout {
            Layout.alignment: Qt.AlignRight
            Layout.topMargin: 14
            spacing: 8
            AppButton {
                visible: dialog.actionText !== ""
                text: dialog.actionText
                onClicked: {
                    const handler = dialog.actionHandler
                    dialog.close()
                    if (handler) handler()
                }
            }
            AppButton {
                text: "확인"
                variant: "primary"
                onClicked: dialog.close()
            }
        }
    }
}
