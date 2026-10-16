import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import "."

// 프리셋 저장: 이름을 정해 콘티 곡들의 지금 슬라이드를 저장한다 (EditorPage.savePresets).
// ask(titles, defaultName, onSave, opts): titles는 저장할 곡 제목들, onSave(name, indexes) — indexes: 저장할 곡(titles의 번호)
// opts.selectable: 곡마다 체크박스로 고른다(처음엔 모두 켜짐, 창을 닫을 때 EditorPage.askSaveBeforeClose).
//   opts.heading·confirmText·skipText, opts.onSkip: '저장하지 않고 …' 버튼 (Esc·바깥 클릭은 아무것도 하지 않고 닫힘)
Popup {
    id: dialog
    property var titles: []
    property var onSave: null
    property bool selectable: false
    property var checked: []          // selectable일 때 곡마다 저장할지
    property string heading: "프리셋 저장"
    property string confirmText: "저장"
    property string skipText: ""
    property var onSkip: null
    readonly property int checkedCount: checked.filter(Boolean).length

    function ask(songTitles, defaultName, save, opts) {
        const o = opts || {}
        titles = songTitles
        onSave = save
        selectable = o.selectable === true
        checked = songTitles.map(() => true)
        heading = o.heading || "프리셋 저장"
        confirmText = o.confirmText || "저장"
        skipText = o.skipText || ""
        onSkip = o.onSkip || null
        nameField.text = defaultName
        open()
    }

    function setChecked(i, on) {
        const next = checked.slice()
        next[i] = on
        checked = next
    }

    function finish() {
        if (selectable && !checkedCount) return
        Qt.inputMethod.commit()    // 한글 조합 중인 글자를 확정한 뒤 읽는다
        const save = onSave
        const name = nameField.text.trim()
        const indexes = titles.map((t, i) => i).filter(i => !selectable || checked[i])
        onSave = null
        onSkip = null
        close()
        if (save) save(name, indexes)
    }

    function skip() {
        const cb = onSkip
        onSave = null
        onSkip = null
        close()
        if (cb) cb()
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
            text: dialog.heading
            color: Theme.text
            font.family: Theme.font
            font.pixelSize: 17
            font.weight: Font.Bold
        }
        BalancedText {
            visible: !dialog.selectable
            maxWidth: parent.width
            Layout.preferredWidth: fitWidth
            source: (dialog.titles.length > 1
                   ? dialog.titles.length + "곡의 지금 슬라이드를 곡마다 저장해요: "
                   : "지금 슬라이드를 저장해요: ")
                  + dialog.titles.join(", ")
                  + "\n다음에 검색 결과나 보관함에서 그대로 불러올 수 있어요."
            textFormat: Text.PlainText
            color: Theme.text2
            font.family: Theme.font
            font.pixelSize: 14
            lineHeight: 1.4
            maximumLineCount: 5
            elide: Text.ElideRight
        }
        // 곡마다 고르기 (창을 닫을 때)
        BalancedText {
            visible: dialog.selectable
            maxWidth: parent.width
            Layout.preferredWidth: fitWidth
            source: "프리셋으로 저장하지 않은 곡이 있어요. 저장할 곡을 골라 주세요. 다음에 보관함에서 그대로 불러올 수 있어요."
            textFormat: Text.PlainText
            color: Theme.text2
            font.family: Theme.font
            font.pixelSize: 14
            lineHeight: 1.4
        }
        ColumnLayout {
            visible: dialog.selectable
            Layout.fillWidth: true
            Layout.topMargin: 4
            spacing: 0
            Repeater {
                model: dialog.selectable ? dialog.titles : []
                delegate: CheckBox {
                    id: songBox
                    required property int index
                    required property string modelData
                    objectName: "presetSaveCheck"
                    Layout.fillWidth: true
                    text: modelData
                    checked: dialog.checked[index] === true
                    onToggled: dialog.setChecked(index, checked)
                    hoverEnabled: true
                    spacing: 8
                    padding: 6
                    indicator: Rectangle {
                        x: songBox.leftPadding
                        anchors.verticalCenter: parent.verticalCenter
                        width: 18; height: 18; radius: 5
                        color: songBox.checked ? Theme.primary : Theme.surface
                        border.width: songBox.checked ? 0 : 1.5
                        border.color: songBox.hovered || songBox.visualFocus ? Theme.primary : Theme.border
                        Rectangle {
                            anchors.fill: parent
                            anchors.margins: -3
                            radius: 8
                            color: "transparent"
                            border.width: 2
                            border.color: Theme.primary
                            visible: songBox.visualFocus
                        }
                        Icon { anchors.centerIn: parent; visible: songBox.checked; glyph: "check"; size: 12; color: "white" }
                    }
                    contentItem: Text {
                        leftPadding: songBox.indicator.width + songBox.spacing
                        text: songBox.text
                        textFormat: Text.PlainText
                        color: songBox.checked ? Theme.text : Theme.text3
                        font.family: Theme.font
                        font.pixelSize: 14
                        font.weight: Font.DemiBold
                        elide: Text.ElideRight
                        verticalAlignment: Text.AlignVCenter
                    }
                }
            }
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
            AppButton { text: dialog.skipText || "취소"; variant: "ghost"; onClicked: dialog.skip() }
            AppButton {
                text: dialog.confirmText
                variant: "primary"
                enabled: !dialog.selectable || dialog.checkedCount > 0
                onClicked: dialog.finish()
            }
        }
    }
}
