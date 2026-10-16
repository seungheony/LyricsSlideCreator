import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import "."

// 프리셋 저장: 이름을 정해 콘티 곡들의 지금 슬라이드를 저장한다 (EditorPage.savePresets).
// ask(titles, defaultName, onSave): titles는 저장할 곡 제목들, onSave(name)
Popup {
    id: dialog
    property var titles: []
    property var onSave: null

    function ask(songTitles, defaultName, save) {
        titles = songTitles
        onSave = save
        nameField.text = defaultName
        open()
    }

    function finish() {
        Qt.inputMethod.commit()    // 한글 조합 중인 글자를 확정한 뒤 읽는다
        const save = onSave
        const name = nameField.text.trim()
        onSave = null
        close()
        if (save) save(name)
    }

    onAboutToShow: { nameField.forceActiveFocus(); nameField.selectAll() }

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
            Layout.fillWidth: true
            text: "프리셋 저장"
            color: Theme.text
            font.family: Theme.font
            font.pixelSize: 17
            font.weight: Font.Bold
        }
        Text {
            Layout.fillWidth: true
            text: (dialog.titles.length > 1
                   ? dialog.titles.length + "곡의 지금 슬라이드를 곡마다 저장해요: "
                   : "지금 슬라이드를 저장해요: ")
                  + dialog.titles.join(", ")
                  + "\n다음에 검색 결과나 저장한 곡에서 그대로 불러올 수 있어요."
            textFormat: Text.PlainText
            color: Theme.text2
            font.family: Theme.font
            font.pixelSize: 14
            lineHeight: 1.4
            wrapMode: Text.Wrap
            maximumLineCount: 5
            elide: Text.ElideRight
        }
        Text {
            Layout.topMargin: 6
            text: "프리셋 이름"
            color: Theme.text3
            font.family: Theme.font
            font.pixelSize: 12
            font.weight: Font.DemiBold
        }
        TextField {
            id: nameField
            objectName: "presetNameField"
            Layout.fillWidth: true
            placeholderText: "예: 주일 예배, 청년부"
            placeholderTextColor: Theme.text3
            color: Theme.text
            font.family: Theme.font
            font.pixelSize: 15
            maximumLength: 60
            selectByMouse: true
            leftPadding: 12; rightPadding: 12
            implicitHeight: 42
            background: Rectangle { radius: 10; color: Theme.surface2; border.width: nameField.activeFocus ? 1.5 : 0; border.color: Theme.focusBorder }
            onAccepted: dialog.finish()
            Accessible.name: "프리셋 이름"
            ContextMenu.menu: AppTextMenu { editor: nameField }
        }
        RowLayout {
            Layout.alignment: Qt.AlignRight
            Layout.topMargin: 14
            spacing: 8
            AppButton { text: "취소"; variant: "ghost"; onClicked: dialog.close() }
            AppButton { text: "저장"; variant: "primary"; onClicked: dialog.finish() }
        }
    }
}
