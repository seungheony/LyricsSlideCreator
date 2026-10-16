import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import "."

// 튜토리얼: 설명할 부분만 밝게 남기고 나머지를 어둡게 덮은 뒤, 옆에 단계별 설명 카드를 띄운다.
// start([{ target: Item(없으면 가운데 카드만), title, body(StyledText), demo: Component(선택) }, ...])
// demo는 강조 영역 위에 그대로 겹쳐 만들어져, 실제 화면 위에서 예시 동작을 재생한다 (Demo.qml)
// enter / leave(선택): 그 단계에 들어설 때·떠날 때(다른 단계로, 닫을 때) 부르는 함수 (예: 서랍을 열어 보여 주고 다시 닫기).
//   target은 함수여도 된다(enter 뒤에 생기는 화면 요소)
// opts.required: 첫 실행·업데이트 후 첫 실행용. 닫기·Esc·건너뛰기 없이 마지막 단계의 "완료"까지 본다(끝까지 보면 opts.onFinished()).
//   ? 버튼으로 연 튜토리얼은 "건너뛰기"·Esc로 언제든 닫는다.
// opts.badge: 진행 표시 앞에 붙일 말 (업데이트 후 '새로 바뀐 점')
Popup {
    id: tour
    objectName: "tour"

    property var steps: []
    property int index: 0
    readonly property var step: steps[index] || null
    readonly property Item target: !step ? null : typeof step.target === "function" ? step.target() : (step.target || null)
    readonly property bool hasTarget: !!target

    // 단계 진입·이탈 (enter / leave)
    property var entered: null
    function leaveStep() {
        const st = entered
        entered = null
        if (st && st.leave) st.leave()
    }
    onStepChanged: {
        if (!visible) return
        leaveStep()
        entered = step
        if (step && step.enter) {
            step.enter()
            Qt.callLater(() => tour.contentItem.forceActiveFocus())    // 연 화면이 포커스를 가져가도 ←→·Enter가 튜토리얼로 오게
        }
    }
    onAboutToShow: { entered = step; if (step && step.enter) step.enter() }
    onAboutToHide: leaveStep()

    property bool required: false
    property string badge: ""
    property var onFinished: null

    function start(newSteps, opts) {
        opts = opts || {}
        steps = newSteps
        index = 0
        required = !!opts.required
        badge = opts.badge || ""
        onFinished = opts.onFinished || null
        open()
    }
    function next() {
        if (index < steps.length - 1) { index++; return }
        const done = onFinished
        onFinished = null
        close()
        if (done) done()
    }
    // ? 버튼으로 연 튜토리얼만 (첫 실행은 끝까지 본다)
    function skip() {
        if (required) return
        onFinished = null
        close()
    }
    readonly property int pad: 6     // 강조 영역이 대상보다 넓은 정도
    function prev() { if (index > 0) index-- }

    onOpened: contentItem.forceActiveFocus()

    parent: Overlay.overlay
    x: 0
    y: 0
    width: parent ? parent.width : 0
    height: parent ? parent.height : 0
    padding: 0
    modal: true
    focus: true
    closePolicy: required ? Popup.NoAutoClose : Popup.CloseOnEscape
    Overlay.modal: Item {}    // 어둡게 덮는 건 강조 영역에 구멍을 내야 해서 직접 그린다
    background: null

    enter: Transition { NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 200 } }
    exit: Transition { NumberAnimation { property: "opacity"; to: 0; duration: 150 } }

    // 강조할 영역 (창 좌표). 화면 전환·창 크기 변경으로 대상이 움직여도 따라가도록 열려 있는 동안 주기적으로 다시 계산한다
    property int refresh: 0
    Timer { interval: 100; repeat: true; running: tour.visible; onTriggered: tour.refresh++ }
    readonly property rect hole: {
        const w = tour.width, h = tour.height, _ = tour.refresh
        const t = tour.target
        if (!t || !tour.visible) return Qt.rect(w / 2, h / 2, 0, 0)
        const p = t.mapToItem(tour.parent, 0, 0)
        // 창 가장자리에 붙은 대상도 강조 테두리가 보이게 창 안으로 줄인다
        const x1 = Math.max(2, p.x - pad), y1 = Math.max(2, p.y - pad)
        const x2 = Math.min(w - 2, p.x + t.width + pad), y2 = Math.min(h - 2, p.y + t.height + pad)
        return Qt.rect(x1, y1, Math.max(0, x2 - x1), Math.max(0, y2 - y1))
    }

    // 설명 카드: 폭은 강조 영역 옆에 남은 자리에 맞춰 260~360으로 줄인다
    readonly property int cardMargin: 16
    readonly property int cardGap: 16
    readonly property int cardMinWidth: 260
    readonly property real rightSpace: width - cardMargin - (hole.x + hole.width + cardGap)
    readonly property real leftSpace: hole.x - cardGap - cardMargin
    readonly property real cardWidth: {
        const full = Math.min(360, Math.max(0, width - cardMargin * 2))
        if (!hasTarget) return full
        if (rightSpace >= cardMinWidth) return Math.min(360, rightSpace)
        if (leftSpace >= cardMinWidth) return Math.min(360, leftSpace)
        return full
    }

    // 설명 카드 위치: 강조 영역의 오른쪽 → 왼쪽 → 아래 → 위 순서로 들어갈 자리를 찾는다.
    // 어디에도 들어가지 않으면 강조 영역 밖(남은 자리가 더 넓은 쪽 화면 가장자리)에 붙여, 강조 영역과 예시를 최대한 덜 가린다
    function cardPos(cw, ch) {
        const m = cardMargin, gap = cardGap, W = width, H = height, r = hole
        const clampX = (v) => Math.max(m, Math.min(W - cw - m, v))
        const clampY = (v) => Math.max(m, Math.min(H - ch - m, v))
        if (!hasTarget) return Qt.point((W - cw) / 2, (H - ch) / 2)
        if (rightSpace >= cardMinWidth) return Qt.point(r.x + r.width + gap, clampY(r.y))
        if (leftSpace >= cardMinWidth) return Qt.point(r.x - gap - cw, clampY(r.y))
        if (r.y + r.height + gap + ch <= H - m) return Qt.point(clampX(r.x + r.width / 2 - cw / 2), r.y + r.height + gap)
        if (r.y - gap - ch >= m) return Qt.point(clampX(r.x + r.width / 2 - cw / 2), r.y - gap - ch)
        return Qt.point(rightSpace >= leftSpace ? W - cw - m : m, clampY(r.y + r.height / 2 - ch / 2))
    }

    contentItem: Item {
        focus: true
        Keys.onLeftPressed: tour.prev()
        Keys.onRightPressed: tour.next()
        Keys.onReturnPressed: tour.next()
        Keys.onEnterPressed: tour.next()

        // 아래 화면 클릭 막기
        MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons; onWheel: (wheel) => wheel.accepted = true }

        // ── 강조 영역 (움직일 때 부드럽게) ──
        Item {
            id: spot
            x: tour.hole.x
            y: tour.hole.y
            width: tour.hole.width
            height: tour.hole.height
            Behavior on x { NumberAnimation { duration: Theme.normal; easing.type: Easing.OutCubic } }
            Behavior on y { NumberAnimation { duration: Theme.normal; easing.type: Easing.OutCubic } }
            Behavior on width { NumberAnimation { duration: Theme.normal; easing.type: Easing.OutCubic } }
            Behavior on height { NumberAnimation { duration: Theme.normal; easing.type: Easing.OutCubic } }
        }

        // 구멍 주위 네 방향을 어둡게
        readonly property color dim: Qt.rgba(0, 0, 0, 0.55)
        Rectangle { color: parent.dim; x: 0; y: 0; width: parent.width; height: Math.max(0, spot.y) }
        Rectangle { color: parent.dim; x: 0; y: spot.y + spot.height; width: parent.width; height: Math.max(0, parent.height - y) }
        Rectangle { color: parent.dim; x: 0; y: spot.y; width: Math.max(0, spot.x); height: spot.height }
        Rectangle { color: parent.dim; x: spot.x + spot.width; y: spot.y; width: Math.max(0, parent.width - x); height: spot.height }

        // ── 예시 동작 ── 강조 영역이 자리를 잡은 뒤에 만들어, 대상 위치를 정확히 계산할 수 있게 한다
        // (바인딩으로 두면 단계가 바뀌는 순간 새 예시가 이전 위치에 잠깐 만들어져 깜빡이므로 직접 넣고 뺀다)
        Loader {
            id: demoLoader
            x: tour.hole.x
            y: tour.hole.y
            width: tour.hole.width
            height: tour.hole.height
            Timer {
                id: demoDelay
                interval: Theme.normal + 60
                onTriggered: demoLoader.sourceComponent = tour.step && tour.step.demo ? tour.step.demo : null
            }
            Connections {
                target: tour
                function onStepChanged() { demoLoader.sourceComponent = null; demoDelay.restart() }
                function onAboutToHide() { demoDelay.stop(); demoLoader.sourceComponent = null }
            }
        }

        // 강조 테두리: 예시(불투명한 복제본) 위에 그려야 가려지지 않는다
        Rectangle {
            visible: tour.hasTarget
            x: spot.x; y: spot.y; width: spot.width; height: spot.height
            radius: 6
            color: "transparent"
            border.width: 2
            border.color: Theme.primary
        }

        // ── 설명 카드 ──
        Rectangle {
            id: card
            readonly property point pos: tour.cardPos(width, height)
            x: pos.x
            y: pos.y
            width: tour.cardWidth
            height: body.implicitHeight + 40
            radius: 16
            color: Theme.surface
            border.width: 1
            border.color: Theme.border
            Behavior on x { NumberAnimation { duration: Theme.normal; easing.type: Easing.OutCubic } }
            Behavior on y { NumberAnimation { duration: Theme.normal; easing.type: Easing.OutCubic } }

            ColumnLayout {
                id: body
                x: 20
                y: 20
                width: card.width - 40
                spacing: 8

                RowLayout {
                    Layout.fillWidth: true
                    Text {
                        text: (tour.badge ? tour.badge + " · " : "") + (tour.index + 1) + " / " + tour.steps.length
                        color: Theme.primaryText
                        font.family: Theme.font
                        font.pixelSize: 12
                        font.weight: Font.Bold
                    }
                    Item { Layout.fillWidth: true }
                }

                BalancedText {
                    maxWidth: parent.width
                    Layout.preferredWidth: fitWidth
                    source: tour.step ? tour.step.title : ""
                    color: Theme.text
                    font.family: Theme.font
                    font.pixelSize: 17
                    font.weight: Font.Bold
                }

                BalancedText {
                    maxWidth: parent.width
                    Layout.preferredWidth: fitWidth
                    source: tour.step ? tour.step.body : ""
                    textFormat: Text.StyledText
                    color: Theme.text2
                    font.family: Theme.font
                    font.pixelSize: 13
                    lineHeight: 1.45
                }

                // 진행: 단계가 적으면 점, 많으면(점이 버튼 자리를 밀어내므로) 가는 막대
                Rectangle {
                    visible: tour.steps.length > 8
                    Layout.fillWidth: true
                    Layout.topMargin: 10
                    implicitHeight: 4
                    radius: 2
                    color: Theme.border
                    Rectangle {
                        width: parent.width * (tour.index + 1) / Math.max(1, tour.steps.length)
                        height: parent.height
                        radius: 2
                        color: Theme.primary
                        Behavior on width { NumberAnimation { duration: Theme.fast } }
                    }
                }
                RowLayout {
                    Layout.fillWidth: true
                    Layout.topMargin: tour.steps.length > 8 ? 4 : 10
                    spacing: 6
                    Row {
                        spacing: 5
                        visible: tour.steps.length > 1 && tour.steps.length <= 8
                        Repeater {
                            model: tour.steps.length
                            delegate: Rectangle {
                                required property int index
                                width: index === tour.index ? 16 : 6
                                height: 6
                                radius: 3
                                color: index === tour.index ? Theme.primary : Theme.border
                                Behavior on width { NumberAnimation { duration: Theme.fast } }
                            }
                        }
                    }
                    Item { Layout.fillWidth: true }
                    AppButton {
                        text: "건너뛰기"; variant: "ghost"; size: "small"
                        visible: !tour.required && tour.index < tour.steps.length - 1
                        onClicked: tour.skip()
                    }
                    AppButton {
                        text: "이전"; variant: "ghost"; size: "small"
                        visible: tour.index > 0
                        onClicked: tour.prev()
                    }
                    AppButton {
                        text: tour.index < tour.steps.length - 1 ? "다음" : "완료"
                        variant: "primary"; size: "small"
                        onClicked: tour.next()
                    }
                }
            }
        }
    }
}
