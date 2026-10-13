import QtQuick
import QtQuick.Shapes
import "."

// 튜토리얼 애니메이션의 가짜 마우스 포인터. (x, y)가 화살표 끝
Item {
    id: cursor
    property bool pressed: false
    property bool smooth: true       // false면 이동 애니메이션 없이 바로 옮긴다
    width: 1
    height: 1

    Behavior on x { enabled: cursor.smooth; NumberAnimation { duration: 600; easing.type: Easing.InOutCubic } }
    Behavior on y { enabled: cursor.smooth; NumberAnimation { duration: 600; easing.type: Easing.InOutCubic } }

    function click() { ripple.restart(); tap.restart() }

    // 클릭 표시: 끝에서 퍼지는 원
    Rectangle {
        id: ring
        width: 36; height: 36; radius: 18
        x: -width / 2; y: -height / 2
        color: "transparent"
        border.width: 3
        border.color: Theme.primary
        opacity: 0
        ParallelAnimation {
            id: ripple
            NumberAnimation { target: ring; property: "scale"; from: 0.3; to: 1.3; duration: 450; easing.type: Easing.OutCubic }
            NumberAnimation { target: ring; property: "opacity"; from: 0.9; to: 0; duration: 450 }
        }
    }

    Shape {
        id: arrow
        scale: cursor.pressed ? 0.85 : 1
        transformOrigin: Item.TopLeft
        Behavior on scale { enabled: !tap.running; NumberAnimation { duration: 100 } }
        SequentialAnimation {
            id: tap
            NumberAnimation { target: arrow; property: "scale"; to: 0.82; duration: 90 }
            NumberAnimation { target: arrow; property: "scale"; to: 1; duration: 140 }
        }
        ShapePath {
            fillColor: "#191F28"
            strokeColor: "white"
            strokeWidth: 1.5
            joinStyle: ShapePath.RoundJoin
            startX: 0; startY: 0
            PathLine { x: 0; y: 17 }
            PathLine { x: 4.4; y: 12.8 }
            PathLine { x: 7.4; y: 19.4 }
            PathLine { x: 10.2; y: 18.2 }
            PathLine { x: 7.3; y: 11.8 }
            PathLine { x: 12.6; y: 11.8 }
            PathLine { x: 0; y: 0 }
        }
    }
}
