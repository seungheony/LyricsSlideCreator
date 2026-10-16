import QtQuick
import QtQuick.Controls.Basic
import "."

// 예배 PPT 패널 카드 끝의 '넣기' 칸 (＋ 곡 추가, ＋ 양식 추가). 테두리 칸이고 마우스를 올리거나 끌어다 놓는 중이면 초록.
// 곡 카드와 양식 칸(찬양 전·후)이 같은 모양을 쓴다.
Button {
    id: control
    property bool lit: false          // 바깥에서 켬 (끌어다 놓는 중 등)
    property bool small: false        // 양식 칸 안의 작은 넣기 칸
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
            Icon { glyph: "plus"; size: control.small ? 12 : 14; color: control.on ? Theme.primaryText : Theme.text2; anchors.verticalCenter: parent.verticalCenter }
            Text {
                text: control.text
                color: control.on ? Theme.primaryText : Theme.text2
                font.family: Theme.font
                font.pixelSize: control.small ? 12 : 13
                font.weight: Font.DemiBold
                anchors.verticalCenter: parent.verticalCenter
            }
        }
    }
    background: Rectangle {
        radius: control.small ? 8 : Theme.radiusSm
        color: control.on ? Theme.primarySoft : Theme.surface2Clear
        border.width: control.visualFocus ? 2 : 1.5
        // 카드(surface2) 위에서도 보이는 옅은 테두리
        border.color: control.on ? Theme.primary : Qt.rgba(Theme.text3.r, Theme.text3.g, Theme.text3.b, 0.4)
        Behavior on color { ColorAnimation { duration: Theme.fast } }
    }
}
