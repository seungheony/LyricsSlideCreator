import QtQuick
import QtQuick.Controls.Basic
import "."

// Theme를 따르는 툴팁. Basic 스타일의 기본 툴팁은 다크 모드에서도 흰 상자라 직접 그린다.
// 사용: 대상 안에 AppToolTip { visible: hovered; text: "..." } (대상이 마우스를 받는 Item이면 그 Item의 hover 상태로)
ToolTip {
    id: tip
    delay: 500
    margins: 8
    padding: 8
    leftPadding: 12
    rightPadding: 12
    // 글 폭에 맞추되 340까지. 넘치면 문장·구분점에서 먼저 줄을 바꾸고 줄 길이를 고르게 (BalancedText)
    width: label.fitWidth + leftPadding + rightPadding

    contentItem: BalancedText {
        id: label
        maxWidth: 340 - tip.leftPadding - tip.rightPadding
        source: tip.text
        font.family: Theme.font
        font.pixelSize: 12
        lineHeight: 1.3
        color: Theme.tooltipText
    }
    background: Rectangle {
        radius: 8
        color: Theme.tooltipBg
        border.width: Theme.dark ? 1 : 0
        border.color: Theme.border
    }
}
