import QtQuick
import QtQuick.Controls.Basic
import "."

// 화면 아래쪽에 잠깐 나타나는 알림. 되돌리기 같은 액션 버튼을 붙일 수 있다.
Item {
    id: host
    width: card.width
    height: card.height

    property var actions: []       // [{ label, handler }]

    function show(message, options) {
        options = options || {}
        label.text = message
        host.error = !!options.error
        host.actions = options.actions
                       || (options.actionLabel ? [{ label: options.actionLabel, handler: options.onAction }] : [])
        hideTimer.interval = options.duration || 2600
        card.state = "shown"
        hideTimer.restart()
    }
    function hide() { card.state = "" }

    property bool error: false

    Timer { id: hideTimer; onTriggered: host.hide() }

    // 마우스를 올려 두는 동안은 사라지지 않는다
    HoverHandler {
        target: card
        onHoveredChanged: {
            if (hovered) hideTimer.stop()
            else if (card.state === "shown") hideTimer.restart()
        }
    }

    Rectangle {
        id: card
        width: content.implicitWidth + 32
        height: 46
        radius: 12
        color: Theme.toastBg
        opacity: 0
        y: 12
        visible: opacity > 0

        states: State {
            name: "shown"
            PropertyChanges { card.opacity: 1; card.y: 0 }
        }
        transitions: Transition {
            NumberAnimation { properties: "opacity,y"; duration: 250; easing.type: Easing.OutCubic }
        }

        Row {
            id: content
            anchors.centerIn: parent
            spacing: 10
            Rectangle {
                width: 20; height: 20; radius: 10
                color: host.error ? Theme.danger : Theme.primary
                anchors.verticalCenter: parent.verticalCenter
                Icon { anchors.centerIn: parent; glyph: host.error ? "x" : "check"; size: 12; color: "white" }
            }
            Text {
                id: label
                width: Math.min(implicitWidth, 380)
                elide: Text.ElideRight
                color: "white"
                font.family: Theme.font
                font.pixelSize: 14
                font.weight: Font.DemiBold
                anchors.verticalCenter: parent.verticalCenter
            }
            Repeater {
                model: host.actions
                delegate: Button {
                    id: actionButton
                    required property var modelData
                    anchors.verticalCenter: parent.verticalCenter
                    hoverEnabled: true
                    implicitHeight: 28
                    leftPadding: 10; rightPadding: 10
                    contentItem: Text {
                        text: actionButton.modelData.label
                        color: Theme.primary
                        font.family: Theme.font
                        font.pixelSize: 13
                        font.weight: Font.Bold
                        verticalAlignment: Text.AlignVCenter
                    }
                    background: Rectangle {
                        radius: 7
                        color: Qt.rgba(1, 1, 1, actionButton.hovered ? 0.2 : 0.12)
                    }
                    HoverHandler { cursorShape: Qt.PointingHandCursor }
                    onClicked: {
                        host.hide()
                        if (actionButton.modelData.handler) actionButton.modelData.handler()
                    }
                }
            }
        }
    }
}
