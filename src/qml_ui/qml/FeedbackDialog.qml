import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import "."

// '문의하기': 오류·불편한 점·기능 요청을 GitHub 이슈 하나(feedback.yml, 종류는 양식에서 고름)로 받는다. 앱은 안내만 하고 브라우저로 이슈 작성 화면을 연다
// (앱에 GitHub 토큰을 넣지 않기 위함. 쓰는 사람에게 GitHub 계정이 필요하다)
Popup {
    id: dialog

    function openForm() {
        Qt.openUrlExternally(backend.feedbackUrl())
        dialog.close()
    }

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

    contentItem: ColumnLayout {
        spacing: 10
        focus: true
        Keys.onReturnPressed: dialog.openForm()
        Keys.onEnterPressed: dialog.openForm()

        Text {
            Layout.fillWidth: true
            text: "무엇이든 편하게 알려 주세요"
            color: Theme.text
            font.family: Theme.font
            font.pixelSize: 17
            font.weight: Font.Bold
        }
        Text {
            Layout.fillWidth: true
            text: "잘 안 되는 기능, 불편한 점, 있었으면 하는 기능 모두 좋아요.\n작은 것이라도 앱을 고치는 데 큰 도움이 돼요."
            color: Theme.text2
            font.family: Theme.font
            font.pixelSize: 14
            lineHeight: 1.4
            wrapMode: Text.Wrap
        }

        // 안내
        Rectangle {
            Layout.fillWidth: true
            Layout.topMargin: 4
            radius: 10
            color: Theme.surface2
            implicitHeight: notes.implicitHeight + 24
            Text {
                id: notes
                x: 12; y: 12
                width: parent.width - 24
                text: "· 브라우저에서 GitHub 작성 화면이 열려요. GitHub 계정이 있어야 해요 (무료).\n"
                    + "· 올린 글은 누구나 볼 수 있어요. 이름·연락처 같은 개인정보는 쓰지 마세요.\n"
                    + "· 오류가 났다면 오류 창의 '오류 정보 복사'나 '문제 알리기'로 복사한 내용을 붙여 넣어 주세요."
                color: Theme.text2
                font.family: Theme.font
                font.pixelSize: 12
                lineHeight: 1.45
                wrapMode: Text.Wrap
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: 8
            spacing: 8
            Item { Layout.fillWidth: true }
            AppButton {
                text: "닫기"
                variant: "ghost"
                onClicked: dialog.close()
            }
            AppButton {
                text: "GitHub에서 글 쓰기"
                variant: "primary"
                onClicked: dialog.openForm()
            }
        }
    }
}
