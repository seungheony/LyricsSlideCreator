import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import QtQuick.Dialogs
import QtQuick.Effects
import QtCore
import "."
import "editor.js" as E

Item {
    id: page

    property var toastHost: null
    property var dialog: null
    property var confirmDialog: null
    property var tour: null
    // 내 템플릿(변경 버튼)은 아직 지원하지 않는다. 다시 쓸 때 true로 바꾸면 기존 기능이 그대로 살아난다
    readonly property bool customTemplate: false

    property var song: null
    property var blocks: []          // 가사 텍스트에서 파생된 슬라이드 목록 (입력 중에는 잠깐 늦게 따라온다, sync)
    property var spans: []           // 지금 가사 텍스트의 슬라이드 위치(start/end). 커서 → 슬라이드 계산용으로 늘 최신
    property int active: -1          // 가사 커서가 위치한 슬라이드
    property bool applying: false    // 코드에서 텍스트를 바꾸는 중 (입력 이벤트 무시)
    property bool generating: false
    property url savedUrl: ""         // 마지막으로 저장한 PPT (완료 토스트의 [열기])
    // 세션 동안 마지막으로 PPT를 저장한 폴더(메모리에만 둠). 비어 있으면 문서 폴더
    property url lastSaveFolder: ""
    // 곡을 연 때나 마지막으로 PPT를 만든 때의 슬라이드 내용. 지금과 다르면 PPT로 만들지 않은 편집이 있다
    property string savedKey: ""
    property string generatingKey: ""
    readonly property bool dirty: song !== null && contentKey(blocks) !== savedKey

    signal backRequested()

    readonly property bool lyricsFocused: lyrics.activeFocus
    readonly property bool dragging: slideList.dragging

    function contentKey(bs) { return E.serialize(E.linesOf(bs)) }

    // ── 곡 불러오기 / 편집 상태 ──
    // 편집 상태는 Main이 곡별로 세션 메모리에 보관해, 같은 곡을 다시 열면 이어서 편집한다 (파일로 남기지 않음)
    function load(newSong, lyricsText) {
        // 멜론 가사는 절 사이에 빈 줄이 섞여 있으므로 처음에는 2줄씩 자동으로 나눈다
        const text = E.serialize(E.regroup(E.allLines(E.parseBlocks(lyricsText)), 2))
        resume(newSong, { text: text, hist: [text], histIdx: 0, cursor: 0, contentY: 0, slideY: 0,
                          kept: {}, savedKey: text })
    }

    function saveState() {
        prepareEdit()
        flushTyping()
        return { text: lyrics.text, hist: hist, histIdx: histIdx, cursor: lyrics.cursorPosition,
                 contentY: lyricsScroll.contentItem.contentY, slideY: slideList.scrollY(),
                 kept: keptLongSlides, savedKey: savedKey, dirty: dirty }
    }

    function resume(newSong, st) {
        song = newSong
        art.source = "image://art/" + newSong.song_id
        backdrop.source = "image://art/" + newSong.song_id
        longCheckTimer.stop()
        typingTimer.stop()
        dismissUndoToast()
        active = -1
        wrapCursor = -1
        keptLongSlides = st.kept
        savedKey = st.savedKey
        applying = true
        lyrics.text = st.text          // 다른 곡이라 통째로 바꾼다
        applying = false
        sync()
        hist = st.hist
        histIdx = st.histIdx
        lyrics.cursorPosition = Math.min(st.cursor, lyrics.length)
        syncActiveFromCaret()
        // 레이아웃이 끝난 뒤 스크롤 위치를 되살린다
        Qt.callLater(() => {
            setLyricsY(st.contentY)
            slideList.setScrollY(st.slideY)
        })
    }

    // ── 텍스트 반영 ──
    // 바뀐 구간만 지우고 넣는다. 통째로 바꾸면 커서가 맨 앞으로 가고 선택·스크롤도 풀린다.
    // 반환: 새 텍스트에서 바뀐 구간 { start, end } (바뀐 게 없으면 null)
    function setText(text) {
        const d = E.textDiff(lyrics.text, text)
        if (!d) return null
        const y = lyricsScroll.contentItem.contentY
        applying = true
        if (d.end > d.start) lyrics.remove(d.start, d.end)
        if (d.insert) lyrics.insert(d.start, d.insert)
        if (lyrics.text !== text) lyrics.text = text    // 만일 어긋나면 통째로
        applying = false
        setLyricsY(y)
        sync()
        return { start: d.start, end: d.start + d.insert.length }
    }

    // 가사 칸 스크롤 (내용이 짧아졌으면 끝에 맞춘다)
    function setLyricsY(y) {
        const flick = lyricsScroll.contentItem
        flick.contentY = Math.max(0, Math.min(y, Math.max(0, flick.contentHeight - flick.height)))
    }

    // 커서가 화면 밖이면 위에서 1/3 지점에 오도록
    function revealCaret() {
        const flick = lyricsScroll.contentItem
        const rect = lyrics.positionToRectangle(lyrics.cursorPosition)
        if (rect.y < flick.contentY || rect.y + rect.height > flick.contentY + flick.height)
            setLyricsY(rect.y - flick.height / 3)
    }

    // 슬라이드 목록 갱신. 줄 배열이 바뀌었을 때만 blocks를 바꾼다 (SlideList는 바뀐 카드만 고침)
    function sync() {
        syncTimer.stop()
        spans = E.parseBlocks(lyrics.text)
        if (!E.sameLines(spans, blocks)) {
            measureLines(spans)
            blocks = spans
        }
        if (active >= blocks.length) active = blocks.length - 1
    }

    // 입력 중에는 슬라이드 목록을 잠깐 모아서 갱신한다. 그 전에 목록을 쓰는 곳은 먼저 부른다
    function flushSync() { if (syncTimer.running) sync() }
    Timer { id: syncTimer; interval: 80; onTriggered: page.sync() }

    // 미리보기·단축키로 편집하기 전에: 조합 중인 한글을 확정하고, 미뤄 둔 목록 갱신을 반영한다
    function prepareEdit() {
        if (lyrics.preeditText !== "") Qt.inputMethod.commit()
        flushSync()
    }

    // ── PPT 줄바꿈 미리 계산 ── 템플릿의 가사 글상자(글꼴·크기·폭) 기준 (src/utils/line_fit.py)
    property var lineRatios: []      // 슬라이드별·줄별 글상자 폭 대비 글자 폭 비율 (1을 넘으면 줄바꿈)
    property var wrapSlides: []      // 줄바꿈되는 줄이 있는 슬라이드 번호
    property int wrapCursor: -1      // 줄바꿈 표시를 누를 때마다 다음 슬라이드로
    property string fitBasis: ""     // 계산 기준 (안내 문구)
    property var ratioCache: new Map()   // 줄 → 비율. 입력할 때는 바뀐 줄만 계산한다

    function measureLines(bs) {
        if (ratioCache.size > 5000) ratioCache = new Map()
        const missing = []
        const seen = new Set()
        bs.forEach(b => b.lines.forEach(l => {
            if (!ratioCache.has(l) && !seen.has(l)) { seen.add(l); missing.push(l) }
        }))
        if (missing.length) {
            const ratios = JSON.parse(backend.lineWidthRatios(JSON.stringify(missing)))
            missing.forEach((l, i) => ratioCache.set(l, ratios[i]))
        }
        lineRatios = bs.map(b => b.lines.map(l => ratioCache.get(l)))
        wrapSlides = lineRatios.reduce((acc, r, i) => r.some(x => x > 1) ? acc.concat(i) : acc, [])
    }

    function updateFitBasis() {
        const info = JSON.parse(backend.lineFitInfo())
        fitBasis = info.font ? info.font + (info.bold ? " 굵게 " : " ") + info.sizePt + "pt · 글상자 폭 " + info.availablePt + "pt"
                               + (info.exact ? "" : " (글꼴이 없어 비슷한 글꼴로 계산한 어림값)")
                             : ""
    }

    function showNextWrap() {
        prepareEdit()
        if (!wrapSlides.length) return
        const next = wrapSlides.find(i => i > wrapCursor)
        wrapCursor = next !== undefined ? next : wrapSlides[0]
        // 그 슬라이드에서 처음으로 넘치는 줄 끝에 커서를 둔다
        revealInText(wrapCursor, (lineRatios[wrapCursor] || []).findIndex(r => r > 1))
        slideList.flash(wrapCursor)
    }

    Component.onCompleted: updateFitBasis()

    // 구조 편집: 텍스트를 새로 쓰고 히스토리에 남긴 뒤 바뀐 슬라이드를 강조한다
    // (호출하는 쪽은 blocks로 groups를 만들기 전에 prepareEdit()을 부른다)
    function commit(groups, opts) {
        opts = opts || {}
        flushTyping()
        setText(E.serialize(groups))
        record(lyrics.text)
        if (opts.focus !== undefined && opts.focus >= 0) {
            active = opts.focus
            Qt.callLater(slideList.flash, opts.focus)
        }
        if (opts.message && toastHost) {
            // 이 토스트가 알린 편집이 마지막일 때만 되돌린다 (다른 편집이 이어지면 record()에서 토스트를 숨김)
            const mine = histIdx
            toastHist = mine
            toastHost.show(opts.message, { actionLabel: "되돌리기", duration: 5000,
                                          onAction: () => { if (page.histIdx === mine) page.undo() } })
        }
    }

    // 되돌리기 토스트가 알린 편집의 히스토리 위치. 히스토리가 그 위치를 벗어나면 토스트를 숨긴다
    property int toastHist: -1
    function dismissUndoToast() {
        if (toastHist < 0) return
        toastHist = -1
        if (toastHost) toastHost.hide()
    }

    function cutSlide(idx, at) {
        prepareEdit()
        const groups = E.linesOf(blocks)
        const lines = groups[idx]
        if (!lines || at <= 0 || at >= lines.length) return
        groups.splice(idx, 1, lines.slice(0, at), lines.slice(at))
        commit(groups, { focus: idx + 1 })
    }

    function joinSlides(idx) {
        prepareEdit()
        const groups = E.linesOf(blocks)
        if (idx < 0 || idx + 1 >= groups.length) return
        const joined = groups[idx].concat(groups[idx + 1])
        const apply = (asked) => {
            groups.splice(idx, 2, joined)
            // 확인하고 합친 슬라이드는 입력칸에서 벗어날 때·PPT를 만들 때 다시 묻지 않는다
            if (asked) keepLong([joined.join("\n")])
            commit(groups, { focus: idx })
        }
        // 2줄 유지 중에 3줄 이상 슬라이드가 생기면 한 번 확인한다
        if (keepTwo && joined.length > 2 && confirmDialog) {
            confirmDialog.ask({
                title: "3줄 이상 슬라이드가 돼요",
                message: (idx + 1) + "번과 " + (idx + 2) + "번 슬라이드를 합치면 " + joined.length
                         + "줄이 돼요. '2줄 유지' 중인데 합칠까요?",
                confirmText: "합치기",
                onConfirm: () => apply(true)
            })
        } else {
            apply(false)
        }
    }

    // ── 2줄 유지 중 3줄 이상 슬라이드 확인 ──
    // 타이핑 중에는 방해하지 않고, 입력칸에서 벗어날 때와 PPT를 만들기 전에 한 번 묻는다.
    // 창 전환·페이지 전환으로 포커스가 빠질 때는 묻지 않는다.
    // '그대로 두기'를 고르거나 확인하고 합친 슬라이드는 내용이 바뀌기 전까지 다시 묻지 않는다.
    property var keptLongSlides: ({})

    function keepLong(keys) {
        const kept = Object.assign({}, keptLongSlides)
        keys.forEach(k => { kept[k] = true })
        keptLongSlides = kept
    }

    // 아직 묻지 않은 3줄 이상 슬라이드 번호
    function freshLongSlides() {
        const out = []
        blocks.forEach((b, i) => { if (b.lines.length > 2 && keptLongSlides[b.lines.join("\n")] !== true) out.push(i) })
        return out
    }

    // 입력칸에서 벗어났을 때: 나눌지, 그대로 둘지
    function askLongSlides(fresh) {
        const keys = fresh.map(i => blocks[i].lines.join("\n"))
        confirmDialog.ask({
            title: "3줄 이상인 슬라이드가 있어요",
            message: longNames(fresh) + " 슬라이드가 3줄 이상이에요. '2줄 유지' 중인데 2줄씩 나눌까요?",
            confirmText: "2줄씩 나누기",
            cancelText: "그대로 두기",
            onConfirm: () => splitLongSlides(keys),
            onCancel: () => keepLong(keys)
        })
        slideList.flash(fresh[0])
    }

    // PPT 생성 전: 그대로 만들지(주 버튼), 편집 화면으로 돌아가 2줄씩 나눌지. Esc·바깥 클릭은 아무것도 하지 않음
    function askLongBeforeGenerate(fresh) {
        const keys = fresh.map(i => blocks[i].lines.join("\n"))
        confirmDialog.ask({
            title: "3줄 이상인 슬라이드가 있어요",
            message: longNames(fresh) + " 슬라이드가 3줄 이상이에요. 그대로 PPT를 만들까요, 2줄씩 나눌까요?",
            confirmText: "그대로 PPT 생성",
            cancelText: "2줄씩 나누기",
            onConfirm: () => { keepLong(keys); openSaveDialog() },
            onCancel: () => splitLongSlides(keys),
            onDismiss: null
        })
        slideList.flash(fresh[0])
    }

    function longNames(fresh) {
        return fresh.slice(0, 5).map(i => (i + 1) + "번").join(", ") + (fresh.length > 5 ? " 등" : "")
    }

    // 입력칸에서 벗어난 뒤 잠깐 기다렸다가 묻는다. 그 사이 PPT 생성·뒤로·창 전환이 있었으면 묻지 않는다
    Timer { id: longCheckTimer; interval: 250; onTriggered: page.checkLongSlides() }

    function checkLongSlides() {
        if (!keepTwo || !confirmDialog || !page.enabled || lyrics.activeFocus) return
        if (Qt.application.state !== Qt.ApplicationActive || !page.Window.active) return   // 다른 앱·창으로 전환
        // 다른 창이 떠 있거나(튜토리얼은 닫힌 뒤에 묻는다, 아래 Connections), PPT 생성·뒤로를 누르는 중이면 묻지 않는다
        if (confirmDialog.visible || (tour && tour.visible) || (dialog && dialog.visible) || saveDialog.visible) return
        if (generating || generateButton.pressed || backButton.pressed) return
        prepareEdit()
        const fresh = freshLongSlides()
        if (fresh.length) askLongSlides(fresh)
    }

    Connections {
        target: page.tour
        function onClosed() { if (page.enabled && !page.lyricsFocused) longCheckTimer.restart() }
    }

    // 물어본 슬라이드(keys)만 2줄씩 나눈다 (나머지는 그대로)
    function splitLongSlides(keys) {
        prepareEdit()
        const asked = {}
        keys.forEach(k => { asked[k] = true })
        let count = 0
        const groups = []
        E.linesOf(blocks).forEach(lines => {
            if (lines.length > 2 && asked[lines.join("\n")] === true) { count++; groups.push(...E.regroup(lines, 2)) }
            else groups.push(lines)
        })
        if (count) commit(groups, { message: count + "장을 2줄씩 나눴어요" })
    }

    function removeSlide(idx) {
        prepareEdit()
        const groups = E.linesOf(blocks)
        if (idx < 0 || idx >= groups.length) return
        groups.splice(idx, 1)
        active = -1
        commit(groups, { message: (idx + 1) + "번 슬라이드를 삭제했어요" })
    }

    function autoSplit(n) {
        prepareEdit()
        const groups = E.regroup(E.allLines(blocks), n)
        if (E.serialize(groups) === lyrics.text) return    // 나눠도 달라지지 않으면 알리지 않는다
        active = -1
        commit(groups, { message: n + "줄씩 다시 나눴어요" })
        slideList.scrollToTop()
    }

    // 줄 드래그: 옆 슬라이드로만 옮긴다. 2줄 유지를 켜면 넘친 줄은 연쇄로 밀고 빈자리는 연쇄로 당겨 채운다
    property bool keepTwo: true     // 기본으로 켜 둔다

    // 놓으려는 위치를 허용된 동작으로 바꾼다. 허용되지 않거나 바뀌는 게 없으면 null
    function resolveDrop(src, raw) {
        const target = E.resolveDrop(blocks, src, raw)
        return target && E.planDrop(blocks, src, target, keepTwo) ? target : null
    }

    function moveLine(src, target) {
        prepareEdit()
        if (!E.resolveDrop(blocks, src, target)) return    // 끄는 사이 목록이 바뀌었으면 하지 않는다
        const plan = E.planDrop(blocks, src, target, keepTwo)
        if (plan) commit(plan.groups, { focus: plan.focus })
    }

    // ── 히스토리 (⌘Z) ──
    // 타이핑과 구조 편집을 하나의 스냅샷 스택으로 관리한다.
    // 타이핑은 0.6초 쉼, 줄바꿈(Enter), 붙여넣기에서 한 단계로 끊는다.
    property var hist: []
    property int histIdx: -1
    property bool recordNextInput: false   // 붙여넣기: 들어온 내용을 바로 한 단계로 남긴다

    function record(text) {
        typingTimer.stop()
        if (hist[histIdx] === text) return
        const next = hist.slice(0, histIdx + 1)
        next.push(text)
        if (next.length > 200) next.shift()
        hist = next
        histIdx = next.length - 1
        dismissUndoToast()
    }

    function flushTyping() {
        if (typingTimer.running) record(lyrics.text)
    }

    function undo() {
        prepareEdit()
        flushTyping()
        if (histIdx <= 0) return
        histIdx--
        dismissUndoToast()
        showHistory()
    }

    function redo() {
        prepareEdit()
        flushTyping()
        if (histIdx >= hist.length - 1) return
        histIdx++
        dismissUndoToast()
        showHistory()
    }

    // 되돌린 곳으로 커서를 옮기고, 화면 밖이면 보이게 한다 (커서 → 활성 슬라이드도 따라감)
    function showHistory() {
        const changed = setText(hist[histIdx])
        if (!changed) return
        lyrics.cursorPosition = changed.end
        revealCaret()
    }

    Timer { id: typingTimer; interval: 600; onTriggered: page.record(lyrics.text) }

    // ── 가사 ↔ 슬라이드 연결 ──
    function syncActiveFromCaret() {
        const idx = E.blockIndexAt(spans, lyrics.cursorPosition)
        if (idx !== active) {
            active = idx
            slideList.ensureVisible(idx)
        }
    }

    // 슬라이드(line을 주면 그 줄 끝)로 가사 커서를 옮긴다.
    // 선택하지 않아서, 위치만 보려다 바로 입력해도 가사가 지워지지 않는다. 위치는 잠깐 강조해 보여 준다
    function revealInText(idx, line) {
        prepareEdit()
        const block = spans[idx]
        if (!block) return
        lyrics.forceActiveFocus()
        lyrics.cursorPosition = line >= 0 ? E.lineEnd(lyrics.text, block, line) : block.start
        // 슬라이드가 위에서 1/3 지점에 오도록 스크롤
        const flick = lyricsScroll.contentItem
        const top = lyrics.positionToRectangle(block.start)
        const bottom = lyrics.positionToRectangle(block.end)
        setLyricsY(top.y - flick.height / 3)
        active = idx
        revealMark.y = top.y - 3
        revealMark.height = bottom.y + bottom.height - top.y + 6
        revealAnim.restart()
    }

    function blurLyrics() { page.forceActiveFocus() }
    function cancelDrag() { slideList.cancelDrag() }

    // ── 도움말 (? 버튼) ──
    // 처음 편집 화면에 들어왔을 때: 모든 튜토리얼을 이어서 끝까지 보여준다
    function showFirstRunTour(onFinished, onSkipped) {
        help.firstRun(onFinished, onSkipped)
    }

    EditorHelp {
        id: help
        tour: page.tour
        blocks: page.blocks
        keepTwo: page.keepTwo
        lyricsBox: lyricsBox
        autoSplitRow: autoSplitRow
        slideList: slideList
        keepTwoRow: keepTwoRow
        keepTwoBox: keepTwoBox
        historyRow: historyRow
        templateRow: templateRow
        templateButton: templateButton
        customTemplate: page.customTemplate
        generateButton: generateButton
    }

    // ── 템플릿 / 생성 ──
    // 2줄 유지 중 3줄 이상 슬라이드가 있으면 먼저 묻고, 답에 맞춰 고친 뒤 저장 대화상자를 연다
    function generate() {
        if (generating || saveDialog.visible) return
        prepareEdit()
        if (!blocks.length) return    // 버튼과 단축키는 가사가 있을 때만 켜지지만 한 번 더 막는다
        longCheckTimer.stop()
        const fresh = keepTwo && confirmDialog ? freshLongSlides() : []
        if (fresh.length) askLongBeforeGenerate(fresh)
        else openSaveDialog()
    }

    function openSaveDialog() {
        const name = (song ? song.title + " — " + song.artist : "lyrics").replace(/[\/\\:*?"<>|]/g, "_")
        // FileDialog 기본 폴더는 프로세스 작업 폴더(설치 폴더일 수 있음)라 쓰지 않는다
        let folder = page.lastSaveFolder
        if (folder.toString() === "") {
            const docs = StandardPaths.writableLocation(StandardPaths.DocumentsLocation)
            folder = docs.toString() !== "" ? docs : StandardPaths.writableLocation(StandardPaths.DesktopLocation)
        }
        saveDialog.currentFolder = folder
        saveDialog.selectedFile = folder.toString().replace(/\/+$/, "") + "/" + encodeURIComponent(name) + ".pptx"
        saveDialog.open()
    }

    Connections {
        target: backend
        function onGenerateFinished(json) {
            page.generating = false
            const res = JSON.parse(json)
            if (res.error) {
                page.dialog.showError(res.error, res.detail)
            } else {
                page.savedKey = page.generatingKey    // 이 내용까지는 PPT로 만들었다
                const name = res.path.split(/[\\/]/).pop()
                const saved = page.savedUrl
                page.toastHost.show("PPT를 만들었어요 · " + name, {
                    duration: 8000,
                    actions: [
                        { label: "열기", handler: () => Qt.openUrlExternally(saved) },
                        { label: "폴더에서 보기", handler: () => backend.revealInFolder(res.path) }
                    ]
                })
            }
        }
        function onTemplateChanged() {
            page.updateFitBasis()
            page.ratioCache = new Map()
            page.measureLines(page.blocks)
        }
        function onArtReady(id) {
            if (page.song && id === page.song.song_id) {
                art.source = "image://art/" + id
                backdrop.source = "image://art/" + id
            }
        }
    }

    FileDialog {
        id: saveDialog
        title: "PPT 저장"
        fileMode: FileDialog.SaveFile
        defaultSuffix: "pptx"
        nameFilters: ["PowerPoint (*.pptx)"]
        onAccepted: {
            page.lastSaveFolder = saveDialog.currentFolder
            page.savedUrl = selectedFile
            page.generating = true
            page.generatingKey = page.contentKey(page.blocks)
            backend.generatePpt(JSON.stringify(page.blocks.map(b => b.lines.join("\n"))), selectedFile.toString(), page.song ? page.song.title + " — " + page.song.artist : "")
        }
    }

    FileDialog {
        id: templateDialog
        title: "PPT 템플릿"
        fileMode: FileDialog.OpenFile
        nameFilters: ["PowerPoint (*.pptx)"]
        onAccepted: {
            templateName.text = backend.setTemplate(selectedFile.toString())
            page.toastHost.show("템플릿을 바꿨어요")
        }
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        // ── 상단: 곡 정보 ──
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 100
            color: Theme.surface
            clip: true

            // 앨범아트를 흐리게 깐 배경
            Image {
                id: backdrop
                anchors.fill: parent
                anchors.margins: -40
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                cache: false
                visible: false
            }
            // 블러는 셰이더가 필요하므로 소프트웨어 렌더링에서는 생략
            MultiEffect {
                anchors.fill: backdrop
                visible: GraphicsInfo.api !== GraphicsInfo.Software
                source: backdrop
                blurEnabled: true
                blur: 1.0
                blurMax: 64
                saturation: 0.4
                opacity: backdrop.status === Image.Ready ? 0.35 : 0
                Behavior on opacity { NumberAnimation { duration: 500 } }
            }

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 24
                anchors.rightMargin: 24
                spacing: 16
                AppButton {
                    id: backButton
                    text: "뒤로"
                    glyph: "chevron-left"
                    variant: "ghost"
                    onClicked: page.backRequested()
                    ToolTip.visible: hovered
                    ToolTip.delay: 600
                    ToolTip.text: "뒤로 (Esc)"
                }
                RoundedImage {
                    id: art
                    Layout.preferredWidth: 64
                    Layout.preferredHeight: 64
                    radius: 10
                    placeholder: Theme.surface2
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 4
                    Text {
                        Layout.fillWidth: true
                        text: page.song ? page.song.title : ""
                        textFormat: Text.PlainText
                        color: Theme.text
                        font.family: Theme.font
                        font.pixelSize: 20
                        font.weight: Font.Bold
                        elide: Text.ElideRight
                    }
                    Text {
                        Layout.fillWidth: true
                        text: page.song ? [page.song.artist, page.song.album].filter(Boolean).join(" · ") : ""
                        textFormat: Text.PlainText
                        color: Theme.text2
                        font.family: Theme.font
                        font.pixelSize: 14
                        elide: Text.ElideRight
                    }
                }
            }
            Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Theme.border }
        }

        // ── 본문: 가사 | 슬라이드 ──
        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.margins: 24
            Layout.topMargin: 20
            Layout.bottomMargin: 12
            spacing: 20

            // 가사 편집
            ColumnLayout {
                // 두 열은 내용(줄바꿈 배지 등)과 무관하게 비율로만 나눈다. 배지가 켜지고 꺼질 때 가사 칸 폭이 바뀌면 입력 중인 줄이 다시 흐른다
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.preferredWidth: 0
                Layout.horizontalStretchFactor: 1000
                spacing: 10

                RowLayout {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 34
                    Text { text: "가사"; color: Theme.text; font.family: Theme.font; font.pixelSize: 15; font.weight: Font.Bold }
                    HelpButton { Layout.leftMargin: 2; onClicked: help.lyrics() }
                    Item { Layout.fillWidth: true }
                    RowLayout {
                        id: autoSplitRow
                        spacing: 5
                        Text { text: "자동 나누기"; color: Theme.text3; font.family: Theme.font; font.pixelSize: 12; Layout.rightMargin: 4 }
                        Repeater {
                            model: [1, 2]
                            delegate: Button {
                                id: splitBtn
                                required property int modelData
                                text: modelData + "줄"
                                hoverEnabled: true
                                implicitHeight: 28
                                leftPadding: 10; rightPadding: 10
                                contentItem: Text {
                                    text: splitBtn.text
                                    color: splitBtn.hovered ? Theme.primary : Theme.text2
                                    font.family: Theme.font
                                    font.pixelSize: 12
                                    font.weight: Font.DemiBold
                                    verticalAlignment: Text.AlignVCenter
                                }
                                background: Rectangle {
                                    radius: 8
                                    color: splitBtn.hovered ? Theme.primarySoft : Theme.surface
                                    border.width: 1
                                    border.color: splitBtn.hovered ? Theme.primary : Theme.border
                                }
                                onClicked: page.autoSplit(modelData)
                            }
                        }
                    }
                }

                Rectangle {
                    id: lyricsBox
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    radius: Theme.radius
                    color: Theme.surface
                    border.width: 1.5
                    border.color: lyrics.activeFocus ? Theme.focusBorder : Theme.border
                    Behavior on border.color { ColorAnimation { duration: Theme.fast } }

                    ScrollView {
                        id: lyricsScroll
                        anchors.fill: parent
                        anchors.margins: 2

                        TextArea {
                            id: lyrics
                            padding: 14
                            color: Theme.text
                            font.family: Theme.font
                            font.pixelSize: 14
                            selectByMouse: true
                            selectionColor: Theme.primarySoft
                            selectedTextColor: Theme.text
                            wrapMode: TextEdit.Wrap
                            placeholderText: "가사를 입력하세요"
                            placeholderTextColor: Theme.text3
                            background: null

                            onTextChanged: {
                                if (page.applying) return
                                page.spans = E.parseBlocks(text)
                                // 슬라이드가 생기거나 없어지면 바로, 줄 내용만 바뀌면 모아서 목록을 갱신한다
                                if (page.spans.length !== page.blocks.length) page.sync()
                                else if (!syncTimer.running) syncTimer.start()
                                page.syncActiveFromCaret()
                                if (page.recordNextInput) {
                                    page.recordNextInput = false
                                    page.record(text)
                                } else {
                                    typingTimer.restart()
                                }
                            }
                            onCursorPositionChanged: if (!page.applying) page.syncActiveFromCaret()
                            onActiveFocusChanged: if (!activeFocus) longCheckTimer.restart()

                            // ⌘Z / ⇧⌘Z 는 앱 전체 히스토리로 처리
                            Keys.onPressed: (event) => {
                                if (page.dragging) return
                                if (event.matches(StandardKey.Undo)) { page.undo(); event.accepted = true }
                                else if (event.matches(StandardKey.Redo)) { page.redo(); event.accepted = true }
                                else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) page.flushTyping()
                                else if (event.matches(StandardKey.Paste)) {
                                    page.flushTyping()
                                    page.recordNextInput = true
                                    Qt.callLater(() => { page.recordNextInput = false })   // 붙여 넣을 게 없었으면 풀어 둔다
                                }
                            }

                            // 미리보기에서 누른 슬라이드 위치를 잠깐 강조 (revealInText)
                            Rectangle {
                                id: revealMark
                                z: -1
                                x: lyrics.leftPadding - 6
                                width: lyrics.width - lyrics.leftPadding - lyrics.rightPadding + 12
                                radius: 6
                                color: Theme.primarySoft
                                opacity: 0
                                SequentialAnimation {
                                    id: revealAnim
                                    NumberAnimation { target: revealMark; property: "opacity"; to: 1; duration: 120 }
                                    PauseAnimation { duration: 700 }
                                    NumberAnimation { target: revealMark; property: "opacity"; to: 0; duration: 500 }
                                }
                            }
                        }
                    }
                }

                Row {
                    spacing: 6
                    Rectangle {
                        width: kbd.implicitWidth + 10; height: 18; radius: 4
                        color: Theme.surface
                        border.width: 1; border.color: Theme.border
                        anchors.verticalCenter: parent.verticalCenter
                        Text { id: kbd; anchors.centerIn: parent; text: "빈 줄"; color: Theme.text2; font.family: Theme.font; font.pixelSize: 11 }
                    }
                    Text {
                        text: "하나가 슬라이드의 경계가 돼요"
                        color: Theme.text3
                        font.family: Theme.font
                        font.pixelSize: 12
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }
            }

            // 슬라이드
            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.preferredWidth: 0
                Layout.horizontalStretchFactor: 1150
                spacing: 10

                RowLayout {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 34
                    Text { text: "슬라이드"; color: Theme.text; font.family: Theme.font; font.pixelSize: 15; font.weight: Font.Bold }
                    Rectangle {
                        visible: page.blocks.length > 0
                        width: countText.implicitWidth + 16; height: 20; radius: 10
                        color: Theme.primarySoft
                        Text { id: countText; anchors.centerIn: parent; text: page.blocks.length + "장"; color: Theme.primaryText; font.family: Theme.font; font.pixelSize: 12; font.weight: Font.DemiBold }
                    }
                    // PPT에서 줄바꿈되는 슬라이드 수. 누르면 그 슬라이드를 차례로 보여준다
                    Rectangle {
                        visible: page.wrapSlides.length > 0
                        width: wrapRow.implicitWidth + 16; height: 20; radius: 10
                        color: wrapArea.containsMouse ? Qt.darker(Theme.warningSoft, 1.05) : Theme.warningSoft
                        Row {
                            id: wrapRow
                            anchors.centerIn: parent
                            spacing: 4
                            Icon { glyph: "alert"; size: 12; color: Theme.warning; anchors.verticalCenter: parent.verticalCenter }
                            Text { text: "줄바꿈 " + page.wrapSlides.length + "장"; color: Theme.warning; font.family: Theme.font; font.pixelSize: 12; font.weight: Font.DemiBold }
                        }
                        MouseArea {
                            id: wrapArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: page.showNextWrap()
                        }
                        ToolTip.visible: wrapArea.containsMouse
                        ToolTip.delay: 400
                        ToolTip.text: "PPT에서 글상자 폭을 넘어 두 줄로 나뉘는 줄이 있어요. 누르면 차례로 보여줘요"
                                      + (page.fitBasis ? "\n기준: " + page.fitBasis : "")
                    }
                    HelpButton { Layout.leftMargin: 2; onClicked: help.slides() }
                    Item { Layout.fillWidth: true }
                    RowLayout {
                        id: keepTwoRow
                        spacing: 2
                        Layout.rightMargin: 6
                        CheckBox {
                            id: keepTwoBox
                            text: "2줄 유지"
                            checked: page.keepTwo
                            onToggled: page.keepTwo = checked
                            hoverEnabled: true
                            spacing: 6
                            padding: 4
                            ToolTip.visible: hovered
                            ToolTip.delay: 500
                            ToolTip.text: "줄을 옮길 때 넘치는 줄은 연쇄로 밀고, 빈자리는 연쇄로 당겨와 슬라이드마다 2줄씩 유지해요"
                            indicator: Rectangle {
                                x: keepTwoBox.leftPadding
                                anchors.verticalCenter: parent.verticalCenter
                                width: 16; height: 16; radius: 4
                                color: keepTwoBox.checked ? Theme.primary : Theme.surface
                                border.width: keepTwoBox.checked ? 0 : 1.5
                                border.color: keepTwoBox.hovered ? Theme.primary : Theme.border
                                Icon { anchors.centerIn: parent; visible: keepTwoBox.checked; glyph: "check"; size: 11; color: "white" }
                            }
                            contentItem: Text {
                                leftPadding: keepTwoBox.indicator.width + keepTwoBox.spacing
                                text: keepTwoBox.text
                                color: keepTwoBox.checked ? Theme.text : Theme.text2
                                font.family: Theme.font
                                font.pixelSize: 12
                                font.weight: Font.DemiBold
                                verticalAlignment: Text.AlignVCenter
                            }
                        }
                        HelpButton { onClicked: help.keepTwoHelp() }
                    }
                    RowLayout {
                        id: historyRow
                        spacing: 5
                        AppButton {
                            glyph: "undo"; variant: "ghost"; size: "small"
                            enabled: page.histIdx > 0
                            onClicked: page.undo()
                            ToolTip.visible: hovered; ToolTip.delay: 600; ToolTip.text: "되돌리기 (" + Theme.undoKey + ")"
                        }
                        AppButton {
                            glyph: "redo"; variant: "ghost"; size: "small"
                            enabled: page.histIdx < page.hist.length - 1
                            onClicked: page.redo()
                            ToolTip.visible: hovered; ToolTip.delay: 600; ToolTip.text: "다시 실행 (" + Theme.redoKey + ")"
                        }
                    }
                }

                SlideList {
                    id: slideList
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    blocks: page.blocks
                    ratios: page.lineRatios
                    active: page.active
                    resolveDrop: (src, raw) => page.resolveDrop(src, raw)
                    onCutRequested: (slide, at) => page.cutSlide(slide, at)
                    onJoinRequested: (slide) => page.joinSlides(slide)
                    onRemoveRequested: (slide) => page.removeSlide(slide)
                    onMoveRequested: (src, target) => page.moveLine(src, target)
                    onRevealRequested: (slide, line) => page.revealInText(slide, line)
                    onEditStarting: page.prepareEdit()
                }

                Text {
                    Layout.fillWidth: true
                    text: "줄을 <b>드래그</b>해 옆 슬라이드로 옮길 수 있어요"
                    textFormat: Text.StyledText
                    color: Theme.text3
                    font.family: Theme.font
                    font.pixelSize: 12
                    elide: Text.ElideRight
                }
            }
        }

        // ── 하단: 템플릿 / 생성 ──
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 74
            color: Theme.surface
            Rectangle { width: parent.width; height: 1; color: Theme.border }

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 24
                anchors.rightMargin: 24
                spacing: 8
                RowLayout {
                    id: templateRow
                    spacing: 8
                    Icon { glyph: "monitor"; color: Theme.text3 }
                    Text { text: "템플릿"; color: Theme.text3; font.family: Theme.font; font.pixelSize: 13 }
                    Text {
                        id: templateName
                        Component.onCompleted: text = page.customTemplate ? backend.templateName() : "기본 템플릿"
                        color: Theme.text
                        font.family: Theme.font
                        font.pixelSize: 13
                        font.weight: Font.DemiBold
                        elide: Text.ElideMiddle
                        Layout.maximumWidth: 260
                    }
                    AppButton { id: templateButton; visible: page.customTemplate; text: "변경"; variant: "ghost"; size: "small"; onClicked: templateDialog.open() }
                    Text {
                        visible: !page.customTemplate
                        text: "· 내 템플릿은 나중에 지원할 예정이에요"
                        color: Theme.text3
                        font.family: Theme.font
                        font.pixelSize: 12
                    }
                    HelpButton { onClicked: help.generate() }
                }
                Item { Layout.fillWidth: true }
                // 꺼진 버튼은 호버를 받지 못해, 바깥에 둔 영역으로 이유를 보여 준다
                Item {
                    implicitWidth: 140
                    implicitHeight: generateButton.implicitHeight
                    AppButton {
                        id: generateButton
                        anchors.fill: parent
                        text: "PPT 생성"
                        variant: "primary"
                        size: "large"
                        busy: page.generating
                        enabled: page.blocks.length > 0
                        onClicked: page.generate()
                    }
                    MouseArea {
                        anchors.fill: parent
                        visible: !generateButton.enabled
                        hoverEnabled: true
                        acceptedButtons: Qt.NoButton
                        ToolTip.visible: containsMouse
                        ToolTip.delay: 300
                        ToolTip.text: "가사를 입력하면 만들 수 있어요"
                    }
                }
            }
        }
    }
}
