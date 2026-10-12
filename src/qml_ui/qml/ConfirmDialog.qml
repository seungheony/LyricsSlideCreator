import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import "."

// 두 가지 중 하나를 고르는 확인창.
// ask({ title, message, confirmText, cancelText, onConfirm, onCancel })
Popup {
    id: dialog
    property string title: ""
    property string message: ""
    property string confirmText: "확인"
    property string cancelText: "취소"
    property var onConfirm: null
    property var onCancel: null

    function ask(opts) {
        title = opts.title || ""
        message = opts.message || ""
        confirmText = opts.confirmText || "확인"
        cancelText = opts.cancelText || "취소"
        onConfirm = opts.onConfirm || null
        onCancel = opts.onCancel || null
        open()
    }

    function finish(confirmed) {
        const cb = confirmed ? onConfirm : onCancel
        onConfirm = null
        onCancel = null
        close()
        if (cb) cb()
    }

    parent: Overlay.overlay
    anchors.centerIn: parent
    width: Math.min(420, parent.width - 32)
    modal: true
    focus: true
    padding: 24
    closePolicy: Popup.NoAutoClose   // 바깥 클릭·Esc는 아래에서 '취소'로 처리

    Overlay.modal: Rectangle {
        color: Qt.rgba(0, 0, 0, 0.4)
        MouseArea { anchors.fill: parent; onClicked: dialog.finish(false) }
    }

    enter: Transition {
        NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 200 }
        NumberAnimation { property: "scale"; from: 0.96; to: 1; duration: 250; easing.type: Easing.OutCubic }
    }
    exit: Transition { NumberAnimation { property: "opacity"; to: 0; duration: 150 } }

    background: Rectangle { radius: 18; color: Theme.surface }

    contentItem: ColumnLayout {
        spacing: 8
        Keys.onEscapePressed: dialog.finish(false)
        Keys.onReturnPressed: dialog.finish(true)
        focus: true

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
        RowLayout {
            Layout.alignment: Qt.AlignRight
            Layout.topMargin: 14
            spacing: 8
            AppButton { text: dialog.cancelText; variant: "ghost"; onClicked: dialog.finish(false) }
            AppButton { text: dialog.confirmText; variant: "primary"; onClicked: dialog.finish(true) }
        }
    }
}
