import QtQuick
import QtQuick.Layouts
import "."

// 곡별 설정 고르기 목록 (PresetPicker의 팝업): '멜론 가사 그대로'(멜론 곡만) · 프리셋들. 지금 설정에 ✓.
// 줄을 누르면 그 곡의 설정으로 정한다(backend.setPresetChoice, 다시 켜도 남음). 담기는 설정대로 한다(행·카드를 누르거나 끌어다 놓기).
// 프리셋 줄에는 연필(이름 고치기, Enter 저장·Esc 취소)·휴지통(두 번 눌러 삭제)이 늘 보인다
ColumnLayout {
    id: choices
    property var song: null           // { song_id, ... }
    property var presets: []          // 설정된 프리셋(default: true)이 맨 앞 (backend presetsFor·allPresets)
    property bool melon: true         // '멜론 가사 그대로' 줄 (직접 입력한 곡은 없음)
    property string renamingId: ""
    property string deletingId: ""
    readonly property bool melonSelected: !presets.some(p => p.default === true)
    signal chosen()

    spacing: 2

    function choose(value) {
        renamingId = ""
        deletingId = ""
        backend.setPresetChoice(song.song_id, value)
        chosen()
    }
    function finishRename(preset, name) {
        renamingId = ""
        if (name.trim() !== (preset.name || "")) backend.renamePreset(preset.id, name.trim())
    }
    function remove(preset) {
        renamingId = ""
        if (deletingId !== preset.id) { deletingId = preset.id; return }
        deletingId = ""
        backend.deletePreset(preset.id)
    }
    function labelOf(p) {
        if (p.name) return p.name
        const m = /^(\d{4})-(\d{2})-(\d{2})/.exec(p.saved_at || "")
        return m ? Number(m[2]) + "월 " + Number(m[3]) + "일 저장" : "프리셋"
    }
    function dateOf(p) {
        const m = /^(\d{4})-(\d{2})-(\d{2})/.exec(p.saved_at || "")
        if (!m) return ""
        return (Number(m[1]) === new Date().getFullYear() ? "" : m[1] + "년 ") + Number(m[2]) + "월 " + Number(m[3]) + "일"
    }

    // 한 줄: ✓ · 이름 · 날짜 (누르면 설정)
    component ChoiceRow: Rectangle {
        id: line
        property bool selected: false
        property string label: ""
        property string date: ""
        property bool strong: false
        default property alias tools: toolRow.data
        signal pressed()
        Layout.fillWidth: true
        implicitHeight: 36
        radius: 8
        // 지금 설정: 옅은 회색 바탕 + 회색 ✓ (초록은 눈에 너무 띄어서 쓰지 않는다)
        color: lineHover.hovered || lineArea.activeFocus ? Theme.surface2
             : line.selected ? Qt.rgba(Theme.surface2.r, Theme.surface2.g, Theme.surface2.b, 0.6) : "transparent"
        HoverHandler { id: lineHover }
        Item {
            id: lineArea
            anchors.fill: parent
            activeFocusOnTab: true
            Keys.onReturnPressed: line.pressed()
            Keys.onEnterPressed: line.pressed()
            Keys.onSpacePressed: line.pressed()
            Accessible.role: Accessible.Button
            Accessible.name: line.label + (line.selected ? ", 지금 설정" : "")
            Accessible.onPressAction: line.pressed()
            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: line.pressed() }
        }
        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 8
            anchors.rightMargin: 4
            spacing: 8
            Item {
                implicitWidth: 14
                implicitHeight: 14
                Icon { anchors.centerIn: parent; visible: line.selected; glyph: "check"; size: 14; color: Theme.text2 }
            }
            // 이름 · 날짜: 이름이 길면 이름을 줄이고 날짜는 늘 이름 바로 뒤에 (버튼 자리를 넘지 않게)
            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Text {
                    id: labelText
                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.min(implicitWidth, Math.max(0, parent.width - (dateText.visible ? dateText.implicitWidth + 8 : 0)))
                    text: line.label
                    textFormat: Text.PlainText
                    color: line.strong || line.selected ? Theme.text : Theme.text2
                    font.family: Theme.font
                    font.pixelSize: 13
                    font.weight: line.strong ? Font.DemiBold : Font.Normal
                    elide: Text.ElideRight
                }
                Text {
                    id: dateText
                    visible: line.date !== ""
                    x: labelText.width + 8
                    anchors.verticalCenter: parent.verticalCenter
                    text: line.date
                    color: Theme.text3
                    font.family: Theme.font
                    font.pixelSize: 12
                }
            }
            Row { id: toolRow; spacing: 0 }
        }
    }

    ChoiceRow {
        visible: choices.melon
        selected: choices.melonSelected
        label: "멜론 가사 그대로"
        onPressed: choices.choose("melon")
    }

    Repeater {
        model: choices.presets
        delegate: Item {
            id: item
            required property var modelData
            readonly property bool renaming: choices.renamingId === modelData.id
            readonly property bool deleting: choices.deletingId === modelData.id
            Layout.fillWidth: true
            implicitHeight: 36

            ChoiceRow {
                anchors.fill: parent
                visible: !item.renaming
                selected: item.modelData.default === true
                label: choices.labelOf(item.modelData)
                date: item.modelData.name ? choices.dateOf(item.modelData) : ""
                strong: !!item.modelData.name
                onPressed: choices.choose(item.modelData.id)
                AppButton {
                    visible: !item.deleting
                    glyph: "pencil"; variant: "ghost"; size: "small"
                    implicitHeight: 28
                    onClicked: { choices.deletingId = ""; choices.renamingId = item.modelData.id }
                    Accessible.name: "이름 고치기: " + choices.labelOf(item.modelData)
                    AppToolTip { visible: parent.hovered; delay: 400; text: "이름 고치기" }
                }
                AppButton {
                    glyph: "trash"
                    text: item.deleting ? "삭제" : ""
                    variant: item.deleting ? "danger" : "ghost"
                    destructive: true
                    size: "small"
                    implicitHeight: 28
                    onClicked: choices.remove(item.modelData)
                    Accessible.name: item.deleting ? "삭제 확인" : "삭제: " + choices.labelOf(item.modelData)
                    AppToolTip { visible: parent.hovered; delay: 400; text: item.deleting ? "한 번 더 누르면 지워져요" : "프리셋 삭제 · 한 번 더 누르면 지워져요" }
                }
            }

            // 이름 고치기
            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 4
                visible: item.renaming
                spacing: 2
                PresetNameField {
                    id: nameField
                    Layout.fillWidth: true
                    host: choices
                    preset: item.modelData
                }
                AppButton {
                    glyph: "check"; variant: "primary"; size: "small"
                    implicitHeight: 28
                    onClicked: { Qt.inputMethod.commit(); choices.finishRename(item.modelData, nameField.text) }
                    Accessible.name: "이름 저장"
                }
                AppButton {
                    glyph: "x"; variant: "ghost"; size: "small"
                    implicitHeight: 28
                    onClicked: choices.renamingId = ""
                    Accessible.name: "이름 고치기 취소"
                }
            }
        }
    }
}
