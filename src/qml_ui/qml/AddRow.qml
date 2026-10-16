import QtQuick
import QtQuick.Controls.Basic
import "."

// 콘티 패널 구역 끝의 '넣기' 칸 (＋ 곡 추가, ＋ PPT 넣기). 테두리 칸이고 마우스를 올리거나 끌어다 놓는 중이면 초록.
// 세 구역(앞에 붙일 PPT · 곡 · 뒤에 붙일 PPT)이 같은 모양을 쓴다.
Button {
    id: control
    property bool lit: false          // 바깥에서 켬 (끌어다 놓는 중 등)
    readonly property bool on: lit || hovered || visualFocus

    implicitHeight: 40
    hoverEnabled: true
    focusPolicy: Qt.TabFocus
    Keys.onReturnPressed: click()
    Keys.onEnterPressed: click()
    Accessible.name: text
    HoverHandler { cursorShape: Qt.PointingHandCursor }

    contentItem: Item {
        Row {
            anchors.centerIn: parent
            spacing: 5
            Icon { glyph: "plus"; size: 14; color: control.on ? Theme.primaryText : Theme.text2; anchors.verticalCenter: parent.verticalCenter }
            Text {
                text: control.text
                color: control.on ? Theme.primaryText : Theme.text2
                font.family: Theme.font
                font.pixelSize: 13
                font.weight: Font.DemiBold
                anchors.verticalCenter: parent.verticalCenter
            }
        }
    }
    background: Rectangle {
        radius: Theme.radiusSm
        color: control.on ? Theme.primarySoft : Theme.surface2Clear
        border.width: control.visualFocus ? 2 : 1.5
        border.color: control.on ? Theme.primary : Theme.border
        Behavior on color { ColorAnimation { duration: Theme.fast } }
    }
}
