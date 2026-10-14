import QtQuick
import QtQuick.Controls.Basic
import "."

// variant: "primary"(연한 초록 바탕 + 초록 글자) | "secondary" | "ghost" | "danger"
// size:    "small" | "normal" | "large"
Button {
    id: control
    property string variant: "secondary"
    property string size: "normal"
    property string glyph: ""
    property bool busy: false

    implicitHeight: size === "small" ? 30 : size === "large" ? 46 : 40
    leftPadding: glyph && !text ? 0 : (size === "small" ? 10 : size === "large" ? 28 : 18)
    rightPadding: leftPadding
    implicitWidth: glyph && !text ? implicitHeight : Math.max(implicitHeight, implicitContentWidth + leftPadding + rightPadding)
    font.family: Theme.font
    font.pixelSize: size === "small" ? 13 : size === "large" ? 15 : 14
    font.weight: Font.DemiBold
    hoverEnabled: true
    focusPolicy: Qt.TabFocus
    HoverHandler { cursorShape: Qt.PointingHandCursor }
    // 키보드로 눌러지도록 (Space는 기본 동작). 확인창·튜토리얼에서 포커스된 버튼이 실행된다
    Keys.onReturnPressed: click()
    Keys.onEnterPressed: click()

    readonly property color fg: variant === "primary" ? Theme.primaryText
                               : variant === "danger" ? "white"
                               : variant === "ghost" ? (hovered ? Theme.text : Theme.text2)
                               : Theme.text

    contentItem: Item {
        implicitWidth: row.implicitWidth
        implicitHeight: row.implicitHeight
        Row {
            id: row
            anchors.centerIn: parent
            spacing: 6
            visible: !control.busy
            Icon {
                visible: control.glyph !== ""
                glyph: control.glyph
                color: control.fg
                size: control.size === "small" ? 14 : 16
                anchors.verticalCenter: parent.verticalCenter
            }
            Text {
                visible: control.text !== ""
                text: control.text
                font: control.font
                color: control.fg
                anchors.verticalCenter: parent.verticalCenter
            }
        }
        Icon {
            anchors.centerIn: parent
            visible: control.busy
            glyph: "loader"
            color: control.fg
            RotationAnimation on rotation { running: control.busy; from: 0; to: 360; duration: 700; loops: Animation.Infinite }
        }
    }

    background: Rectangle {
        radius: Theme.radiusSm
        color: {
            if (control.variant === "primary") return control.hovered && control.enabled ? Theme.primarySoftHover : Theme.primarySoft
            if (control.variant === "danger") return Theme.danger
            if (control.variant === "ghost") return control.hovered ? Theme.surface2 : Theme.surface2Clear
            return control.hovered ? Theme.border : Theme.surface2
        }
        // Tab으로 포커스가 왔을 때(visualFocus) 위치가 보이도록
        border.width: control.visualFocus ? 2 : 0
        border.color: Theme.primary
        Behavior on color { ColorAnimation { duration: Theme.fast } }
    }

    opacity: enabled ? 1 : 0.5
    scale: pressed ? 0.97 : 1
    Behavior on scale { NumberAnimation { duration: 100 } }
}
