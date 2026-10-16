import QtQuick
import QtQuick.Layouts
import "."

// 편집 화면의 튜토리얼: 단계별 설명과, 실제 화면 위에서 재생하는 예시 동작(Demo).
// 예시는 지금 불러온 곡의 가사 줄로 보여주되, 실제 가사·슬라이드는 건드리지 않는다.
// 첫 실행(firstRun)은 매주 쓰는 순서대로 기본 흐름(예배 PPT → 양식 → 가사 → 미리보기 다듬기 → 2줄 유지 → PPT 생성 → 프리셋 저장)을
// 보여 준 뒤, 가끔 쓰는 기능을 '이럴 땐: …'으로 이어서 모두 보여 준다(곡 담기는 서랍 튜토리얼 SongDrawer.showHelp).
// ? 버튼은 그 부분의 기본 흐름 단계 뒤에 관련된 '이럴 땐' 단계를 붙인다.
QtObject {
    id: help

    property var tour: null
    property var blocks: []
    property bool keepTwo: false
    // 강조·포인터 대상 (EditorPage의 실제 화면 요소)
    property Item lyricsBox
    property Item autoSplitRow
    property Item slideList
    property Item keepTwoBox
    property Item historyRow
    property Item templateRow
    property Item templateButton
    property bool customTemplate: false
    property Item generateButton
    property Item savePresetButton
    property Item setlistPanel
    property Item wrapBadge          // '줄바꿈 있음' 표시
    property Item editorBody         // 가사 | 슬라이드 (두 칸을 함께 보이는 예시)
    property Item slidesColumn       // 슬라이드 제목 줄 + 목록
    property Item slidesTitle
    property var editor: null        // EditorPage (서랍을 열어 보여 주는 단계)
    property Item addSongArea        // 콘티 패널 + 서랍 자리

    // item의 자리를 to 좌표로 옮겨 clone을 겹친다 (예시 복제본을 실제 화면 요소 위에)
    function place(clone, item, to) {
        const p = item.mapToItem(to, 0, 0)
        clone.x = p.x; clone.y = p.y; clone.width = item.width; clone.height = item.height
    }

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

    // ── 튜토리얼 ──
    function lyrics() { tour.start(lyricsSteps().concat(autoSplitSteps(), historySteps())) }
    function slides() { tour.start(slideEditSteps().concat(keepTwoSteps(), previewSteps(), wrapSteps())) }
    function generate() { tour.start(templateSteps().concat(generateSteps(), presetSteps())) }
    function setlistHelp() { tour.start(setlistSteps().concat(formSteps(), clearSteps(), staleSteps())) }
    // 첫 실행 단계 전부. 단계마다 rev(기본 1): 업데이트로 새로 만들거나 바꾼 단계는 rev를 올린다
    // (Main이 본 리비전보다 높은 단계만 업데이트 후 첫 실행 때 보여 준다)
    function firstRunSteps() {
        return setlistSteps().concat(formSteps(), lyricsSteps(), slideEditSteps(), keepTwoSteps(), generateSteps(), presetSteps(),
                                     manualSteps(), autoSplitSteps(), previewSteps(), wrapSteps(), historySteps(), clearSteps(), staleSteps())
    }

    // ── 기본 흐름 ──
    function setlistSteps() {
        return [
            { target: setlistPanel, title: "예배 PPT 한눈에 보기",
              body: "위에서부터 순서대로 한 PPT가 돼요.<br>"
                  + "<b>찬양 전</b> 양식 → <b>찬양</b> → <b>찬양 후</b> 양식.<br>"
                  + "곡을 누르면 오른쪽에서 그 곡의 가사를 편집해요. 끌어서 <b>순서</b>를 바꾸고, 목록 <b>밖으로 끌어내면</b> 빠져요(되돌릴 수 있어요). "
                  + "곡을 더 담으려면 <b>곡 추가</b>(" + Theme.mod + "K)를 눌러요." }
        ]
    }

    function formSteps() {
        return [
            { target: setlistPanel.formsRow, title: "매주 쓰는 PPT는 양식으로",
              body: "'예배 준비중'처럼 찬양 <b>전</b>에, 광고·설교처럼 찬양 <b>후</b>에 띄울 PPT를 넣어요. "
                  + "<b>양식 추가</b>를 누르면 <b>양식 보관함</b>이 열리고, 거기서 이 칸으로 끌어다 놓아요. PPT 파일을 칸에 바로 끌어다 놓아도 돼요.<br>"
                  + "넣은 양식은 다음에 앱을 켜도 그대로 있어요." }
        ]
    }

    function lyricsSteps() {
        return [
            { target: editorBody, demo: lyricsDemo, title: "가사가 곧 슬라이드예요",
              body: "<b>빈 줄</b>로 구분된 단락 하나가 슬라이드 한 장이 돼요. 가사를 고치면 오른쪽 미리보기에 바로 반영돼요." }
        ]
    }

    function slideEditSteps() {
        return [
            { target: slideList, demo: cutJoinDemo, title: "미리보기에서 나누고 합치기",
              body: "슬라이드 안 <b>줄 사이</b>에 마우스를 올리면 <b>✂</b>가, <b>슬라이드 사이</b>에 올리면 <b>합치기</b>가 나타나요. "
                  + "누르면 거기서 나누거나 두 장을 합쳐요." },
            { target: slideList, demo: dragDemo, title: "가사를 끌어 옮기기",
              body: "<b>첫 줄</b>은 앞 슬라이드로, <b>마지막 줄</b>은 뒤 슬라이드로 끌어서 옮겨요. "
                  + "슬라이드 <b>사이</b>에 놓으면 새 슬라이드가 돼요." }
        ]
    }

    function keepTwoSteps() {
        return [
            // 체크박스와 슬라이드 목록을 함께 강조하고, 켜진 상태에서 줄 하나를 옮겨 뒤쪽이 2줄씩 다시 맞춰지는 모습을 보인다
            { target: slidesColumn, demo: keepTwoDemo, title: "가사 짝이 한 줄씩 어긋났다면: 2줄 유지",
              body: "켜 두면(기본) 줄을 옮길 때 넘친 줄이 <b>같은 방향</b>으로 밀려서 뒤쪽이 <b>2줄씩</b> 다시 맞춰져요. "
                  + "짝이 한 줄씩 어긋났을 때 한 줄만 옮기면 돼요." }
        ]
    }

    function generateSteps() {
        return [
            { target: generateButton, demo: generateDemo, title: "다 됐으면 PPT 생성",
              body: "저장할 위치를 고르면 양식과 찬양을 순서대로 <b>한 PPT</b>로 만들어요. "
                  + "찬양 앞·곡 사이·끝에는 <b>검은 빈 슬라이드</b>가 들어가요.<br>단축키: <b>" + Theme.mod + "Enter</b>" }
        ]
    }

    function presetSteps() {
        return [
            { target: savePresetButton, title: "다음 주에도 그대로: 프리셋 저장",
              body: "<b>저장</b>(" + Theme.mod + "S)을 누르면 곡마다 지금 슬라이드를 이름을 붙여 <b>보관함</b>에 저장해요. "
                  + "다음에 그 곡을 검색하면 오른쪽에 저장해둔 프리셋 이름이 보이고, 담으면 저장했던 그대로 불러와요. "
                  + "프리셋 이름을 누르면 <b>멜론 가사 그대로</b> 가져오거나 다른 프리셋으로 바꿀 수 있어요. "
                  + "저장한 곡은 곡 추가 화면의 <b>보관함</b> 탭에 있어요." }
        ]
    }

    // 템플릿은 PPT 생성 ? 버튼에서만 (지금은 기본 템플릿뿐이라 첫 실행에서는 뺀다)
    function templateSteps() {
        return [
            customTemplate
                ? { target: templateRow, demo: templateDemo, title: "템플릿",
                    body: "PPT의 배경·글꼴·글자 위치를 정하는 파일이에요. "
                        + "템플릿 첫 슬라이드에서 <b>'가사'</b>라고 적힌 글상자 자리에 각 슬라이드의 가사가 들어가요.<br>"
                        + "<b>변경</b>을 눌러 내 템플릿(.pptx)으로 바꿀 수 있어요." }
                : { target: templateRow, title: "템플릿",
                    body: "PPT의 배경·글꼴·글자 위치를 정하는 파일이에요. 지금은 <b>기본 템플릿</b>으로 만들어지고, "
                        + "내 템플릿은 나중에 지원할 예정이에요." }
        ]
    }

    // ── 가끔 쓰는 기능: 이럴 땐 ──
    function manualSteps() {
        return [
            // 예시가 '곡 추가'를 눌러 서랍을 실제로 열고 직접 입력 탭에서 입력하는 모습을 보인다(입력은 복제본).
            // 반복할 때마다 서랍을 닫았다 열고, 다음 단계로 가거나 튜토리얼을 닫으면 서랍을 닫는다
            { target: addSongArea, demo: manualDemo, title: "멜론에 찾는 곡이 없을 때",
              leave: () => editor.closeDrawer(false),
              body: "<b>곡 추가</b> → <b>직접 입력</b> 탭에서 제목과 가사를 붙여 넣고 <b>콘티에 담기</b>를 누르면 2줄씩 나뉘어 담겨요. "
                  + "직접 입력한 곡도 프리셋으로 저장하면 검색 결과와 보관함에서 다시 찾을 수 있어요." }
        ]
    }

    function autoSplitSteps() {
        return [
            { target: autoSplitRow, demo: autoSplitDemo, title: "가사를 처음부터 다시 나누고 싶을 때",
              body: "가사 전체를 <b>1줄씩</b> 또는 <b>2줄씩</b> 다시 나눠요. 곡을 처음 담으면 2줄씩 나뉘어 있어요.<br>"
                  + "<b>되돌리기(" + Theme.undoKey + ")</b>로 되돌릴 수 있어요." }
        ]
    }

    function previewSteps() {
        return [
            { target: editorBody, demo: findDemo, title: "가사 위치를 찾을 때",
              body: "가사를 누르면 그 단락의 슬라이드가 <b>초록 테두리</b>로 표시돼요. "
                  + "거꾸로 슬라이드를 누르면 왼쪽 가사에서 그 부분이 <b>선택</b>돼요." }
        ]
    }

    function wrapSteps() {
        return [
            { target: slidesColumn, demo: wrapDemo, title: "줄바꿈 경고",
              body: "한줄에 들어가는 텍스트가 너무 길어서 실제 PPT 화면에는 <b>두 줄로 나뉘는 줄</b>이 있다는 뜻이에요. 그 줄은 <b>주황색</b>으로 보이고, "
                  + "위의 <b>줄바꿈 있음</b>을 누르면 그 슬라이드를 차례로 보여 줘요. "
                  + "그 줄을 짧게 고치거나 나누면 사라져요." }
        ]
    }

    function historySteps() {
        return [
            { target: historyRow, demo: historyDemo, title: "되돌리기",
              body: "모든 편집은 되돌릴 수 있어요. <b>" + Theme.undoKey + "</b> 되돌리기, <b>"
                  + Theme.redoKey + "</b> 다시 실행." }
        ]
    }

    function clearSteps() {
        return [
            { target: setlistPanel, demo: clearDemo, title: "초기화",
              body: "<b>⋯</b> 메뉴의 <b>콘티 비우기</b>로 곡을 모두 빼요. 아래 알림의 <b>되돌리기</b>로 바로 되돌릴 수 있고, "
                  + "편집하던 곡은 다시 담으면 이어서 편집돼요." }
        ]
    }

    function staleSteps() {
        return [
            { target: setlistPanel.formsRow, demo: staleDemo, title: "양식에 ⚠가 보이면",
              body: "파일로 넣은 양식을 <b>6일 넘게</b> 고치지 않았다는 뜻이에요. 마우스를 올리면 언제 고친 파일인지 보여요. 지난주 설교 PPT가 그대로 들어가지 않았는지 확인해 주세요.<br>"
                  + "줄 오른쪽 <b>보관함</b> 아이콘으로 양식 보관함에 넣어 둔 양식은 보관할 때의 파일을 그대로 써서 ⚠가 뜨지 않아요." }
        ]
    }

    // ── 예시 동작 ──

    // 가사 칸 복제본 (예시용): 줄 목록 · 커서 · 누른 키 · 선택 표시. 실제 가사 칸과 같은 글꼴·여백
    component LyricsClone: Rectangle {
        id: lc
        readonly property ListModel lines: lcModel
        property bool caret: false
        property real caretX: 0
        property real caretY: 0
        property string key: ""
        radius: Theme.radius
        color: Theme.surface
        border.width: 1.5
        border.color: Theme.focusBorder
        function setLines(arr) {
            lcModel.clear()
            for (const l of arr) lcModel.append({ line: l, sel: false })
        }
        function item(i) { return lcView.itemAtIndex(i) }
        // i번째 줄 끝 (lc 좌표)
        function lineEnd(i) {
            const it = item(i)
            const p = it.mapToItem(lc, it.textWidth, 0)
            return Qt.point(p.x + 2, p.y)
        }
        function selectLines(from, to) {
            for (let i = 0; i < lcModel.count; i++) lcModel.setProperty(i, "sel", i >= from && i <= to)
        }
        ListModel { id: lcModel }
        ListView {
            id: lcView
            x: 15
            y: 15
            width: parent.width - 30
            height: parent.height - 30
            interactive: false
            clip: true
            model: lcModel
            add: Transition { NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 200 } }
            remove: Transition { NumberAnimation { property: "opacity"; to: 0; duration: 200 } }
            displaced: Transition { NumberAnimation { property: "y"; duration: 250; easing.type: Easing.OutCubic } }
            delegate: Item {
                required property string line
                required property bool sel
                readonly property real textWidth: lineText.contentWidth
                width: ListView.view.width
                height: lineText.implicitHeight
                Rectangle { visible: sel; width: Math.max(lineText.contentWidth, 6); height: parent.height; color: Theme.primarySoft }
                Text { id: lineText; text: line || " "; color: Theme.text; font.family: Theme.font; font.pixelSize: 14 }
            }
        }
        Rectangle {
            visible: lc.caret
            x: lc.caretX
            y: lc.caretY
            width: 1.5
            height: 17
            color: Theme.text
            SequentialAnimation on opacity {
                loops: Animation.Infinite
                running: lc.caret
                PropertyAction { value: 1 }
                PauseAnimation { duration: 500 }
                PropertyAction { value: 0 }
                PauseAnimation { duration: 500 }
            }
        }
        // 누른 키
        Rectangle {
            visible: lc.key !== ""
            x: lc.caretX + 16
            y: lc.caretY - 3
            width: keyText.implicitWidth + 16
            height: 24
            radius: 6
            color: Theme.surface2
            border.width: 1
            border.color: Theme.border
            Text { id: keyText; anchors.centerIn: parent; text: lc.key; color: Theme.text; font.family: Theme.font; font.pixelSize: 12; font.weight: Font.Bold }
        }
    }

    // 가사 칸과 미리보기를 함께: 줄 끝에서 Enter로 빈 줄을 넣으면 오른쪽 슬라이드가 나뉘고, 지우면 다시 합쳐진다
    property Component lyricsDemo: Component {
        Demo {
            id: d
            readonly property var l: help.sampleLines(4)
            LyricsClone { id: lc }
            DemoSlides { id: s }
            function caretAt(i, dy) { const p = lc.lineEnd(i); lc.caretX = p.x; lc.caretY = p.y + (dy || 0) }
            onReset: {
                help.place(lc, help.lyricsBox, d)
                help.place(s, help.slideList, d)
                lc.setLines([l[0], l[1], "", l[2], l[3]])
                lc.caret = false
                lc.key = ""
                s.clearMarks()
                s.setGroups([[l[0], l[1]], [l[2], l[3]]])
                d.jumpTo(lc, 0.75, 0.75)
            }
            script: [
                [600, () => { const p = lc.lineEnd(0); d.moveToXY(lc, p.x, p.y + 9) }],
                [750, () => { d.click(); d.caretAt(0); lc.caret = true }],
                [700, () => { lc.key = "Enter" }],
                [350, () => { lc.lines.insert(1, { line: "", sel: false }); lc.caret = false }],
                [250, () => { s.applyGroups([[l[0]], [l[1]], [l[2], l[3]]]); s.flash(1) }],
                [600, () => { lc.key = ""; const p = lc.lineEnd(1); lc.caretX = p.x - 2; lc.caretY = p.y + 17; lc.caret = true }],
                [1500, () => { lc.key = "⌫ 지우기" }],
                [350, () => { lc.lines.remove(1); d.caretAt(0) }],
                [250, () => { s.applyGroups([[l[0], l[1]], [l[2], l[3]]]); s.flash(0) }],
                [700, () => { lc.key = "" }]
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
    // 가사 위치 찾기: 가사를 누르면 그 단락의 슬라이드에 초록 테두리, 슬라이드를 누르면 가사에서 그 부분이 선택된다
    property Component findDemo: Component {
        Demo {
            id: d
            readonly property var l: help.sampleLines(6)
            LyricsClone { id: lc }
            DemoSlides { id: s }
            onReset: {
                help.place(lc, help.lyricsBox, d)
                help.place(s, help.slideList, d)
                lc.setLines([l[0], l[1], "", l[2], l[3], "", l[4], l[5]])
                lc.caret = false
                lc.key = ""
                s.clearMarks()
                s.setGroups([[l[0], l[1]], [l[2], l[3]], [l[4], l[5]]])
                d.jumpTo(lc, 0.8, 0.9)
            }
            script: [
                // 가사 → 슬라이드
                [600, () => d.moveTo(lc.item(3), 0.15, 0.5)],
                [750, () => {
                    d.click()
                    const it = lc.item(3)
                    const p = it.mapToItem(lc, Math.min(it.textWidth, it.width * 0.15), 0)
                    lc.caretX = p.x; lc.caretY = p.y; lc.caret = true
                }],
                [250, () => { s.active = 1; s.flash(1) }],
                // 슬라이드 → 가사
                [1700, () => d.moveTo(s.card(2), 0.5, 0.55)],
                [700, () => { s.pressedSlide = 2; d.click() }],
                [160, () => { s.pressedSlide = -1; s.active = 2; lc.caret = false; lc.selectLines(6, 7) }],
                [1700, () => {}]
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
            // 둘째 슬라이드의 첫 줄을 앞 슬라이드 끝으로 → 그 줄(이제 첫 슬라이드의 마지막 줄)을 슬라이드 사이에 놓아 새 슬라이드로
            script: help.dragScript(d, s, 1, 0, 0, [[l[0], l[1], l[2]], [l[3]], [l[4], l[5]]]).concat([
                [1300, () => d.moveTo(s.line(0, 2))],
                [700, () => { d.cursor.pressed = true }],
                [250, () => {
                    s.dragSlide = 0; s.dragLine = 2
                    d.ghostText = s.linesAt(0)[2]
                    d.moveTo(s.joinGap(1), 0.5, 0.5)
                }],
                [700, () => { s.dropGap = 1 }],
                [700, () => {
                    d.cursor.pressed = false
                    d.ghostText = ""
                    s.clearMarks()
                    s.setLines(0, [l[0], l[1]])
                }],
                // 줄을 뺀 첫 슬라이드가 줄어든 뒤에 사이에 새 슬라이드를 끼워 넣는다(뒤 슬라이드들이 밀려 내려간다).
                // 높이 변화와 동시에 넣으면 ListView가 새 슬라이드를 예전 높이 기준 자리에 둔 채 겹친다
                [300, () => s.insertAt(1, [l[2]])],
                [350, () => s.flash(1)]
            ])
        }
    }

    // 2줄 유지: 켜진 체크박스를 가리킨 뒤, 첫 슬라이드의 마지막 줄을 뒤 슬라이드 처음으로 옮기면
    // 넘친 줄이 뒤로 연쇄해서 밀려 2줄씩 다시 맞춰진다 (editor.js planDrop과 같은 결과)
    property Component keepTwoDemo: Component {
        Demo {
            id: d
            readonly property var l: help.sampleLines(6)
            DemoSlides { id: s }
            // 실제 체크박스 위에 켜진 상태를 그린다 (꺼 두었어도 예시는 켜진 상태로)
            Rectangle {
                id: mark
                width: 16; height: 16; radius: 4
                color: Theme.primary
                Icon { anchors.centerIn: parent; glyph: "check"; size: 11; color: "white" }
            }
            onReset: {
                help.place(s, help.slideList, d)
                const p = help.keepTwoBox.indicator.mapToItem(d, 0, 0)
                mark.x = p.x; mark.y = p.y
                s.clearMarks()
                s.setGroups([[l[0], l[1]], [l[2], l[3]], [l[4], l[5]]])
                d.jumpTo(s, 0.8, 0.95)
            }
            script: [
                [500, () => d.moveTo(mark)],
                [900, () => {}]
            ].concat(help.dragScript(d, s, 0, 1, 1, [[l[0]], [l[1], l[2], l[3]], [l[4], l[5]]], [
                [1, 2, 2, [[l[0]], [l[1], l[2]], [l[3], l[4], l[5]]]],
                [2, 2, 3, [[l[0]], [l[1], l[2]], [l[3], l[4]], [l[5]]]]
            ]))
        }
    }

    // '곡 추가'를 눌러 서랍(직접 입력 탭)을 실제로 열고, 제목을 입력하고 가사를 붙여 넣은 뒤 '콘티에 담기' (입력은 복제본)
    property Component manualDemo: Component {
        Demo {
            id: d
            readonly property Item form: help.editor.drawer.manual
            readonly property string title: "새 찬양"
            readonly property var lyricLines: help.sampleLines(4)
            property int typed: 0
            property bool pasted: false
            property bool added: false
            property string key: ""
            // 입력칸 모양 그대로 덮어 그린다 (실제 입력칸은 건드리지 않는다)
            Rectangle {
                id: titleCover
                visible: d.typed > 0
                radius: Theme.radiusSm
                color: Theme.surface2
                border.width: 1.5
                border.color: Theme.focusBorder
                Text {
                    x: 12
                    anchors.verticalCenter: parent.verticalCenter
                    text: d.title.slice(0, d.typed) + (d.typed < d.title.length ? "|" : "")
                    color: Theme.text
                    font.family: Theme.font
                    font.pixelSize: 14
                }
            }
            Rectangle {
                id: lyricsCover
                visible: d.pasted
                radius: Theme.radiusSm
                color: Theme.surface
                border.width: 1.5
                border.color: Theme.focusBorder
                Column {
                    x: 14
                    y: 14
                    spacing: 2
                    Repeater {
                        model: d.lyricLines
                        delegate: Text { required property string modelData; text: modelData; color: Theme.text; font.family: Theme.font; font.pixelSize: 14 }
                    }
                }
            }
            // 누른 키 (붙여 넣기)
            Rectangle {
                id: keyBadge
                visible: d.key !== ""
                width: keyLabel.implicitWidth + 16
                height: 24
                radius: 6
                color: Theme.surface2
                border.width: 1
                border.color: Theme.border
                Text { id: keyLabel; anchors.centerIn: parent; text: d.key; color: Theme.text; font.family: Theme.font; font.pixelSize: 12; font.weight: Font.Bold }
            }
            // 담았다는 알림 (실제 알림과 같은 모양)
            Rectangle {
                visible: d.added
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 16
                width: addedRow.implicitWidth + 32
                height: 44
                radius: 12
                color: Theme.toastBg
                Row {
                    id: addedRow
                    anchors.centerIn: parent
                    spacing: 8
                    Icon { glyph: "check"; size: 16; color: Theme.primary; anchors.verticalCenter: parent.verticalCenter }
                    Text { text: "'" + d.title + "' 곡을 콘티에 담았어요"; color: "white"; font.family: Theme.font; font.pixelSize: 13; font.weight: Font.DemiBold; anchors.verticalCenter: parent.verticalCenter }
                }
            }
            // 담은 뒤 왼쪽 찬양 목록: 마지막 곡 아래(지금 '곡 추가' 자리)에 새 곡이 붙고 '곡 추가'는 한 줄 아래로 (실제 목록과 같은 모양)
            Item {
                id: listAdd
                visible: d.added
                // 찬양 칸이 한 줄만큼 길어진 모습
                Rectangle {
                    id: cardGrow
                    radius: 12
                    color: Theme.surface2
                }
                // 아래의 실제 '곡 추가' 칸을 바로 가리고, 새 곡 줄은 그 위에서 나타난다
                Rectangle {
                    id: rowCover
                    color: Theme.surface2
                }
                Rectangle {
                    id: newRow
                    radius: Theme.radiusSm
                    color: "transparent"
                    opacity: d.added ? 1 : 0
                    scale: d.added ? 1 : 0.92
                    Behavior on opacity { NumberAnimation { duration: 300 } }
                    Behavior on scale { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
                    Text {
                        x: 10
                        anchors.verticalCenter: parent.verticalCenter
                        text: help.setlistPanel.entries.length + 1
                        color: Theme.text3
                        font.family: Theme.font
                        font.pixelSize: 12
                        font.weight: Font.Bold
                    }
                    Text {
                        x: 30
                        anchors.verticalCenter: parent.verticalCenter
                        text: d.title
                        color: Theme.text
                        font.family: Theme.font
                        font.pixelSize: 13
                        font.weight: Font.DemiBold
                    }
                }
                Rectangle {
                    id: addClone
                    radius: Theme.radiusSm
                    color: "transparent"
                    border.width: 1.5
                    border.color: Qt.rgba(Theme.text3.r, Theme.text3.g, Theme.text3.b, 0.4)
                    Row {
                        anchors.centerIn: parent
                        spacing: 5
                        Icon { glyph: "plus"; size: 13; color: Theme.text2; anchors.verticalCenter: parent.verticalCenter }
                        Text { text: "곡 추가"; color: Theme.text2; font.family: Theme.font; font.pixelSize: 13; font.weight: Font.DemiBold; anchors.verticalCenter: parent.verticalCenter }
                    }
                }
            }
            // 서랍이 열리는 중일 수 있어 위치는 움직이기 직전에 잡는다
            function sync() {
                help.place(titleCover, form.titleItem, d)
                help.place(lyricsCover, form.lyricsItem, d)
                const panel = help.setlistPanel
                const step = panel.step
                help.place(newRow, addButton, d)
                help.place(rowCover, addButton, d)
                help.place(addClone, addButton, d)
                addClone.y += step
                const c = panel.songCard.mapToItem(d, 0, 0)
                cardGrow.x = c.x
                cardGrow.y = c.y + panel.songCard.height - 16
                cardGrow.width = panel.songCard.width
                cardGrow.height = step + 16
            }
            readonly property Item addButton: help.setlistPanel.addButton
            onReset: {
                typed = 0; pasted = false; added = false; key = ""
                help.editor.closeDrawer(false)
                d.jumpTo(addButton, 1.6, 2.2)
            }
            script: {
                const steps = [
                    [500, () => d.moveTo(d.addButton, 0.5, 0.5)],
                    [750, () => { d.click(); help.editor.openDrawer("manual") }],
                    // 서랍이 다 열린 뒤에 자리를 잡는다
                    [Theme.normal + 450, () => { d.sync(); d.moveTo(d.form.titleItem, 0.3, 0.5) }],
                    [700, () => d.click()]]
                for (let i = 1; i <= title.length; i++) steps.push([i === 1 ? 300 : 160, () => d.typed++])
                steps.push(
                    [600, () => d.moveTo(d.form.lyricsItem, 0.3, 0.15)],
                    [700, () => {
                        d.click()
                        const p = d.form.lyricsItem.mapToItem(d, 16, 14)
                        keyBadge.x = p.x; keyBadge.y = p.y
                        d.key = Theme.mod + "V 붙여 넣기"
                    }],
                    [600, () => { d.key = ""; d.pasted = true }],
                    [900, () => d.moveTo(d.form.submitItem, 0.5, 0.5)],
                    // 담으면 입력칸은 비워지고, 왼쪽 찬양 목록 끝에 그 제목으로 곡이 붙는다
                    [750, () => { d.click(); d.typed = 0; d.pasted = false; d.added = true }],
                    [700, () => d.moveTo(newRow, 0.5, 0.5)],
                    [1800, () => {}])
                return steps
            }
        }
    }

    // 줄바꿈 경고: '줄바꿈 있음' 표시와 주황색 줄, 줄에 마우스를 올리면 툴팁, 표시를 누르면 그 슬라이드
    property Component wrapDemo: Component {
        Demo {
            id: d
            readonly property var l: help.sampleLines(6)
            DemoSlides { id: s }
            Rectangle {
                id: badge
                opacity: 0
                width: badgeRow.implicitWidth + 16
                height: 20
                radius: 10
                color: Theme.warningSoft
                Behavior on opacity { NumberAnimation { duration: Theme.normal } }
                Row {
                    id: badgeRow
                    anchors.centerIn: parent
                    spacing: 4
                    Icon { glyph: "alert"; size: 12; color: Theme.warning; anchors.verticalCenter: parent.verticalCenter }
                    Text { text: "줄바꿈 있음"; color: Theme.warning; font.family: Theme.font; font.pixelSize: 12; font.weight: Font.DemiBold }
                }
            }
            // 줄에 마우스를 올렸을 때 (실제 툴팁과 같은 모양)
            Rectangle {
                id: tip
                visible: false
                width: tipText.implicitWidth + 16
                height: tipText.implicitHeight + 16
                radius: 8
                color: Theme.tooltipBg
                border.width: 1
                border.color: Theme.border
                Text { id: tipText; anchors.centerIn: parent; text: "PPT에서 두 줄로 나뉘어요 · 글상자 폭의 112%"; color: Theme.tooltipText; font.family: Theme.font; font.pixelSize: 12 }
            }
            onReset: {
                help.place(s, help.slideList, d)
                const t = help.slidesTitle.mapToItem(d, help.slidesTitle.width + 6, help.slidesTitle.height / 2)
                badge.x = t.x
                badge.y = t.y - badge.height / 2
                badge.opacity = 0
                tip.visible = false
                s.clearMarks()
                s.setGroups([[l[0], l[1]], [l[2] + " " + l[3], l[4]], [l[5]]])
                d.jumpTo(s, 0.85, 0.95)
            }
            script: [
                [500, () => { badge.opacity = 1; s.warnLines = ["1:0"] }],
                [1000, () => d.moveTo(s.line(1, 0), 0.5, 0.5)],
                [700, () => {
                    const it = s.line(1, 0)
                    const p = it.mapToItem(d, it.width / 2, 0)
                    tip.x = Math.max(4, Math.min(d.width - tip.width - 4, p.x - tip.width / 2))
                    tip.y = p.y - tip.height - 8
                    tip.visible = true
                }],
                [1900, () => { tip.visible = false; d.moveTo(badge, 0.5, 0.5) }],
                [700, () => { d.click(); s.active = 1; s.flash(1) }],
                [1500, () => {}]
            ]
        }
    }

    // 콘티 비우기: ⋯ 메뉴 → '콘티 비우기' → 목록이 비고 '되돌리기' 알림 → 되돌리기
    property Component clearDemo: Component {
        Demo {
            id: d
            readonly property Item panel: help.setlistPanel
            property bool menuOpen: false
            property bool itemHot: false
            property bool cleared: false
            // 실제 ⋯ 메뉴와 같은 모양
            Rectangle {
                id: menu
                visible: d.menuOpen
                width: 180
                height: menuCol.implicitHeight + 12
                radius: 10
                color: Theme.surface
                border.width: 1
                border.color: Theme.border
                Column {
                    id: menuCol
                    x: 6
                    y: 6
                    width: parent.width - 12
                    Rectangle {
                        width: parent.width
                        height: 34
                        radius: 6
                        color: "transparent"
                        Text { x: 12; anchors.verticalCenter: parent.verticalCenter; text: "곡 추가"; color: Theme.text; font.family: Theme.font; font.pixelSize: 13 }
                        Text { anchors.right: parent.right; anchors.rightMargin: 12; anchors.verticalCenter: parent.verticalCenter; text: Theme.mod + "K"; color: Theme.text3; font.family: Theme.font; font.pixelSize: 12 }
                    }
                    Rectangle {
                        id: clearItem
                        width: parent.width
                        height: 34
                        radius: 6
                        color: d.itemHot ? Theme.surface2 : "transparent"
                        Text { x: 12; anchors.verticalCenter: parent.verticalCenter; text: "콘티 비우기"; color: Theme.text; font.family: Theme.font; font.pixelSize: 13 }
                    }
                }
            }
            // 비운 뒤의 찬양 칸 (실제 빈 칸과 같은 모양)
            Rectangle {
                id: emptyCard
                visible: d.cleared
                radius: 12
                color: Theme.surface2
                Column {
                    anchors.centerIn: parent
                    spacing: 10
                    Icon { anchors.horizontalCenter: parent.horizontalCenter; glyph: "music"; size: 26; color: Theme.text3 }
                    Text { anchors.horizontalCenter: parent.horizontalCenter; horizontalAlignment: Text.AlignHCenter; text: "담은 곡이 여기에\n순서대로 쌓여요"; color: Theme.text3; font.family: Theme.font; font.pixelSize: 13; lineHeight: 1.3 }
                }
            }
            // 되돌리기 알림
            Rectangle {
                id: toastClone
                visible: d.cleared
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 20
                width: toastRow.implicitWidth + 28
                height: 44
                radius: 12
                color: Theme.toastBg
                Row {
                    id: toastRow
                    anchors.centerIn: parent
                    spacing: 12
                    Text { text: "콘티를 비웠어요"; color: "white"; font.family: Theme.font; font.pixelSize: 13; font.weight: Font.DemiBold; anchors.verticalCenter: parent.verticalCenter }
                    Text { id: undoText; text: "되돌리기"; color: Theme.primary; font.family: Theme.font; font.pixelSize: 13; font.weight: Font.Bold; anchors.verticalCenter: parent.verticalCenter }
                }
            }
            onReset: {
                const b = panel.menuButton.mapToItem(d, 0, 0)
                menu.x = b.x + panel.menuButton.width - menu.width
                menu.y = b.y + panel.menuButton.height + 4
                const c = panel.songCard.mapToItem(d, 0, 0)
                emptyCard.x = c.x
                emptyCard.y = c.y
                emptyCard.width = panel.songCard.width
                emptyCard.height = Math.max(panel.songCard.height, d.height - c.y - 8)
                menuOpen = false; itemHot = false; cleared = false
                d.jumpTo(panel.menuButton, -1.5, 2.5)
            }
            script: [
                [500, () => d.moveTo(panel.menuButton, 0.5, 0.5)],
                [700, () => { d.click(); d.menuOpen = true }],
                [700, () => d.moveTo(clearItem, 0.35, 0.5)],
                [450, () => { d.itemHot = true }],
                [450, () => d.click()],
                [150, () => { d.menuOpen = false; d.itemHot = false; d.cleared = true }],
                [1300, () => d.moveTo(undoText, 0.5, 0.5)],
                [700, () => { d.click(); d.cleared = false }],
                [1300, () => {}]
            ]
        }
    }

    // 양식 ⚠: 찬양 전 칸에 지난 파일이 들어 있는 모습 → 마우스를 올리면 고친 날 → 보관함 아이콘을 눌러 보관하면 ⚠가 사라진다
    property Component staleDemo: Component {
        Demo {
            id: d
            readonly property Item before: help.setlistPanel.attachBefore
            property bool hot: false
            property bool kept: false
            property bool tipOn: false
            // 찬양 전 칸 (실제 칸과 같은 모양, 파일 줄 하나)
            Rectangle {
                id: box
                radius: 12
                color: Theme.surface2
                Text { x: 10; y: 8; text: "찬양 전"; color: Theme.text2; font.family: Theme.font; font.pixelSize: 12; font.weight: Font.Bold }
                Rectangle {
                    id: fileRow
                    x: 8
                    y: 28
                    width: box.width - 16
                    height: 30
                    radius: 8
                    color: d.hot ? Theme.border : Theme.surface
                    Behavior on color { ColorAnimation { duration: Theme.fast } }
                    Text {
                        x: 8
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - 60
                        text: "설교.pptx"
                        elide: Text.ElideRight
                        color: Theme.text
                        font.family: Theme.font
                        font.pixelSize: 12
                        font.weight: Font.DemiBold
                    }
                    Icon {
                        visible: !d.kept && !d.hot
                        anchors.right: parent.right
                        anchors.rightMargin: 8
                        anchors.verticalCenter: parent.verticalCenter
                        glyph: "alert"; size: 12; color: Theme.warning
                    }
                    Icon {
                        id: keepIcon
                        visible: d.hot
                        anchors.right: parent.right
                        anchors.rightMargin: 30
                        anchors.verticalCenter: parent.verticalCenter
                        glyph: "library"; size: 14
                        color: d.kept ? Theme.primaryText : Theme.text2
                    }
                    Icon {
                        visible: d.hot
                        anchors.right: parent.right
                        anchors.rightMargin: 8
                        anchors.verticalCenter: parent.verticalCenter
                        glyph: "x"; size: 14; color: Theme.text2
                    }
                }
            }
            // 줄에 마우스를 올렸을 때 (실제 툴팁과 같은 모양)
            Rectangle {
                visible: d.tipOn
                x: box.x
                y: box.y + box.height + 6
                // 강조 영역(찬양 전·후 두 칸) 안에서 줄을 바꾼다 (넘치면 설명 카드에 가린다)
                width: Math.min(tipText.implicitWidth, d.width - box.x - 24) + 16
                height: tipText.height + 16
                radius: 8
                color: Theme.tooltipBg
                border.width: 1
                border.color: Theme.border
                Text {
                    id: tipText
                    anchors.centerIn: parent
                    width: Math.min(implicitWidth, d.width - box.x - 24)
                    wrapMode: Text.Wrap
                    text: "10월 9일에 고친 파일이에요. 이번 주 PPT가 맞는지 확인해 주세요."
                    color: Theme.tooltipText
                    font.family: Theme.font
                    font.pixelSize: 12
                }
            }
            onReset: {
                const p = before.mapToItem(d, 0, 0)
                box.x = p.x
                box.y = p.y
                box.width = before.width
                box.height = Math.max(before.height, 66)
                hot = false; kept = false; tipOn = false
                d.jumpTo(box, 0.9, 1.6)
            }
            script: [
                [600, () => d.moveTo(fileRow, 0.35, 0.5)],
                [450, () => { d.hot = true }],
                [500, () => { d.tipOn = true }],
                [2200, () => { d.tipOn = false; d.moveTo(keepIcon, 0.5, 0.5) }],
                [700, () => { d.click(); d.kept = true }],
                [700, () => { d.moveTo(box, 0.9, 1.6) }],
                [500, () => { d.hot = false }],
                [1500, () => {}]
            ]
        }
    }
}
