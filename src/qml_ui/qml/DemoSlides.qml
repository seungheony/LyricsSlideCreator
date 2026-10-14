import QtQuick
import QtQuick.Shapes
import "."

// 튜토리얼용 슬라이드 목록. SlideList와 같은 모양으로 그리되 실제 가사와는 연결되지 않은 복제본이다.
// 나누기·합치기·삭제는 목록 추가/삭제 전환 효과로 움직임을 보여준다.
Rectangle {
    id: root
    color: Theme.bg

    // 표시 상태 (Demo 스크립트가 바꾼다)
    property int active: -1
    property int hover: -1           // 마우스가 올라간 슬라이드 (삭제 버튼 표시)
    property bool trashHot: false    // 삭제 버튼 위
    property int pressedSlide: -1    // 누르는 중인 슬라이드
    property int cutSlide: -1        // 이 슬라이드의 cutAt번째 줄 앞에 나누기 표시
    property int cutAt: -1
    property bool cutHot: false      // 가위 버튼 위
    property int joinAt: -1          // 이 슬라이드 위쪽 사이에 합치기 표시
    property int dropSlide: -1       // 줄을 놓을 슬라이드
    property bool dropAtStart: false // 삽입선 위치: 처음(true) / 끝(false)
    property int dragSlide: -1       // 끌고 있는 줄의 원래 위치 (흐리게)
    property int dragLine: -1
    property int hideSlide: -1       // 날아가는 중인 줄의 원래 자리 (비워 둔다)
    property int hideLine: -1

    function clearMarks() {
        active = -1; hover = -1; trashHot = false; pressedSlide = -1
        cutSlide = -1; cutAt = -1; cutHot = false; joinAt = -1
        dropSlide = -1; dropAtStart = false; dragSlide = -1; dragLine = -1
        hideSlide = -1; hideLine = -1
        flyAnim.stop(); flyer.visible = false
    }

    // 처음 상태로 채운다. 추가/삭제 효과 없이 바로 바꿔서 반복할 때 깜빡이지 않게 한다
    property bool animate: true
    function setGroups(groups) {
        animate = false
        applyGroups(groups)
        view.forceLayout()
        animate = true
    }
    // 바뀐 슬라이드만 고쳐 쓴다.
    // 새 슬라이드는 다른 슬라이드의 높이 변화가 끝난 뒤에 붙인다: 동시에 일어나면 ListView가
    // 추가 효과 중인 슬라이드를 예전 높이 기준 위치에 둔 채 다시 배치하지 않는다
    property var pending: []
    function applyGroups(groups) {
        appendTimer.stop()
        const texts = groups.map(g => g.join("\n"))
        for (let i = 0; i < Math.min(texts.length, slides.count); i++)
            if (slides.get(i).text !== texts[i]) slides.setProperty(i, "text", texts[i])
        while (slides.count > texts.length) slides.remove(slides.count - 1)
        pending = texts.slice(slides.count)
        if (!pending.length) return
        if (animate) appendTimer.restart()
        else appendPending()
    }
    function appendPending() {
        for (const text of pending) slides.append({ text: text })
        pending = []
        flyer.visible = false
    }
    Timer { id: appendTimer; interval: 250; onTriggered: root.appendPending() }
    function linesAt(i) { return slides.get(i).text.split("\n") }
    function split(i, at) {
        const lines = linesAt(i)
        slides.setProperty(i, "text", lines.slice(0, at).join("\n"))
        slides.insert(i + 1, { text: lines.slice(at).join("\n") })
    }
    function merge(i) {
        slides.setProperty(i, "text", slides.get(i).text + "\n" + slides.get(i + 1).text)
        slides.remove(i + 1)
    }
    function removeAt(i) { slides.remove(i) }

    // 포인터를 옮길 대상
    function slot(i) { return view.itemAtIndex(i) }
    function card(i) { return slot(i).card }
    function line(i, l) { return slot(i).lineAt(l) }
    function trash(i) { return slot(i).trash }
    function joinGap(i) { return slot(i).joinGap }
    function cutGap(i, at) { return slot(i).lineAt(at).cutGap }
    function flash(i) { const s = slot(i); if (s) s.flash() }

    // ── 예시 전용: 넘친 줄이 옆 슬라이드로 넘어가는 모습 (실제 편집 화면에는 없음) ──
    // from 슬라이드의 at번째 줄을 to 슬라이드 맨 앞(to가 끝이면 새 슬라이드 자리)으로 날린 뒤 groups로 바꾼다
    property var flyGroups: null
    property int flyTarget: -1
    function fly(from, at, to, groups) {
        const src = line(from, at)
        const p = src.mapToItem(root, src.width / 2, src.height / 2)
        let q
        if (to < slides.count) {
            const dst = line(to, 0)
            q = dst.mapToItem(root, dst.width / 2, 0)
        } else {
            const c = card(to - 1)
            q = c.mapToItem(root, c.width / 2, c.height + 18 + 46)
        }
        flyerText.text = linesAt(from)[at]
        flyer.x = p.x - flyer.width / 2
        flyer.y = p.y - flyer.height / 2
        flyX.to = q.x - flyer.width / 2
        flyY.to = q.y - flyer.height / 2
        flyGroups = groups
        flyTarget = to
        hideSlide = from
        hideLine = at
        flyer.visible = true
        flyAnim.restart()
    }

    Rectangle {
        id: flyer
        visible: false
        z: 10
        width: Math.min(flyerText.implicitWidth + 28, root.width - 40)
        height: 32
        radius: 10
        color: Theme.slideBg
        border.width: 2
        border.color: Theme.primary
        Text {
            id: flyerText
            anchors.centerIn: parent
            width: parent.width - 28
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
            color: "white"
            font.family: Theme.font
            font.pixelSize: 14
            font.weight: Font.Bold
        }
        ParallelAnimation {
            id: flyAnim
            NumberAnimation { id: flyX; target: flyer; property: "x"; duration: 550; easing.type: Easing.InOutCubic }
            NumberAnimation { id: flyY; target: flyer; property: "y"; duration: 550; easing.type: Easing.InOutCubic }
            SequentialAnimation {
                NumberAnimation { target: flyer; property: "scale"; from: 1; to: 1.08; duration: 200 }
                NumberAnimation { target: flyer; property: "scale"; to: 1; duration: 350 }
            }
            onFinished: {
                root.hideSlide = -1
                root.hideLine = -1
                root.applyGroups(root.flyGroups)
                root.flash(root.flyTarget)
                // 새 슬라이드는 조금 늦게 붙으므로 그때까지 날아온 줄을 남겨 둔다
                if (!root.pending.length) flyer.visible = false
            }
        }
    }

    ListModel { id: slides }

    ListView {
        id: view
        x: 2
        y: 2
        width: parent.width - 12
        height: parent.height - 2
        interactive: false
        clip: true
        model: slides

        add: Transition {
            enabled: root.animate
            NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 300 }
            NumberAnimation { property: "scale"; from: 0.92; to: 1; duration: 300; easing.type: Easing.OutCubic }
        }
        remove: Transition {
            enabled: root.animate
            NumberAnimation { property: "opacity"; to: 0; duration: 320 }
            NumberAnimation { property: "scale"; to: 0.85; duration: 320; easing.type: Easing.InCubic }
        }
        displaced: Transition { enabled: root.animate; NumberAnimation { property: "y"; duration: 320; easing.type: Easing.OutCubic } }

        delegate: Column {
            id: slot
            required property string text
            required property int index
            readonly property var lines: text.split("\n")
            readonly property alias card: card
            readonly property alias trash: trash
            readonly property alias joinGap: joinGap
            width: ListView.view.width

            function lineAt(l) { return lineRep.itemAt(l) }
            function flash() { flashAnim.restart() }

            // 슬라이드 사이: 합치기
            Item {
                id: joinGap
                width: parent.width
                height: slot.index > 0 ? 18 : 0
                visible: slot.index > 0
                readonly property bool on: root.joinAt === slot.index
                Shape {
                    anchors.fill: parent
                    opacity: joinGap.on ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: Theme.fast } }
                    ShapePath {
                        strokeColor: Theme.primary
                        strokeWidth: 1.5
                        strokeStyle: ShapePath.DashLine
                        dashPattern: [3, 3]
                        fillColor: "transparent"
                        startX: joinGap.width * 0.1; startY: 9
                        PathLine { x: joinGap.width * 0.9; y: 9 }
                    }
                }
                Rectangle {
                    anchors.centerIn: parent
                    width: joinRow.implicitWidth + 20
                    height: 24
                    radius: 12
                    color: Theme.primary
                    opacity: joinGap.on ? 1 : 0
                    scale: joinGap.on ? 1 : 0.9
                    Behavior on opacity { NumberAnimation { duration: Theme.fast } }
                    Behavior on scale { NumberAnimation { duration: Theme.fast } }
                    Row {
                        id: joinRow
                        anchors.centerIn: parent
                        spacing: 4
                        Icon { glyph: "join"; size: 13; color: "white"; anchors.verticalCenter: parent.verticalCenter }
                        Text { text: "합치기"; color: "white"; font.family: Theme.font; font.pixelSize: 12; font.weight: Font.Bold }
                    }
                }
            }

            Rectangle {
                id: card
                width: parent.width
                height: Math.max(92, lineCol.implicitHeight + 40)
                radius: Theme.radiusSm
                color: Theme.slideBg
                border.width: 1
                border.color: Theme.slideBorder
                scale: root.pressedSlide === slot.index ? 0.98 : 1
                Behavior on scale { NumberAnimation { duration: 100 } }

                readonly property bool isActive: root.active === slot.index
                readonly property bool isDrop: root.dropSlide === slot.index

                Rectangle {
                    anchors.fill: parent
                    radius: parent.radius
                    color: "transparent"
                    border.width: card.isActive || card.isDrop ? 2 : 1
                    border.color: card.isDrop ? Qt.rgba(0, 0.804, 0.235, 0.55)
                                : card.isActive ? Theme.primary
                                : root.hover === slot.index ? Qt.rgba(1, 1, 1, 0.15) : "transparent"
                }
                Rectangle {
                    id: glow
                    anchors.fill: parent
                    anchors.margins: -4
                    radius: parent.radius + 4
                    color: "transparent"
                    border.width: 4
                    border.color: Theme.primarySoft
                    opacity: 0
                    SequentialAnimation {
                        id: flashAnim
                        NumberAnimation { target: glow; property: "opacity"; to: 1; duration: 150 }
                        NumberAnimation { target: glow; property: "opacity"; to: 0; duration: 450 }
                    }
                }

                Text {
                    x: 12; y: 9
                    text: slot.index + 1
                    color: card.isActive ? Theme.primary : Qt.rgba(1, 1, 1, 0.4)
                    font.family: Theme.font
                    font.pixelSize: 11
                    font.weight: Font.Bold
                }

                Rectangle {
                    id: trash
                    x: card.width - width - 6; y: 6
                    width: 28; height: 28; radius: 7
                    readonly property bool hot: root.trashHot && root.hover === slot.index
                    color: hot ? Qt.rgba(0.94, 0.27, 0.32, 0.2) : "transparent"
                    opacity: root.hover === slot.index ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: Theme.fast } }
                    Icon {
                        anchors.centerIn: parent
                        glyph: "trash"; size: 15
                        color: trash.hot ? Theme.danger : Qt.rgba(1, 1, 1, 0.5)
                    }
                }

                Column {
                    id: lineCol
                    anchors.centerIn: parent
                    width: card.width - 104

                    Repeater {
                        id: lineRep
                        model: slot.lines
                        delegate: Item {
                            id: lineItem
                            required property string modelData
                            required property int index
                            readonly property alias cutGap: cutGap
                            width: lineCol.width
                            height: lineText.height + 6

                            Text {
                                id: lineText
                                anchors.centerIn: parent
                                width: parent.width
                                text: lineItem.modelData
                                color: "white"
                                font.family: Theme.font
                                font.pixelSize: 14
                                font.weight: Font.Bold
                                lineHeight: 1.15
                                wrapMode: Text.WordWrap
                                horizontalAlignment: Text.AlignHCenter
                                opacity: root.hideSlide === slot.index && root.hideLine === lineItem.index ? 0
                                       : root.dragSlide === slot.index && root.dragLine === lineItem.index ? 0.25 : 1
                            }

                            // 놓을 위치: 받는 슬라이드의 첫 줄 위 또는 마지막 줄 아래
                            Rectangle {
                                visible: card.isDrop && lineItem.index === (root.dropAtStart ? 0 : lineRep.count - 1)
                                x: -(card.width - lineCol.width) / 2 + 28
                                y: root.dropAtStart ? -2 : parent.height - 1
                                width: card.width - 56
                                height: 3
                                radius: 2
                                color: Theme.primary
                            }

                            // 줄 사이: 나누기
                            Item {
                                id: cutGap
                                readonly property bool on: root.cutSlide === slot.index && root.cutAt === lineItem.index
                                visible: lineItem.index > 0
                                x: -(card.width - lineCol.width) / 2
                                y: -6
                                width: card.width
                                height: 12
                                z: 2
                                Shape {
                                    anchors.fill: parent
                                    opacity: cutGap.on ? 1 : 0
                                    Behavior on opacity { NumberAnimation { duration: Theme.fast } }
                                    ShapePath {
                                        strokeColor: Theme.primary
                                        strokeWidth: 1.5
                                        strokeStyle: ShapePath.DashLine
                                        dashPattern: [3, 3]
                                        fillColor: "transparent"
                                        startX: 16; startY: 6
                                        PathLine { x: cutGap.width - 16; y: 6 }
                                    }
                                }
                                Rectangle {
                                    x: 6
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: 22; height: 22; radius: 11
                                    color: Theme.primary
                                    opacity: cutGap.on ? 1 : 0
                                    scale: root.cutHot && cutGap.on ? 1.1 : cutGap.on ? 1 : 0.8
                                    Behavior on opacity { NumberAnimation { duration: Theme.fast } }
                                    Behavior on scale { NumberAnimation { duration: Theme.fast } }
                                    Icon { anchors.centerIn: parent; glyph: "scissors"; size: 13; color: "white" }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
