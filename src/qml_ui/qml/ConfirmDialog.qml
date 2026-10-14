import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import "."

// 두 가지 중 하나를 고르는 확인창.
// ask({ title, message, confirmText, cancelText, onConfirm, onCancel, onDismiss })
// onDismiss: Esc·바깥 클릭으로 닫을 때. 없으면 '취소'와 같다
// 이미 떠 있으면(열리거나 닫히는 중 포함) 덮어쓰지 않고 차례를 기다린다.
Popup {
    id: dialog
    property string title: ""
    property string message: ""
    property string confirmText: "확인"
    property string cancelText: "취소"
    property var onConfirm: null
    property var onCancel: null
    property var onDismiss: null
    property bool hasDismiss: false
    property var queue: []

    function ask(opts) {
        if (visible) { queue = queue.concat([opts]); return }
        show(opts)
    }

    onClosed: {
        if (!queue.length) return
        const next = queue[0]
        queue = queue.slice(1)
        show(next)
    }

    function show(opts) {
        title = opts.title || ""
        message = opts.message || ""
        confirmText = opts.confirmText || "확인"
        cancelText = opts.cancelText || "취소"
        onConfirm = opts.onConfirm || null
        onCancel = opts.onCancel || null
        hasDismiss = opts.onDismiss !== undefined
        onDismiss = opts.onDismiss || null
        open()
    }

    function finish(confirmed) {
        const cb = confirmed ? onConfirm : onCancel
        onConfirm = null
        onCancel = null
        onDismiss = null
        close()
        if (cb) cb()
    }

    // Esc·바깥 클릭: onDismiss가 있으면 그것만(없어도 아무 일 없음), 지정하지 않았으면 '취소'
    function dismiss() {
        if (!hasDismiss) { finish(false); return }
        const cb = onDismiss
        onConfirm = null
        onCancel = null
        onDismiss = null
        close()
        if (cb) cb()
    }

    // 다시 열 때 지난번에 포커스했던 버튼이 남아 있으면 Enter가 그 버튼을 누른다: 내용 전체로 되돌린다
    onAboutToShow: contentItem.forceActiveFocus()

    parent: Overlay.overlay
    anchors.centerIn: parent
    width: Math.min(420, parent.width - 32)
    modal: true
    focus: true
    padding: 24
    closePolicy: Popup.NoAutoClose   // 바깥 클릭·Esc는 아래에서 '취소'로 처리

    Overlay.modal: Rectangle {
        color: Qt.rgba(0, 0, 0, 0.4)
        MouseArea { anchors.fill: parent; onClicked: dialog.dismiss() }
    }

    enter: Transition {
        NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 200 }
        NumberAnimation { property: "scale"; from: 0.96; to: 1; duration: 250; easing.type: Easing.OutCubic }
    }
    exit: Transition { NumberAnimation { property: "opacity"; to: 0; duration: 150 } }

    background: Rectangle { radius: 18; color: Theme.surface }

    contentItem: ColumnLayout {
        spacing: 8
        Keys.onEscapePressed: dialog.dismiss()
        Keys.onReturnPressed: dialog.finish(true)
        Keys.onEnterPressed: dialog.finish(true)
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
