import QtQuick
import QtQuick.Effects

// 모서리가 둥근 이미지. 로드되면 부드럽게 나타난다.
// 소프트웨어 렌더링(오래된 그래픽 드라이버, 가상 머신, 원격 데스크톱)에서는
// 셰이더 효과를 쓸 수 없으므로 둥근 모서리 없이 이미지를 그대로 보여준다.
Item {
    id: root
    readonly property bool effects: GraphicsInfo.api !== GraphicsInfo.Software
    property alias source: img.source
    property real radius: 8
    property color placeholder: "transparent"
    readonly property bool ready: img.status === Image.Ready

    Rectangle {
        anchors.fill: parent
        radius: root.radius
        color: root.placeholder
    }

    Image {
        id: img
        anchors.fill: parent
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        cache: false
        visible: !root.effects
        opacity: root.ready ? 1 : 0
        smooth: true
        mipmap: true
        Behavior on opacity { NumberAnimation { duration: 300 } }
    }

    Rectangle {
        id: mask
        anchors.fill: parent
        radius: root.radius
        visible: false
        layer.enabled: true
    }

    MultiEffect {
        anchors.fill: parent
        visible: root.effects
        source: img
        maskEnabled: true
        maskSource: mask
        opacity: root.ready ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 300 } }
    }
}
