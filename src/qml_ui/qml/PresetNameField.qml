import QtQuick
import QtQuick.Controls.Basic
import "."

// 프리셋 이름 고치기 칸 (Enter 저장, Esc 취소). 보일 때 지금 이름을 넣고 전부 고른다
// host: renamingId·finishRename(preset, name)을 가진 쪽 (PresetChoices)
TextField {
    id: field
    property var host: null
    property var preset: null

    implicitHeight: 30
    placeholderText: "프리셋 이름"
    placeholderTextColor: Theme.text3
    color: Theme.text
    font.family: Theme.font
    font.pixelSize: 13
    maximumLength: 60
    selectByMouse: true
    leftPadding: 8; rightPadding: 8
    background: Rectangle { radius: 8; color: Theme.surface; border.width: 1.5; border.color: Theme.focusBorder }
    onVisibleChanged: if (visible) { text = preset.name || ""; forceActiveFocus(); selectAll() }
    onAccepted: { Qt.inputMethod.commit(); host.finishRename(preset, text) }
    Keys.onEscapePressed: (event) => { host.renamingId = ""; event.accepted = true }
    Accessible.name: "프리셋 이름"
    ContextMenu.menu: AppTextMenu { editor: field }
}
