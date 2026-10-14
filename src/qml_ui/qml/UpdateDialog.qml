import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import "."

// 업데이트 진행 창: 확인 → 다운로드 → 설치 시작(앱 자동 종료) / 실패
Popup {
    id: dialog
    property string version: ""
    property string notes: ""
    property string page: ""
    property bool editing: false     // 편집 중인 가사가 있는지 (재시작 시 사라짐을 알림)
    property string stage: "confirm" // confirm | notes | downloading | installing | error
    property real progress: 0
    property string errorText: ""

    function openConfirm() { stage = "confirm"; open() }
    function openNotes() { stage = "notes"; open() }

    parent: Overlay.overlay
    anchors.centerIn: parent
    width: Math.min(460, parent.width - 32)
    modal: true
    focus: true
    padding: 24
    closePolicy: stage === "downloading" || stage === "installing" ? Popup.NoAutoClose
                                                                  : Popup.CloseOnEscape | Popup.CloseOnPressOutside
    Overlay.modal: Rectangle { color: Qt.rgba(0, 0, 0, 0.4) }
    enter: Transition {
        NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 200 }
        NumberAnimation { property: "scale"; from: 0.96; to: 1; duration: 250; easing.type: Easing.OutCubic }
    }
    exit: Transition { NumberAnimation { property: "opacity"; to: 0; duration: 150 } }
    background: Rectangle { radius: 18; color: Theme.surface }

    Connections {
        target: backend
        function onUpdateProgress(p) { dialog.progress = p }
        function onUpdateFailed(msg) { dialog.errorText = msg; dialog.stage = "error" }
        function onUpdateReady() { dialog.stage = "installing"; quitTimer.start() }
    }
    // 설치가 시작되면 앱을 닫는다 (Windows: 설치 프로그램이, macOS: 교체 스크립트가 다시 실행해준다)
    Timer { id: quitTimer; interval: 1200; onTriggered: Qt.quit() }

    contentItem: ColumnLayout {
        spacing: 10

        Text {
            Layout.fillWidth: true
            text: dialog.stage === "notes" ? "v" + dialog.version + " 변경 내용"
                : dialog.stage === "downloading" ? "업데이트 받는 중…"
                : dialog.stage === "installing" ? "업데이트를 설치합니다"
                : dialog.stage === "error" ? "업데이트하지 못했어요"
                : "v" + dialog.version + "으로 업데이트할까요?"
            color: Theme.text
            font.family: Theme.font
            font.pixelSize: 17
            font.weight: Font.Bold
            wrapMode: Text.Wrap
        }

        // 변경 내용 (릴리스 노트, 마크다운)
        ScrollView {
            visible: (dialog.stage === "confirm" || dialog.stage === "notes") && dialog.notes !== ""
            Layout.fillWidth: true
            Layout.preferredHeight: Math.min(notesText.implicitHeight + 24, 240)
            background: Rectangle { radius: 10; color: Theme.surface2 }
            Text {
                id: notesText
                width: dialog.availableWidth - 24
                x: 12; y: 12
                text: dialog.notes
                textFormat: Text.MarkdownText
                wrapMode: Text.Wrap
                color: Theme.text2
                font.family: Theme.font
                font.pixelSize: 13
                onLinkActivated: (link) => Qt.openUrlExternally(link)
            }
        }

        Text {
            visible: dialog.stage === "confirm"
            Layout.fillWidth: true
            text: dialog.editing ? "앱이 다시 시작되며, 지금 편집 중인 가사는 저장되지 않아요."
                                 : "받은 뒤 자동으로 설치하고 앱을 다시 시작해요."
            color: dialog.editing ? Theme.danger : Theme.text3
            font.family: Theme.font
            font.pixelSize: 13
            wrapMode: Text.Wrap
        }

        // 진행률
        ColumnLayout {
            visible: dialog.stage === "downloading" || dialog.stage === "installing"
            Layout.fillWidth: true
            spacing: 6
            Rectangle {
                Layout.fillWidth: true
                height: 8
                radius: 4
                color: Theme.surface2
                Rectangle {
                    width: parent.width * (dialog.stage === "installing" ? 1 : dialog.progress)
                    height: parent.height
                    radius: 4
                    color: Theme.primary
                    Behavior on width { NumberAnimation { duration: 150 } }
                }
            }
            Text {
                text: dialog.stage === "installing" ? "잠시 후 앱이 다시 시작됩니다"
                                                    : Math.round(dialog.progress * 100) + "%"
                color: Theme.text3
                font.family: Theme.font
                font.pixelSize: 12
            }
        }

        Text {
            visible: dialog.stage === "error"
            Layout.fillWidth: true
            text: dialog.errorText
            color: Theme.text2
            font.family: Theme.font
            font.pixelSize: 13
            wrapMode: Text.Wrap
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: 8
            visible: dialog.stage !== "downloading" && dialog.stage !== "installing"
            spacing: 8
            AppButton {
                visible: dialog.stage === "error"
                text: "릴리스 페이지 열기"
                variant: "ghost"
                onClicked: Qt.openUrlExternally(dialog.page)
            }
            Item { Layout.fillWidth: true }
            AppButton {
                text: dialog.stage === "confirm" ? "나중에" : "닫기"
                variant: dialog.stage === "confirm" ? "ghost" : "secondary"
                onClicked: dialog.close()
            }
            AppButton {
                visible: dialog.stage === "confirm" || dialog.stage === "notes"
                text: "업데이트"
                variant: "primary"
                onClicked: {
                    // '변경 내용'에서 눌러도 편집 중 경고가 있는 확인 단계를 거친다
                    if (dialog.stage === "notes") { dialog.stage = "confirm"; return }
                    dialog.progress = 0
                    dialog.stage = "downloading"
                    backend.startUpdate()
                }
            }
        }
    }
}
