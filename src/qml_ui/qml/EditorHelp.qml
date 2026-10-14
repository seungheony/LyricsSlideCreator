import QtQuick
import "."

// 편집 화면의 ? 버튼 튜토리얼: 단계별 설명과, 실제 화면 위에서 재생하는 예시 동작(Demo).
// 예시는 지금 불러온 곡의 가사 줄로 보여주되, 실제 가사·슬라이드는 건드리지 않는다.
QtObject {
    id: help

    property var tour: null
    property var blocks: []
    property bool keepTwo: false
    // 강조·포인터 대상 (EditorPage의 실제 화면 요소)
    property Item lyricsBox
    property Item autoSplitRow
    property Item slideList
    property Item keepTwoRow
    property Item keepTwoBox
    property Item historyRow
    property Item templateRow
    property Item templateButton
    property bool customTemplate: false
    property Item generateButton

    // 예시용 가사 줄: 지금 가사의 앞부분, 모자라면 "가사 N"
    function sampleLines(n) {
        const all = blocks.reduce((acc, b) => acc.concat(b.lines), [])
        const lines = []
        for (let i = 0; i < n; i++) lines.push(all[i] || ("가사 " + (i + 1)))
        return lines
    }

    function childWithText(row, text) {
        for (let i = 0; i < row.children.length; i++)
            if (row.children[i].text === text) return row.children[i]
        return row
    }

    // ── 튜토리얼 ── (? 버튼마다 해당 부분만, 처음 들어왔을 때는 전부 이어서)
    function lyrics() { tour.start(lyricsSteps()) }
    function slides() { tour.start(slidesSteps()) }
    function keepTwoHelp() { tour.start(keepTwoSteps()) }
    function generate() { tour.start(generateSteps()) }
    function firstRun(onFinished, onSkipped) {
        tour.start(lyricsSteps().concat(slidesSteps(), keepTwoSteps(), generateSteps()),
                   { required: true, onFinished: onFinished, onSkipped: onSkipped })
    }

    function lyricsSteps() {
        return [
            { target: lyricsBox, demo: lyricsDemo, title: "가사가 곧 슬라이드예요",
              body: "<b>빈 줄</b>로 구분된 덩어리 하나가 슬라이드 한 장이 돼요. 가사를 고치면 오른쪽 미리보기에 바로 반영돼요." },
            { target: autoSplitRow, demo: autoSplitDemo, title: "자동 나누기",
              body: "가사 전체를 처음부터 <b>1줄씩</b> 또는 <b>2줄씩</b> 다시 나눠요. 곡을 처음 불러오면 2줄씩 나뉘어 있어요.<br>"
                  + "직접 나눈 것은 사라지지만 <b>되돌리기(" + Theme.undoKey + ")</b>로 되돌릴 수 있어요." }
        ]
    }

    function slidesSteps() {
        return [
            { target: slideList, demo: previewDemo, title: "슬라이드 미리보기",
              body: "PPT에 들어갈 슬라이드를 한 장씩 보여줘요.<br>"
                  + "슬라이드를 누르면 왼쪽 가사에서 그 부분이 선택되고, 마우스를 올리면 나오는 <b>휴지통</b>으로 지울 수 있어요." },
            { target: slideList, demo: cutJoinDemo, title: "나누기 · 합치기",
              body: "슬라이드 안 <b>줄 사이</b>에 마우스를 올리면 <b>✂</b>가, <b>슬라이드 사이</b>에 올리면 <b>합치기</b>가 나타나요. "
                  + "누르면 거기서 나누거나 두 장을 합쳐요." },
            { target: slideList, demo: dragDemo, title: "줄 옮기기 (드래그)",
              body: "<b>첫 줄</b>은 앞 슬라이드로, <b>마지막 줄</b>은 뒤 슬라이드로 끌어서 옮길 수 있어요. "
                  + "슬라이드 <b>사이</b>에 놓으면 새 슬라이드가 돼요." },
            { target: historyRow, demo: historyDemo, title: "되돌리기",
              body: "모든 편집은 되돌릴 수 있어요. <b>" + Theme.undoKey + "</b> 되돌리기, <b>"
                  + Theme.redoKey + "</b> 다시 실행." }
        ]
    }

    function keepTwoSteps() {
        return [
            { target: keepTwoRow, demo: keepTwoToggleDemo, title: "2줄 유지란?",
              body: "줄을 옆 슬라이드로 옮길 때, <b>넘치는 줄을 밀어서 2줄씩 다시 맞춰주는</b> 옵션이에요. "
                  + "가사 짝이 한 줄씩 어긋나 있을 때, 한 줄만 옮겨서 뒤쪽을 한 번에 바로잡을 수 있어요. 기본으로 켜져 있어요." },
            { target: slideList, demo: dragDemo, title: "꺼져 있으면",
              body: "옮긴 줄만 움직여요. 받은 슬라이드는 3줄, 준 슬라이드는 1줄이 된 채로 남아요." },
            { target: slideList, demo: keepTwoDragDemo, title: "켜져 있으면",
              body: "예: 첫 슬라이드의 마지막 줄을 뒤 슬라이드로 옮기면, 3줄이 된 슬라이드는 넘친 줄을 <b>같은 방향</b>으로 밀어내서 뒤쪽 슬라이드가 모두 <b>2줄씩 다시 맞춰져요</b>. "
                  + "줄을 준 슬라이드는 채우지 않고 <b>1줄</b>로 남아요." }
        ]
    }

    function generateSteps() {
        return [
            customTemplate
                ? { target: templateRow, demo: templateDemo, title: "템플릿",
                    body: "PPT의 배경·글꼴·글자 위치를 정하는 파일이에요. "
                        + "템플릿 첫 슬라이드에서 <b>'가사'</b>라고 적힌 글상자 자리에 각 슬라이드의 가사가 들어가요.<br>"
                        + "<b>변경</b>을 눌러 내 템플릿(.pptx)으로 바꿀 수 있어요." }
                : { target: templateRow, title: "템플릿",
                    body: "PPT의 배경·글꼴·글자 위치를 정하는 파일이에요. 지금은 <b>기본 템플릿</b>으로 만들어지고, "
                        + "내 템플릿은 나중에 지원할 예정이에요." },
            { target: generateButton, demo: generateDemo, title: "PPT 생성",
              body: "저장할 위치를 고르면 미리보기의 슬라이드 수만큼 PPT가 만들어져요.<br>단축키: <b>"
                  + Theme.mod + "Enter</b>" }
        ]
    }

    // ── 예시 동작 ──

    // 가사 입력칸: 줄 끝에서 Enter로 빈 줄을 넣어 나누고, 지워서 다시 합친다
    property Component lyricsDemo: Component {
        Demo {
            id: d
            readonly property var lines: help.sampleLines(4)
            property string key: ""
            property bool caret: false

            Rectangle { anchors.fill: parent; color: Theme.bg }
            Rectangle {
                id: box
                anchors.fill: parent
                anchors.margins: help.tour.pad
                radius: Theme.radius
                color: Theme.surface
                border.width: 1.5
                border.color: Theme.focusBorder

                ListView {
                    id: textView
                    x: 16
                    y: 16
                    width: parent.width - 32
                    height: parent.height - 32
                    interactive: false
                    model: ListModel { id: textModel }
                    add: Transition { NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 200 } }
                    remove: Transition { NumberAnimation { property: "opacity"; to: 0; duration: 200 } }
                    displaced: Transition { NumberAnimation { property: "y"; duration: 250; easing.type: Easing.OutCubic } }
                    delegate: Text {
                        required property string line
                        width: ListView.view.width
                        text: line || " "
                        color: Theme.text
                        font.family: Theme.font
                        font.pixelSize: 14
                    }
                }

                // 커서
                Rectangle {
                    id: caretBar
                    visible: d.caret
                    width: 1.5
                    height: 17
                    color: Theme.text
                    SequentialAnimation on opacity {
                        loops: Animation.Infinite
                        running: d.caret
                        PropertyAction { value: 1 }
                        PauseAnimation { duration: 500 }
                        PropertyAction { value: 0 }
                        PauseAnimation { duration: 500 }
                    }
                }

                // 누른 키
                Rectangle {
                    visible: d.key !== ""
                    x: caretBar.x + 16
                    y: caretBar.y - 3
                    width: keyText.implicitWidth + 16
                    height: 24
                    radius: 6
                    color: Theme.surface2
                    border.width: 1
                    border.color: Theme.border
                    Text {
                        id: keyText
                        anchors.centerIn: parent
                        text: d.key
                        color: Theme.text
                        font.family: Theme.font
                        font.pixelSize: 12
                        font.weight: Font.Bold
                    }
                }
            }

            // 첫 줄 끝 위치 (box 좌표)
            function lineEnd(i) {
                const it = textView.itemAtIndex(i)
                const p = it.mapToItem(box, it.contentWidth, 0)
                return Qt.point(p.x + 2, p.y)
            }

            onReset: {
                textModel.clear()
                for (const l of [lines[0], lines[1], "", lines[2], lines[3]]) textModel.append({ line: l })
                caret = false
                key = ""
                d.jumpTo(box, 0.75, 0.75)
            }
            script: [
                [600, () => { const p = d.lineEnd(0); d.moveToXY(box, p.x, p.y + 9) }],
                [750, () => { d.click(); const p = d.lineEnd(0); caretBar.x = p.x; caretBar.y = p.y; d.caret = true }],
                [700, () => { d.key = "Enter" }],
                [350, () => { textModel.insert(1, { line: "" }); d.caret = false }],
                [500, () => { d.key = ""; const p = d.lineEnd(1); caretBar.x = p.x - 2; caretBar.y = p.y + 17; d.caret = true }],
                [1400, () => { d.key = "⌫ 지우기" }],
                [350, () => { textModel.remove(1); const p = d.lineEnd(0); caretBar.x = p.x; caretBar.y = p.y }],
                [600, () => { d.key = "" }]
            ]
        }
    }

    // 실제 버튼 위에서 누르는 모습만 보여준다
    property Component autoSplitDemo: Component {
        Demo {
            id: d
            onReset: d.jumpTo(help.autoSplitRow, 0.2, 1.8)
            script: [
                [500, () => d.moveTo(help.childWithText(help.autoSplitRow, "1줄"))],
                [750, () => d.click()],
                [900, () => d.moveTo(help.childWithText(help.autoSplitRow, "2줄"))],
                [750, () => d.click()]
            ]
        }
    }

    property Component historyDemo: Component {
        Demo {
            id: d
            onReset: d.jumpTo(help.historyRow, 0.1, 2)
            script: [
                [500, () => d.moveTo(help.historyRow.children[0])],
                [750, () => d.click()],
                [900, () => d.moveTo(help.historyRow.children[1])],
                [750, () => d.click()]
            ]
        }
    }

    property Component keepTwoToggleDemo: Component {
        Demo {
            id: d
            property bool checked: help.keepTwo
            // 실제 체크박스 위에 바뀐 상태를 그린다
            Rectangle {
                id: mark
                readonly property point pos: help.keepTwoBox.indicator.mapToItem(d, 0, 0)
                x: pos.x; y: pos.y
                width: 16; height: 16; radius: 4
                color: d.checked ? Theme.primary : Theme.surface
                border.width: d.checked ? 0 : 1.5
                border.color: Theme.border
                Icon { anchors.centerIn: parent; visible: d.checked; glyph: "check"; size: 11; color: "white" }
            }
            onReset: { checked = help.keepTwo; d.jumpTo(help.keepTwoBox, 0.5, 2) }
            script: [
                [500, () => d.moveTo(mark)],
                [750, () => { d.click(); d.checked = !d.checked }],
                [1300, () => { d.click(); d.checked = !d.checked }]
            ]
        }
    }

    property Component templateDemo: Component {
        Demo {
            id: d
            onReset: d.jumpTo(help.templateRow, 0.5, 2)
            script: [
                [500, () => d.moveTo(help.templateButton)],
                [750, () => d.click()]
            ]
        }
    }

    property Component generateDemo: Component {
        Demo {
            id: d
            onReset: d.jumpTo(help.generateButton, 0.2, 1.6)
            script: [
                [500, () => d.moveTo(help.generateButton, 0.6, 0.55)],
                [750, () => d.click()]
            ]
        }
    }

    // 슬라이드 목록 복제본 위에서 재생하는 예시들
    // 클릭 → 선택, 마우스를 올려 휴지통 → 삭제
    property Component previewDemo: Component {
        Demo {
            id: d
            readonly property var l: help.sampleLines(6)
            Rectangle { anchors.fill: parent; color: Theme.bg }
            DemoSlides { id: s; anchors.fill: parent; anchors.margins: help.tour.pad }
            onReset: {
                s.clearMarks()
                s.setGroups([[l[0], l[1]], [l[2], l[3]], [l[4], l[5]]])
                d.jumpTo(s, 0.8, 0.95)
            }
            script: [
                [500, () => d.moveTo(s.card(1), 0.5, 0.55)],
                [700, () => { s.hover = 1; s.pressedSlide = 1; d.click() }],
                [160, () => { s.pressedSlide = -1; s.active = 1 }],
                [1100, () => d.moveTo(s.trash(1))],
                [650, () => { s.trashHot = true }],
                [350, () => d.click()],
                [180, () => { s.clearMarks(); s.removeAt(1) }]
            ]
        }
    }

    // 줄 사이 ✂ → 나누기, 슬라이드 사이 합치기 → 합치기
    property Component cutJoinDemo: Component {
        Demo {
            id: d
            readonly property var l: help.sampleLines(4)
            Rectangle { anchors.fill: parent; color: Theme.bg }
            DemoSlides { id: s; anchors.fill: parent; anchors.margins: help.tour.pad }
            onReset: {
                s.clearMarks()
                s.setGroups([[l[0], l[1]], [l[2], l[3]]])
                d.jumpTo(s, 0.8, 0.9)
            }
            script: [
                [500, () => { d.moveTo(s.cutGap(0, 1), 0.5, 0.5) }],
                [650, () => { s.hover = 0; s.cutSlide = 0; s.cutAt = 1 }],
                [500, () => d.moveToXY(s.cutGap(0, 1), 17, 6)],
                [650, () => { s.cutHot = true; d.click() }],
                [200, () => { s.clearMarks(); s.split(0, 1); s.flash(1) }],
                [1200, () => d.moveTo(s.joinGap(1), 0.5, 0.5)],
                [650, () => { s.joinAt = 1 }],
                [600, () => d.click()],
                [200, () => { s.clearMarks(); s.merge(0); s.flash(0) }]
            ]
        }
    }

    // from 슬라이드의 line번째 줄을 to 슬라이드로 끌어다 놓는다 (앞 슬라이드면 끝에, 뒤 슬라이드면 처음에).
    // moved: 놓은 직후 모습
    // chain: 2줄 유지로 넘친 줄이 차례로 밀려나는 과정 [[from, at, to, 바뀐 뒤 모습], ...] (없으면 생략)
    function dragScript(d, s, from, line, to, moved, chain) {
        const forward = to > from
        const steps = [
            [500, () => d.moveTo(s.line(from, line))],
            [700, () => { d.cursor.pressed = true }],
            [250, () => {
                s.dragSlide = from; s.dragLine = line
                d.ghostText = s.linesAt(from)[line]
                d.moveTo(s.card(to), 0.5, forward ? 0.2 : 0.8)
            }],
            [700, () => { s.dropSlide = to; s.dropAtStart = forward }],
            [700, () => {
                d.cursor.pressed = false
                d.ghostText = ""
                s.clearMarks()
                s.applyGroups(moved)
                s.flash(to)
            }]
        ]
        for (const c of chain || [])
            steps.push([c === chain[0] ? 700 : 950, () => s.fly(c[0], c[1], c[2], c[3])])
        return steps
    }

    property Component dragDemo: Component {
        Demo {
            id: d
            readonly property var l: help.sampleLines(6)
            Rectangle { anchors.fill: parent; color: Theme.bg }
            DemoSlides { id: s; anchors.fill: parent; anchors.margins: help.tour.pad }
            onReset: {
                s.clearMarks()
                s.setGroups([[l[0], l[1]], [l[2], l[3]], [l[4], l[5]]])
                d.jumpTo(s, 0.8, 0.95)
            }
            // 둘째 슬라이드의 첫 줄을 앞 슬라이드 끝으로
            script: help.dragScript(d, s, 1, 0, 0, [[l[0], l[1], l[2]], [l[3]], [l[4], l[5]]])
        }
    }

    property Component keepTwoDragDemo: Component {
        Demo {
            id: d
            readonly property var l: help.sampleLines(6)
            Rectangle { anchors.fill: parent; color: Theme.bg }
            DemoSlides { id: s; anchors.fill: parent; anchors.margins: help.tour.pad }
            onReset: {
                s.clearMarks()
                s.setGroups([[l[0], l[1]], [l[2], l[3]], [l[4], l[5]]])
                d.jumpTo(s, 0.8, 0.95)
            }
            // 첫 슬라이드의 마지막 줄을 뒤 슬라이드 처음으로 → 넘친 줄이 뒤로 연쇄해서 밀린다 (editor.js planDrop과 같은 결과)
            script: help.dragScript(d, s, 0, 1, 1, [[l[0]], [l[1], l[2], l[3]], [l[4], l[5]]], [
                [1, 2, 2, [[l[0]], [l[1], l[2]], [l[3], l[4], l[5]]]],
                [2, 2, 3, [[l[0]], [l[1], l[2]], [l[3], l[4]], [l[5]]]]
            ])
        }
    }
}
