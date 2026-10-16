import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import "."

// 오류 안내용 모달. 자세한 내용(트레이스백)은 접어 두고, 마지막 오류 줄만 요약으로 보여 준다.
// showError(제목\n안내, 자세한 내용, 두 번째 동작 { text, handler }, 다시 시도 { handler })
Popup {
    id: dialog
    property string title: ""
    property string message: ""
    property string detail: ""
    // 확인 옆에 둘 수 있는 두 번째 동작 (예: '직접 입력으로 열기'). 누르면 창을 닫고 handler를 부른다
    property string actionText: ""
    property var actionHandler: null
    // 다시 시도할 수 있는 오류(곡 불러오기 실패 등)면 '다시 시도'를 둔다. 누르면 창을 닫고 handler를 부른다
    property var retryHandler: null
    property bool copied: false
    // 자세한 내용의 마지막 줄 (트레이스백이면 예외 줄). 사용자 폴더 경로가 든 긴 내용을 열지 않아도 원인을 알 수 있다
    readonly property string summary: {
        const lines = dialog.detail.split("\n").map(s => s.trim()).filter(s => s !== "")
        return lines.length ? lines[lines.length - 1] : ""
    }

    function showError(title, detail, action, retry) {
        dialog.actionText = action ? action.text : ""
        dialog.actionHandler = action ? action.handler : null
        dialog.retryHandler = retry ? retry.handler : null
        dialog.copied = false
        const parts = title.split('\n')
        dialog.title = parts[0]
        dialog.message = parts.slice(1).join('\n')
        dialog.detail = detail || ""
        detailBox.visible = false
        open()
    }

    // 다시 열 때 지난번에 포커스했던 버튼이 남아 있으면 Enter가 그 버튼을 누른다: 내용 전체로 되돌린다
    onAboutToShow: contentItem.forceActiveFocus()

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
        focus: true
        Keys.onReturnPressed: dialog.close()
        Keys.onEnterPressed: dialog.close()
        BalancedText {
            maxWidth: parent.width
            Layout.preferredWidth: fitWidth
            source: dialog.title
            color: Theme.text
            font.family: Theme.font
            font.pixelSize: 17
            font.weight: Font.Bold
        }
        BalancedText {
            maxWidth: parent.width
            Layout.preferredWidth: fitWidth
            visible: dialog.message !== ""
            source: dialog.message
            color: Theme.text2
            font.family: Theme.font
            font.pixelSize: 14
            lineHeight: 1.4
        }
        // 오류 요약과 안내 (예외로 실패했을 때)
        Text {
            visible: dialog.summary !== ""
            text: dialog.summary
            textFormat: Text.PlainText
            color: Theme.text3
            font.family: Theme.font
            font.pixelSize: 12
            wrapMode: Text.Wrap
            maximumLineCount: 3
            elide: Text.ElideRight
            Layout.topMargin: 4
            Layout.fillWidth: true
        }
        BalancedText {
            maxWidth: parent.width
            Layout.preferredWidth: fitWidth
            visible: dialog.detail !== ""
            source: "계속되면 '문제 알리기'로 알려 주세요. 오류 정보를 복사해 두니 붙여 넣기만 하면 돼요."
            color: Theme.text3
            font.family: Theme.font
            font.pixelSize: 12
        }
        RowLayout {
            visible: dialog.detail !== ""
            Layout.topMargin: 2
            spacing: 6
            AppButton {
                text: detailBox.visible ? "자세히 보기 ▾" : "자세히 보기 ▸"
                variant: "ghost"; size: "small"
                onClicked: detailBox.visible = !detailBox.visible
            }
            AppButton {
                text: dialog.copied ? "복사했어요" : "오류 정보 복사"
                glyph: dialog.copied ? "check" : ""
                variant: "ghost"; size: "small"
                onClicked: {
                    backend.copyErrorReport(dialog.title, dialog.detail)
                    dialog.copied = true
                    copiedTimer.restart()
                }
            }
            // 오류 정보를 복사하고 GitHub 문의 화면을 연다
            AppButton {
                text: "문제 알리기"
                variant: "ghost"; size: "small"
                onClicked: {
                    backend.copyErrorReport(dialog.title, dialog.detail)
                    dialog.copied = true
                    copiedTimer.restart()
                    Qt.openUrlExternally(backend.feedbackUrl())
                }
            }
        }
        Timer { id: copiedTimer; interval: 2000; onTriggered: dialog.copied = false }
        ScrollView {
            id: detailBox
            visible: false
            Layout.fillWidth: true
            Layout.preferredHeight: 160
            background: Rectangle { radius: 8; color: Theme.surface2 }
            TextArea {
                id: detailText
                text: dialog.detail
                readOnly: true
                ContextMenu.menu: AppTextMenu { editor: detailText }
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
                visible: dialog.retryHandler !== null
                text: "다시 시도"
                onClicked: {
                    const handler = dialog.retryHandler
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
