import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Shapes
import "."

// 슬라이드 미리보기 목록.
// 직접 상태를 바꾸지 않고, 사용자의 편집 의도를 시그널로 알린다 (EditorPage가 텍스트를 고쳐 씀).
Item {
    id: list

    property var blocks: []
    // 슬라이드별·줄별 PPT 글상자 폭 대비 글자 폭 비율 (1을 넘으면 PPT에서 줄바꿈, EditorPage.measureLines)
    property var ratios: []
    property int active: -1
    // (src, 포인터가 가리키는 위치) → 허용된 드롭 위치 또는 null. 규칙은 editor.js resolveDrop
    property var resolveDrop: function (src, target) { return target }

    signal cutRequested(int slide, int at)
    signal joinRequested(int slide)              // slide와 slide+1 합치기
    signal removeRequested(int slide)
    signal moveRequested(var src, var target)
    signal revealRequested(int slide)

    readonly property bool dragging: drag.active

    function scrollToTop() { flick.contentY = 0 }

    function ensureVisible(idx) {
        col.forceLayout()
        const it = rep.itemAt(idx)
        if (!it) return
        const top = col.y + it.y + it.cardY
        const bottom = top + it.cardHeight
        let to = flick.contentY
        if (top < flick.contentY) to = top - 8
        else if (bottom > flick.contentY + flick.height) to = bottom - flick.height + 8
        to = Math.max(0, Math.min(to, Math.max(0, flick.contentHeight - flick.height)))
        if (to !== flick.contentY) {
            scrollAnim.to = to
            scrollAnim.restart()
        }
    }

    function flash(idx) {
        ensureVisible(idx)
        const it = rep.itemAt(idx)
        if (it) it.flash()
    }

    // ── 줄 드래그 앤 드롭 ──
    QtObject {
        id: drag
        property bool active: false
        property var src: null
        property var target: null
        property point pointer: Qt.point(0, 0)   // 화면(scene) 좌표
    }
    readonly property int edge: 14   // 슬라이드 위/아래 가장자리 — 여기에 놓으면 새 슬라이드

    function beginDrag(slide, line, text, scenePos) {
        drag.src = { slide: slide, line: line }
        drag.active = true
        ghostLabel.text = text
        moveDrag(scenePos)
    }

    function moveDrag(scenePos) {
        if (!drag.active) return    // Esc로 취소한 뒤에도 마우스 이동 이벤트가 이어진다
        drag.pointer = scenePos
        updateTarget()
    }

    function endDrag() {
        const src = drag.src
        const target = drag.target
        cancelDrag()
        if (src && target) list.moveRequested(src, target)
    }

    function cancelDrag() {
        drag.active = false
        drag.src = null
        drag.target = null
        for (let i = 0; i < rep.count; i++) {
            const it = rep.itemAt(i)
            if (it) it.dropTarget = false
        }
        indicator.visible = false
    }

    onBlocksChanged: if (drag.active) cancelDrag()    // 끄는 중 목록이 다시 만들어지면 고스트·삽입선을 치운다

    function cardTop(i) { col.forceLayout(); const it = rep.itemAt(i); return it.y + it.cardY }
    function cardBottom(i) { col.forceLayout(); const it = rep.itemAt(i); return it.y + it.cardY + it.cardHeight }

    // 포인터 위치 → 놓을 위치 계산 및 삽입선 표시
    function updateTarget() {
        const local = list.mapFromItem(null, drag.pointer.x, drag.pointer.y)
        const p = col.mapFromItem(null, drag.pointer.x, drag.pointer.y)
        let raw = null

        // 1) 포인터가 가리키는 곳: 어느 슬라이드 위(line) 또는 어느 슬라이드 사이(new)
        const inside = local.x >= 0 && local.x <= list.width && local.y >= -20 && local.y <= list.height + 20
        if (inside && rep.count > 0) {
            for (let i = 0; i < rep.count; i++) {
                if (p.y < cardTop(i) + edge) { raw = { type: 'new', at: i }; break }
                if (p.y <= cardBottom(i) - edge) { raw = { type: 'line', slide: i, at: 0 }; break }
            }
            if (!raw) raw = { type: 'new', at: rep.count }
        }

        // 2) 허용된 동작으로 바꾼다 (옆 슬라이드 끝/처음에 붙이기, 옆 사이에 새 슬라이드)
        const target = raw ? list.resolveDrop(drag.src, raw) : null
        drag.target = target

        let lineY = 0
        let card = -1
        if (target && target.type === 'line') {
            card = target.slide
            const rows = rep.itemAt(card).lineRects()
            lineY = target.at === 0 ? rows[0].top : rows[rows.length - 1].bottom
        } else if (target) {
            const k = target.at
            if (k === 0) lineY = cardTop(0) - 9
            else if (k === rep.count) lineY = cardBottom(rep.count - 1) + 9
            else lineY = (cardBottom(k - 1) + cardTop(k)) / 2
        }

        for (let i = 0; i < rep.count; i++) rep.itemAt(i).dropTarget = (i === card)

        if (!target) { indicator.visible = false; return }
        // 새 슬라이드 표시는 목록 맨 위/아래에서도 보이도록 화면 안쪽으로 당긴다
        const viewTop = flick.contentY - col.y
        const viewBottom = viewTop + flick.height
        if (target.type === 'new') lineY = Math.min(Math.max(lineY, viewTop + 14), viewBottom - 14)
        indicator.isNew = target.type === 'new'
        indicator.lineY = lineY
        indicator.visible = lineY >= viewTop && lineY <= viewBottom
    }

    // 목록 위/아래 끝 근처로 끌면 자동 스크롤
    Timer {
        interval: 16
        repeat: true
        running: drag.active
        onTriggered: {
            const local = list.mapFromItem(null, drag.pointer.x, drag.pointer.y)
            const zone = 48
            let dy = 0
            if (local.y < zone) dy = -Math.ceil((zone - local.y) / 4)
            else if (local.y > list.height - zone) dy = Math.ceil((local.y - (list.height - zone)) / 4)
            if (!dy) return
            const max = Math.max(0, flick.contentHeight - flick.height)
            const next = Math.max(0, Math.min(max, flick.contentY + Math.max(-24, Math.min(24, dy))))
            if (next !== flick.contentY) {
                flick.contentY = next
                list.updateTarget()
            }
        }
    }

    Text {
        anchors.centerIn: parent
        visible: list.blocks.length === 0
        text: "가사를 입력하면 슬라이드가 여기에 표시돼요"
        color: Theme.text3
        font.family: Theme.font
        font.pixelSize: 13
    }

    Flickable {
        id: flick
        anchors.fill: parent
        clip: true
        contentWidth: width
        contentHeight: col.height + 16
        boundsBehavior: Flickable.StopAtBounds
        interactive: !drag.active
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        NumberAnimation { id: scrollAnim; target: flick; property: "contentY"; duration: 250; easing.type: Easing.OutCubic }

        Column {
            id: col
            x: 2
            y: 2
            width: flick.width - 12

            Repeater {
                id: rep
                model: list.blocks

                delegate: Column {
                    id: slot
                    required property var modelData
                    required property int index

                    width: col.width
                    property bool dropTarget: false
                    readonly property real cardY: card.y
                    readonly property real cardHeight: card.height

                    function flash() { flashAnim.restart() }
                    // 각 줄의 위/아래 위치 (col 좌표)
                    function lineRects() {
                        const rects = []
                        for (let i = 0; i < lineRep.count; i++) {
                            const it = lineRep.itemAt(i)
                            const pt = it.mapToItem(col, 0, 0)
                            rects.push({ top: pt.y, bottom: pt.y + it.height })
                        }
                        return rects
                    }

                    // ── 슬라이드 사이: 클릭하면 합치기 ──
                    Item {
                        width: parent.width
                        height: slot.index > 0 ? 18 : 0
                        visible: slot.index > 0
                        z: 2

                        MouseArea {
                            id: joinArea
                            anchors.fill: parent
                            hoverEnabled: true
                            enabled: !drag.active
                            cursorShape: Qt.PointingHandCursor
                            onClicked: list.joinRequested(slot.index - 1)
                        }
                        Shape {
                            anchors.fill: parent
                            opacity: joinArea.containsMouse ? 1 : 0
                            Behavior on opacity { NumberAnimation { duration: Theme.fast } }
                            ShapePath {
                                strokeColor: Theme.primary
                                strokeWidth: 1.5
                                strokeStyle: ShapePath.DashLine
                                dashPattern: [3, 3]
                                fillColor: "transparent"
                                startX: joinArea.width * 0.1; startY: 9
                                PathLine { x: joinArea.width * 0.9; y: 9 }
                            }
                        }
                        Rectangle {
                            anchors.centerIn: parent
                            width: joinRow.implicitWidth + 20
                            height: 24
                            radius: 12
                            color: Theme.primary
                            opacity: joinArea.containsMouse ? 1 : 0
                            scale: joinArea.containsMouse ? 1 : 0.9
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

                    // ── 슬라이드 카드 ──
                    Rectangle {
                        id: card
                        width: parent.width
                        height: Math.max(92, lines.implicitHeight + 40)
                        radius: Theme.radiusSm
                        color: Theme.slideBg
                        border.width: 1
                        border.color: Theme.slideBorder

                        readonly property bool isActive: slot.index === list.active
                        readonly property bool hovered: cardHover.hovered && !drag.active

                        HoverHandler { id: cardHover }

                        // 카드 바탕 클릭 → 가사로 이동
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: list.revealRequested(slot.index)
                        }

                        // 테두리: 현재 슬라이드 / 놓을 위치 / 마우스 오버
                        Rectangle {
                            anchors.fill: parent
                            radius: parent.radius
                            color: "transparent"
                            border.width: card.isActive || slot.dropTarget ? 2 : 1
                            border.color: slot.dropTarget ? Qt.rgba(0, 0.804, 0.235, 0.55)
                                        : card.isActive ? Theme.primary
                                        : card.hovered ? Qt.rgba(1, 1, 1, 0.15) : "transparent"
                        }
                        // 변경된 슬라이드 강조
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

                        // 삭제 버튼
                        Rectangle {
                            x: card.width - width - 6; y: 6
                            width: 28; height: 28; radius: 7
                            color: delArea.containsMouse ? Qt.rgba(0.94, 0.27, 0.32, 0.2) : "transparent"
                            opacity: card.hovered ? 1 : 0
                            visible: opacity > 0
                            Behavior on opacity { NumberAnimation { duration: Theme.fast } }
                            Icon {
                                anchors.centerIn: parent
                                glyph: "trash"; size: 15
                                color: delArea.containsMouse ? Theme.danger : Qt.rgba(1, 1, 1, 0.5)
                            }
                            MouseArea {
                                id: delArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: list.removeRequested(slot.index)
                            }
                        }

                        // ── 가사 줄 ──
                        Column {
                            id: lines
                            anchors.centerIn: parent
                            width: card.width - 104

                            Repeater {
                                id: lineRep
                                model: slot.modelData.lines

                                delegate: Item {
                                    id: lineItem
                                    required property string modelData
                                    required property int index
                                    readonly property bool isDragged: drag.active && drag.src
                                                                      && drag.src.slide === slot.index && drag.src.line === index
                                    readonly property real ratio: (list.ratios[slot.index] || [])[index] || 0
                                    readonly property bool wraps: ratio > 1

                                    width: lines.width
                                    height: lineText.height + 6

                                    ToolTip.visible: wraps && lineMouse.containsMouse && !drag.active
                                    ToolTip.delay: 300
                                    ToolTip.text: "PPT에서 두 줄로 나뉘어요 · " + (ratio < 1.005 ? "글상자 폭을 아주 조금 넘어요"
                                                                                     : "글상자 폭의 " + Math.round(ratio * 100) + "%")

                                    Rectangle {
                                        anchors.centerIn: parent
                                        width: Math.min(lineText.contentWidth + 20, parent.width)
                                        height: parent.height
                                        radius: 6
                                        color: lineItem.wraps ? Qt.rgba(1, 0.71, 0.28, lineMouse.containsMouse && !drag.active ? 0.22 : 0.14)
                                             : Qt.rgba(1, 1, 1, lineMouse.containsMouse && lineMouse.draggable && !drag.active ? 0.08 : 0)
                                        Behavior on color { ColorAnimation { duration: Theme.fast } }
                                    }

                                    // PPT 줄바꿈 경고 (왼쪽 여백, 나누기 가위 버튼과 겹치지 않는 자리)
                                    Icon {
                                        visible: lineItem.wraps
                                        x: -22
                                        anchors.verticalCenter: parent.verticalCenter
                                        glyph: "alert"; size: 14
                                        color: Theme.slideWarning
                                    }

                                    Text {
                                        id: lineText
                                        anchors.centerIn: parent
                                        width: parent.width
                                        text: lineItem.modelData
                                        color: lineItem.wraps ? Theme.slideWarning : "white"
                                        font.family: Theme.font
                                        font.pixelSize: 14
                                        font.weight: Font.Bold
                                        lineHeight: 1.15
                                        wrapMode: Text.WordWrap
                                        horizontalAlignment: Text.AlignHCenter
                                        opacity: lineItem.isDragged ? 0.25 : 1
                                    }

                                    // 줄 잡고 끌기 (조금 움직여야 드래그, 그 전엔 클릭)
                                    // 옆 슬라이드로 옮길 수 있는 첫 줄·마지막 줄만 잡힌다
                                    MouseArea {
                                        id: lineMouse
                                        readonly property bool draggable: lineItem.index === 0
                                                                          || lineItem.index === lineRep.count - 1
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        preventStealing: draggable
                                        cursorShape: drag.active ? Qt.ClosedHandCursor
                                                   : draggable ? Qt.OpenHandCursor : Qt.PointingHandCursor
                                        property point start
                                        property bool moved: false

                                        onPressed: (mouse) => {
                                            start = mapToItem(null, mouse.x, mouse.y)
                                            moved = false
                                        }
                                        onPositionChanged: (mouse) => {
                                            if (!pressed || !draggable) return
                                            const p = mapToItem(null, mouse.x, mouse.y)
                                            if (!moved) {
                                                if (Math.hypot(p.x - start.x, p.y - start.y) < 5) return
                                                moved = true
                                                list.beginDrag(slot.index, lineItem.index, lineItem.modelData, p)
                                            } else {
                                                list.moveDrag(p)
                                            }
                                        }
                                        onReleased: if (moved) list.endDrag()
                                        onCanceled: if (moved) list.cancelDrag()
                                        onClicked: if (!moved) list.revealRequested(slot.index)
                                    }

                                    // 줄 사이: 클릭하면 여기서 나누기
                                    Item {
                                        visible: lineItem.index > 0
                                        x: -(card.width - lines.width) / 2
                                        y: -6
                                        width: card.width
                                        height: 12
                                        z: 2

                                        MouseArea {
                                            id: cutArea
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            enabled: !drag.active
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: list.cutRequested(slot.index, lineItem.index)
                                        }
                                        Shape {
                                            anchors.fill: parent
                                            opacity: cutArea.containsMouse ? 1 : card.hovered ? 0.2 : 0
                                            Behavior on opacity { NumberAnimation { duration: Theme.fast } }
                                            ShapePath {
                                                strokeColor: cutArea.containsMouse ? Theme.primary : Qt.rgba(1, 1, 1, 0.5)
                                                strokeWidth: 1.5
                                                strokeStyle: ShapePath.DashLine
                                                dashPattern: [3, 3]
                                                fillColor: "transparent"
                                                startX: 16; startY: 6
                                                PathLine { x: cutArea.width - 16; y: 6 }
                                            }
                                        }
                                        Rectangle {
                                            x: 6
                                            anchors.verticalCenter: parent.verticalCenter
                                            width: 22; height: 22; radius: 11
                                            color: Theme.primary
                                            opacity: cutArea.containsMouse ? 1 : 0
                                            scale: cutArea.containsMouse ? 1 : 0.8
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

        // 놓을 위치 표시 (col 좌표 기준)
        Item {
            id: indicator
            property bool isNew: false
            property real lineY: 0
            visible: false
            z: 10
            x: col.x + (isNew ? col.width * 0.2 : 28)
            width: isNew ? col.width * 0.6 : col.width - 56
            y: col.y + lineY - height / 2
            height: isNew ? 26 : 3

            Rectangle {
                anchors.fill: parent
                visible: !indicator.isNew
                radius: 2
                color: Theme.primary
                Rectangle { x: -4; anchors.verticalCenter: parent.verticalCenter; width: 9; height: 9; radius: 4.5; color: Theme.primary }
                Rectangle { x: parent.width - 5; anchors.verticalCenter: parent.verticalCenter; width: 9; height: 9; radius: 4.5; color: Theme.primary }
            }
            Rectangle {
                anchors.fill: parent
                visible: indicator.isNew
                radius: 8
                color: Theme.surface
                border.width: 1.5
                border.color: Theme.primary
                Text {
                    anchors.centerIn: parent
                    text: "＋ 새 슬라이드로"
                    color: Theme.primary
                    font.family: Theme.font
                    font.pixelSize: 12
                    font.weight: Font.Bold
                }
            }
        }
    }

    // 끌고 있는 줄 (창 전체 위에 표시)
    Rectangle {
        id: ghost
        parent: Overlay.overlay
        visible: drag.active
        x: drag.pointer.x + 14
        y: drag.pointer.y - 18
        z: 1000
        width: Math.min(ghostLabel.implicitWidth + 28, 360)
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
            color: "white"
            font.family: Theme.font
            font.pixelSize: 14
            font.weight: Font.Bold
        }
    }
}
