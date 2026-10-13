import QtQuick
import "."

// 튜토리얼에서 실제 화면 위에 예시 동작을 재생하는 틀.
// script: [[기다릴 ms, 함수], ...] 를 차례로 실행하고, 끝나면 잠시 쉬었다가 reset 후 처음부터 반복한다.
// 실제 데이터는 건드리지 않는다: 바뀌는 모습이 필요하면 복제본(DemoSlides 등)을 위에 덮어 그린다.
Item {
    id: demo
    property var script: []
    property int step: 0
    property string ghostText: ""    // 끌고 있는 줄 (포인터 옆에 표시)
    readonly property alias cursor: cursor
    default property alias content: layer.data

    signal reset()

    function run() {
        timer.stop()
        step = 0
        ghostText = ""
        cursor.pressed = false
        reset()
        if (script.length) {
            timer.interval = script[0][0]
            timer.start()
        }
    }

    // item 안의 (fx, fy) 비율 위치 (이 틀의 좌표)
    function point(item, fx, fy) {
        return item.mapToItem(demo, item.width * (fx === undefined ? 0.5 : fx), item.height * (fy === undefined ? 0.5 : fy))
    }
    function moveTo(item, fx, fy) {
        const p = point(item, fx, fy)
        cursor.x = p.x
        cursor.y = p.y
    }
    // item 안의 픽셀 위치로 이동
    function moveToXY(item, x, y) {
        const p = item.mapToItem(demo, x, y)
        cursor.x = p.x
        cursor.y = p.y
    }
    function jumpTo(item, fx, fy) {
        cursor.smooth = false
        moveTo(item, fx, fy)
        cursor.smooth = true
    }
    function click() { cursor.click() }

    Timer {
        id: timer
        onTriggered: {
            if (demo.step >= demo.script.length) { demo.run(); return }
            demo.script[demo.step][1]()
            demo.step++
            interval = demo.step < demo.script.length ? demo.script[demo.step][0] : 1800
            start()
        }
    }

    Component.onCompleted: Qt.callLater(run)

    Item { id: layer; anchors.fill: parent }

    // 끌고 있는 줄
    Rectangle {
        visible: demo.ghostText !== ""
        x: cursor.x + 14
        y: cursor.y - 18
        z: 99
        width: Math.min(ghostLabel.implicitWidth + 28, 300)
        height: 36
        radius: 10
        color: Theme.slideBg
        border.width: 2
        border.color: Theme.primary
        rotation: -1.5
        Text {
            id: ghostLabel
            anchors.fill: parent
            anchors.leftMargin: 14
            anchors.rightMargin: 14
            verticalAlignment: Text.AlignVCenter
            elide: Text.ElideRight
            text: demo.ghostText
            color: "white"
            font.family: Theme.font
            font.pixelSize: 14
            font.weight: Font.Bold
        }
    }

    DemoCursor { id: cursor; z: 100 }
}
