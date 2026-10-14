import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import "."

// 업데이트 진행 창: 확인 → 다운로드(취소 가능) → 설치 시작(앱 자동 종료) / 실패(다시 시도)
Popup {
    id: dialog
    property string version: ""
    property string notes: ""        // StyledText HTML (backend가 릴리스 노트에서 보여 줄 부분만 골라 바꿈)
    property string page: ""
    property bool editing: false     // 편집 중인 가사가 있는지 (재시작 시 사라짐을 알림)
    property string stage: "confirm" // confirm | notes | downloading | cancelling | installing | error
    property real progress: 0
    property string errorText: ""
    property string errorDetail: ""
    readonly property bool busy: stage === "downloading" || stage === "cancelling" || stage === "installing"

    function openConfirm() { stage = "confirm"; notesScroll.contentItem.contentY = 0; open() }
    function openNotes() { stage = "notes"; notesScroll.contentItem.contentY = 0; open() }
    function startDownload() {
        progress = 0
        detailBox.visible = false
        stage = "downloading"
        backend.startUpdate()
    }

    parent: Overlay.overlay
    anchors.centerIn: parent
    width: Math.min(460, parent.width - 32)
    modal: true
    focus: true
    padding: 24
    closePolicy: busy ? Popup.NoAutoClose : Popup.CloseOnEscape | Popup.CloseOnPressOutside
    Overlay.modal: Rectangle { color: Qt.rgba(0, 0, 0, 0.4) }
    enter: Transition {
        NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 200 }
        NumberAnimation { property: "scale"; from: 0.96; to: 1; duration: 250; easing.type: Easing.OutCubic }
    }
    exit: Transition { NumberAnimation { property: "opacity"; to: 0; duration: 150 } }
    background: Rectangle { radius: 18; color: Theme.surface }

    Connections {
        target: backend
        function onUpdateProgress(p) { if (dialog.stage === "downloading") dialog.progress = p }
        function onUpdateFailed(json) {
            const e = JSON.parse(json)
            dialog.errorText = e.message
            dialog.errorDetail = e.detail || ""
            dialog.stage = "error"
        }
        function onUpdateCancelled() { dialog.close() }
        function onUpdateReady() { dialog.stage = "installing"; quitTimer.start() }
    }
    // 설치가 시작되면 앱을 닫는다 (Windows: 설치 프로그램이, macOS: 교체 스크립트가 다시 실행해준다)
    Timer { id: quitTimer; interval: 1200; onTriggered: Qt.quit() }

    contentItem: ColumnLayout {
        spacing: 10

        Text {
            Layout.fillWidth: true
            // 버전 뒤에 조사를 바로 붙이지 않는다 ('v1.2.1 버전으로')
            text: dialog.stage === "notes" ? "v" + dialog.version + " 변경 내용"
                : dialog.stage === "downloading" ? "업데이트 받는 중…"
                : dialog.stage === "cancelling" ? "취소하는 중…"
                : dialog.stage === "installing" ? "업데이트를 설치하고 있어요"
                : dialog.stage === "error" ? "업데이트하지 못했어요"
                : "v" + dialog.version + " 버전으로 업데이트할까요?"
            color: Theme.text
            font.family: Theme.font
            font.pixelSize: 17
            font.weight: Font.Bold
            wrapMode: Text.Wrap
        }

        // 변경 내용. QML의 MarkdownText는 linkColor를 무시하므로 StyledText로 보여 준다
        ScrollView {
            id: notesScroll
            visible: (dialog.stage === "confirm" || dialog.stage === "notes") && dialog.notes !== ""
            Layout.fillWidth: true
            Layout.preferredHeight: Math.min(notesText.implicitHeight + 24, 240)
            contentWidth: availableWidth
            contentHeight: notesText.implicitHeight + 24    // 위아래 여백까지 넣어야 맨 아래 줄이 잘리지 않는다
            background: Rectangle { radius: 10; color: Theme.surface2 }
            Text {
                id: notesText
                x: 12; y: 12
                width: notesScroll.availableWidth - 24
                text: dialog.notes
                textFormat: Text.StyledText
                linkColor: Theme.primaryText
                wrapMode: Text.Wrap
                color: Theme.text2
                font.family: Theme.font
                font.pixelSize: 13
                lineHeight: 1.3
                onLinkActivated: (link) => Qt.openUrlExternally(link)
                HoverHandler { cursorShape: parent.hoveredLink ? Qt.PointingHandCursor : Qt.ArrowCursor }
            }
        }
        Text {
            visible: (dialog.stage === "confirm" || dialog.stage === "notes") && dialog.notes === ""
            Layout.fillWidth: true
            text: "변경 내용은 <a href=\"" + dialog.page + "\">릴리스 페이지</a>에서 확인할 수 있어요."
            textFormat: Text.StyledText
            linkColor: Theme.primaryText
            wrapMode: Text.Wrap
            color: Theme.text2
            font.family: Theme.font
            font.pixelSize: 13
            onLinkActivated: (link) => Qt.openUrlExternally(link)
            HoverHandler { cursorShape: parent.hoveredLink ? Qt.PointingHandCursor : Qt.ArrowCursor }
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
            visible: dialog.busy
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
                    color: dialog.stage === "cancelling" ? Theme.text3 : Theme.primary
                    Behavior on width { NumberAnimation { duration: 150 } }
                }
            }
            Text {
                text: dialog.stage === "installing" ? "잠시 후 앱이 다시 시작돼요"
                    : dialog.stage === "cancelling" ? "받던 파일을 지우고 있어요"
                    : Math.round(dialog.progress * 100) + "%"
                color: Theme.text3
                font.family: Theme.font
                font.pixelSize: 12
            }
        }

        // 실패: 사용자용 안내 + 접힌 기술 원문
        Text {
            visible: dialog.stage === "error"
            Layout.fillWidth: true
            text: dialog.errorText
            color: Theme.text2
            font.family: Theme.font
            font.pixelSize: 13
            lineHeight: 1.4
            wrapMode: Text.Wrap
        }
        AppButton {
            visible: dialog.stage === "error" && dialog.errorDetail !== ""
            text: detailBox.visible ? "자세히 ▾" : "자세히 ▸"
            variant: "ghost"; size: "small"
            onClicked: detailBox.visible = !detailBox.visible
        }
        ScrollView {
            id: detailBox
            visible: false
            Layout.fillWidth: true
            Layout.preferredHeight: 140
            background: Rectangle { radius: 8; color: Theme.surface2 }
            TextArea {
                id: detailText
                text: dialog.errorDetail
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
            Layout.fillWidth: true
            Layout.topMargin: 8
            visible: dialog.stage !== "installing"
            spacing: 8
            AppButton {
                visible: dialog.stage === "error"
                text: "릴리스 페이지"
                variant: "ghost"
                onClicked: Qt.openUrlExternally(dialog.page)
            }
            Item { Layout.fillWidth: true }
            AppButton {
                visible: !dialog.busy
                text: dialog.stage === "confirm" ? "나중에" : "닫기"
                variant: dialog.stage === "confirm" ? "ghost" : "secondary"
                onClicked: dialog.close()
            }
            AppButton {
                visible: dialog.stage === "downloading" || dialog.stage === "cancelling"
                enabled: dialog.stage === "downloading"
                text: "취소"
                variant: "secondary"
                onClicked: {
                    dialog.stage = "cancelling"
                    backend.cancelUpdate()
                }
            }
            AppButton {
                visible: dialog.stage === "confirm" || dialog.stage === "notes" || dialog.stage === "error"
                text: dialog.stage === "error" ? "다시 시도" : "업데이트"
                variant: "primary"
                onClicked: {
                    // '변경 내용'에서 눌러도 편집 중 경고가 있는 확인 단계를 거친다
                    if (dialog.stage === "notes") { dialog.stage = "confirm"; return }
                    dialog.startDownload()
                }
            }
        }
    }
}
