import QtQuick
import QtQuick.Controls.Basic
import "."

// 설명이 필요한 곳 옆에 두는 물음표 버튼. 누르면 해당 부분의 튜토리얼(Tour)을 연다
Button {
    id: control
    implicitWidth: 28    // 클릭 영역. 보이는 동그라미는 20px
    implicitHeight: 28
    padding: 0
    hoverEnabled: true
    focusPolicy: Qt.TabFocus
    HoverHandler { cursorShape: Qt.PointingHandCursor }
    Accessible.name: "도움말"

    contentItem: Text {
        text: "?"
        color: control.hovered ? Theme.primary : Theme.text3
        font.family: Theme.font
        font.pixelSize: 12
        font.weight: Font.Bold
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
    }

    background: Rectangle {
        implicitWidth: 20
        implicitHeight: 20
        width: 20; height: 20
        x: (control.width - width) / 2
        y: (control.height - height) / 2
        radius: width / 2
        color: control.hovered ? Theme.primarySoft : Qt.rgba(Theme.primarySoft.r, Theme.primarySoft.g, Theme.primarySoft.b, 0)
        border.width: 1.5
        border.color: control.hovered ? Theme.primary : Theme.text3
        opacity: control.hovered ? 1 : 0.7
        Behavior on color { ColorAnimation { duration: Theme.fast } }
    }

    ToolTip.visible: hovered
    ToolTip.delay: 400
    ToolTip.text: "사용 방법 보기"
}
