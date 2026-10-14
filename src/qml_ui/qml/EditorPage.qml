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
    property var generatingKeys: ({})    // 만드는 중인 PPT에 들어간 곡별 내용 (song_id → contentKey)
    readonly property bool dirty: song !== null && contentKey(blocks) !== savedKey

    // ── 콘티 ── 여러 곡을 순서대로 한 PPT로 만든다. 편집기는 고른 곡 하나만 다룬다.
    // 곡마다 가사 텍스트가 유일한 원본이고, 편집 상태는 세션 메모리에만 둔다 (파일로 남기지 않음 → 닫을 때 확인).
    // sessions: song_id → { song, text, hist, histIdx, cursor, contentY, slideY, kept, savedKey, dirty, slides, wraps }
    //   지금 편집 중인 곡은 화면이 최신이고 sessions의 값은 곡을 바꾸거나 화면을 떠날 때 갱신한다(storeCurrent).
    //   콘티에서 뺀 곡도 남겨 두어, 다시 넣으면 이어서 편집한다.
    property var sessions: ({})
    property var setlist: []            // 콘티 곡 순서 (song_id)
    readonly property string currentId: song ? song.song_id : ""
    // 곡 목록 패널에 보일 내용 (지금 곡은 편집 중인 내용으로)
    readonly property var setlistEntries: setlist.map(id => id === currentId
        ? { id: id, title: song.title || "제목 없음", artist: song.artist, slides: blocks.length, wraps: wrapSlides.length }
        : { id: id, title: sessions[id].song.title || "제목 없음", artist: sessions[id].song.artist,
            slides: sessions[id].slides, wraps: sessions[id].wraps })
    readonly property int deckSize: E.deckSize(setlistEntries.map(e => e.slides))
    // 콘티의 곡 중 PPT로 만들지 않은 편집이 있는지 / 콘티에서 뺀 곡까지 포함해서
    readonly property bool setlistDirty: dirty || setlist.some(id => id !== currentId && sessions[id].dirty)
    readonly property bool anyDirty: dirty || Object.keys(sessions).some(id => id !== currentId && sessions[id].dirty)

    signal backRequested()
    signal addSongRequested()
    signal feedbackRequested()

    // 머리글의 제목·가수 입력칸에 커서가 있다 (이때 ⌘Z는 그 칸의 되돌리기, Esc는 입력칸에서 빠져나오기)
    readonly property bool headerFocused: titleField.activeFocus || artistField.activeFocus
    readonly property bool lyricsFocused: lyrics.activeFocus || headerFocused
    readonly property bool dragging: slideList.dragging

    function contentKey(bs) { return E.serialize(E.linesOf(bs)) }
    function textKey(text) { return E.serialize(E.linesOf(E.parseBlocks(text))) }

    // ── 곡별 편집 상태 ──
    // 처음 여는 곡: 가사를 정리하고(맨 앞 제목 줄·절 번호·후렴 표시) 문단 안에서 2줄씩 자동으로 나눈다.
    // 정리한 게 있으면 정리 전 가사를 히스토리 첫 단계로 남겨 되돌릴 수 있게 하고, 처음 열 때 알린다(notice)
    function newEntry(newSong, lyricsText) {
        const clean = E.cleanText(lyricsText || "")
        const tidy = E.tidyMelonLyrics(clean, newSong.title)
        const text = E.serialize(E.regroupWithin(tidy.text, 2))
        const before = E.serialize(E.regroupWithin(clean, 2))
        const tidied = text !== before
        const groups = E.linesOf(E.parseBlocks(text))
        return { song: newSong, text: text, hist: tidied ? [before, text] : [text], histIdx: tidied ? 1 : 0,
                 cursor: 0, contentY: 0, slideY: 0, kept: {}, savedKey: text, dirty: false,
                 slides: groups.length, wraps: countWraps(groups), notice: tidied ? E.tidyMessage(tidy) : "" }
    }

    function saveState() {
        prepareEdit()
        flushTyping()
        return { song: song, text: lyrics.text, hist: hist, histIdx: histIdx, cursor: lyrics.cursorPosition,
                 contentY: lyricsScroll.contentItem.contentY, slideY: slideList.scrollY(),
                 kept: keptLongSlides, savedKey: savedKey, dirty: dirty,
                 slides: blocks.length, wraps: wrapSlides.length }
    }

    // 지금 곡의 편집 상태를 sessions에 보관한다 (곡을 바꾸거나 화면을 떠날 때)
    function storeCurrent() {
        if (!song) return
        const next = Object.assign({}, sessions)
        next[song.song_id] = saveState()
        sessions = next
    }

    function setEntry(id, entry) {
        const next = Object.assign({}, sessions)
        next[id] = entry
        sessions = next
    }

    function openEntry(id) { resume(sessions[id].song, sessions[id]) }

    // ── 콘티 편집 ──
    // 곡을 콘티 끝에 더하고 그 곡을 연다. lyricsText가 null이면 보관된 편집 상태로 이어서 편집한다.
    // 반환: 새로 더했으면 true, 이미 콘티에 있던 곡이면 false (그 곡을 연다)
    function addSong(newSong, lyricsText) {
        storeCurrent()
        const id = newSong.song_id
        if (!sessions[id]) setEntry(id, newEntry(newSong, lyricsText))
        const added = setlist.indexOf(id) < 0
        if (added) setlist = setlist.concat([id])
        if (id !== currentId) openEntry(id)
        return added
    }

    // 이 곡 하나로 새 콘티를 시작한다 (전에 편집한 곡들의 내용은 sessions에 남는다)
    function startSetlist(newSong, lyricsText) {
        storeCurrent()
        setlist = []
        addSong(newSong, lyricsText)
    }

    function selectSong(id) {
        if (id === currentId || !sessions[id]) return
        storeCurrent()
        openEntry(id)
    }

    function moveSong(from, to) {
        setlist = E.moveItem(setlist, from, to)
    }

    // 콘티에서 뺀다 (편집 내용은 남아 되돌리거나 다시 넣으면 이어서 편집). 곡이 하나뿐이면 빼지 않는다
    function removeSong(idx) {
        if (setlist.length <= 1 || idx < 0 || idx >= setlist.length) return
        storeCurrent()
        const id = setlist[idx]
        const next = setlist.slice()
        next.splice(idx, 1)
        setlist = next
        if (id === currentId) openEntry(next[Math.min(idx, next.length - 1)])
        if (toastHost)
            toastHost.show("'" + (sessions[id].song.title || "제목 없음") + "' 곡을 콘티에서 뺐어요",
                           { actionLabel: "되돌리기", duration: 5000, onAction: () => page.restoreSong(id, idx) })
    }

    function restoreSong(id, idx) {
        if (setlist.indexOf(id) >= 0 || !sessions[id]) return
        const next = setlist.slice()
        next.splice(Math.min(idx, next.length), 0, id)
        setlist = next
        selectSong(id)
    }

    // 콘티 곡별 슬라이드 (지금 곡은 편집 중인 내용으로). 부르기 전에 prepareEdit()
    function setlistGroups() {
        return setlist.map(id => id === currentId
            ? { id: id, song: song, groups: E.linesOf(blocks), kept: keptLongSlides }
            : { id: id, song: sessions[id].song, groups: E.linesOf(E.parseBlocks(sessions[id].text)), kept: sessions[id].kept })
    }

    // 지금 곡이 아닌 곡의 가사를 고친다 (그 곡의 히스토리에 남겨, 열어서 되돌릴 수 있다)
    function rewriteStored(id, text) {
        const st = sessions[id]
        if (st.text === text) return
        const hist = st.hist.slice(0, st.histIdx + 1).concat([text])
        if (hist.length > 200) hist.shift()
        const groups = E.linesOf(E.parseBlocks(text))
        setEntry(id, Object.assign({}, st, { text: text, hist: hist, histIdx: hist.length - 1,
                                             dirty: E.serialize(groups) !== st.savedKey,
                                             slides: groups.length, wraps: countWraps(groups) }))
    }

    function resume(newSong, st) {
        song = newSong
        // 직접 입력한 곡은 앨범아트가 없다
        art.source = newSong.manual ? "" : "image://art/" + newSong.song_id
        backdrop.source = art.source
        titleField.text = newSong.title
        artistField.text = newSong.artist
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
        // 처음 열면서 가사를 정리했으면 한 번 알린다 (되돌리면 정리 전 가사)
        if (st.notice) {
            const message = st.notice
            st.notice = ""
            showUndoToast(message)
        }
        // 직접 입력으로 연 곡은 바로 쓸 수 있게 한다: 제목이 비어 있으면 제목, 아니면 가사 칸
        if (newSong.manual && !st.text) (newSong.title ? lyrics : titleField).forceActiveFocus()
    }

    // 지금 히스토리 위치에서 되돌릴 수 있는 토스트 (편집이 이어지면 record()에서 숨김)
    function showUndoToast(message) {
        if (!toastHost) return
        const mine = histIdx
        toastHist = mine
        toastHost.show(message, { actionLabel: "되돌리기", duration: 5000,
                                  onAction: () => { if (page.histIdx === mine) page.undo() } })
    }

    // 머리글에서 제목·가수를 고쳤다 (파일 이름·콘티 목록에 반영)
    function setSongInfo(title, artist) {
        if (!song) return
        const t = title.trim(), a = artist.trim()
        if (t === song.title && a === song.artist) return
        song = Object.assign({}, song, { title: t, artist: a })
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
        if (lyrics.preeditText !== "" || titleField.preeditText !== "" || artistField.preeditText !== "") Qt.inputMethod.commit()
        flushSync()
    }

    // ── PPT 줄바꿈 미리 계산 ── 템플릿의 가사 글상자(글꼴·크기·폭) 기준 (src/utils/line_fit.py)
    property var lineRatios: []      // 슬라이드별·줄별 글상자 폭 대비 글자 폭 비율 (1을 넘으면 줄바꿈)
    property var wrapSlides: []      // 줄바꿈되는 줄이 있는 슬라이드 번호
    property int wrapCursor: -1      // 줄바꿈 표시를 누를 때마다 다음 슬라이드로
    property string fitBasis: ""     // 계산 기준 (안내 문구)
    property var ratioCache: new Map()   // 줄 → 비율. 입력할 때는 바뀐 줄만 계산한다

    // 캐시에 없는 줄만 계산한다. groups: 슬라이드별 줄 배열
    function fillRatios(groups) {
        if (ratioCache.size > 5000) ratioCache = new Map()
        const missing = []
        const seen = new Set()
        groups.forEach(lines => lines.forEach(l => {
            if (!ratioCache.has(l) && !seen.has(l)) { seen.add(l); missing.push(l) }
        }))
        if (missing.length) {
            const ratios = JSON.parse(backend.lineWidthRatios(JSON.stringify(missing)))
            missing.forEach((l, i) => ratioCache.set(l, ratios[i]))
        }
    }

    function measureLines(bs) {
        fillRatios(E.linesOf(bs))
        lineRatios = bs.map(b => b.lines.map(l => ratioCache.get(l)))
        wrapSlides = lineRatios.reduce((acc, r, i) => r.some(x => x > 1) ? acc.concat(i) : acc, [])
    }

    // 줄바꿈되는 줄이 있는 슬라이드 수 (콘티의 다른 곡 표시용)
    function countWraps(groups) {
        fillRatios(groups)
        return groups.filter(lines => lines.some(l => ratioCache.get(l) > 1)).length
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
        // 이 토스트가 알린 편집이 마지막일 때만 되돌린다 (다른 편집이 이어지면 record()에서 숨김)
        if (opts.message) showUndoToast(opts.message)
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

    // 아직 묻지 않은 3줄 이상 슬라이드 번호 (지금 곡)
    function freshLongSlides() {
        return E.longSlides(E.linesOf(blocks), keptLongSlides)
    }

    // 콘티 전체에서 아직 묻지 않은 3줄 이상 슬라이드: [{ id, title, slides: 번호[], keys: 내용[] }]
    function freshLongInSetlist() {
        return setlistGroups().map(s => {
            const slides = E.longSlides(s.groups, s.kept)
            return { id: s.id, title: s.song.title || "제목 없음", slides: slides, keys: slides.map(i => E.slideKey(s.groups[i])) }
        }).filter(s => s.slides.length)
    }

    function keepLongIn(id, keys) {
        if (id === currentId) { keepLong(keys); return }
        const kept = Object.assign({}, sessions[id].kept)
        keys.forEach(k => { kept[k] = true })
        setEntry(id, Object.assign({}, sessions[id], { kept: kept }))
    }

    // 입력칸에서 벗어났을 때: 나눌지, 그대로 둘지
    function askLongSlides(fresh) {
        const keys = fresh.map(i => E.slideKey(blocks[i].lines))
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

    // PPT 생성 전: 콘티 전체에서 그대로 만들지(주 버튼), 편집 화면으로 돌아가 2줄씩 나눌지. Esc·바깥 클릭은 아무것도 하지 않음
    // fresh: freshLongInSetlist() 결과. 곡이 여럿이면 곡 제목을 붙여 알린다
    function askLongBeforeGenerate(fresh) {
        const multi = setlist.length > 1
        confirmDialog.ask({
            title: "3줄 이상인 슬라이드가 있어요",
            message: fresh.map(s => (multi ? "'" + s.title + "' " : "") + longNames(s.slides)).join(", ")
                     + " 슬라이드가 3줄 이상이에요. 그대로 PPT를 만들까요, 2줄씩 나눌까요?",
            confirmText: "그대로 PPT 생성",
            cancelText: "2줄씩 나누기",
            onConfirm: () => { fresh.forEach(s => keepLongIn(s.id, s.keys)); openSaveDialog() },
            onCancel: () => splitLongInSetlist(fresh),
            onDismiss: null
        })
        const cur = fresh.find(s => s.id === currentId)
        if (cur) slideList.flash(cur.slides[0])
    }

    // 물어본 슬라이드만 2줄씩 나눈다. 다른 곡은 그 곡의 히스토리에 남긴다
    function splitLongInSetlist(fresh) {
        prepareEdit()
        let total = 0
        let songs = 0
        let current = null
        fresh.forEach(s => {
            if (s.id === currentId) { current = s; return }
            const r = E.splitAsked(E.linesOf(E.parseBlocks(sessions[s.id].text)), s.keys)
            if (!r.count) return
            rewriteStored(s.id, E.serialize(r.groups))
            total += r.count
            songs++
        })
        if (!songs) {
            if (current) splitLongSlides(current.keys)    // 지금 곡만: 되돌리기 토스트
            return
        }
        if (current) {
            const r = E.splitAsked(E.linesOf(blocks), current.keys)
            if (r.count) { commit(r.groups); total += r.count; songs++ }
        }
        if (toastHost) toastHost.show(songs + "곡에서 " + total + "장을 2줄씩 나눴어요 · 곡마다 되돌릴 수 있어요")
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
        if (generating || generateButton.pressed || backButton.pressed || setlistPanel.busy) return
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
        const r = E.splitAsked(E.linesOf(blocks), keys)
        if (r.count) commit(r.groups, { message: r.count + "장을 2줄씩 나눴어요" })
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

    // 줄 드래그: 옆 슬라이드로만 옮긴다. 2줄 유지를 켜면 넘친 줄은 연쇄로 민다 (줄이 빠진 슬라이드는 1줄로 남는다)
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

    // 붙여넣기 직전: 들어온 내용을 바로 한 단계로 남기도록 표시한다 (단축키·오른쪽 클릭 메뉴 공통)
    function notePaste() {
        flushTyping()
        recordNextInput = true
        Qt.callLater(() => { recordNextInput = false })   // 붙여 넣을 게 없었으면 풀어 둔다
    }

    function blurLyrics() { page.forceActiveFocus() }

    // 입력칸에서 Tab·Shift+Tab: 포커스 순서의 다음·이전 컨트롤로
    function moveFocusFrom(item, forward) {
        const next = item.nextItemInFocusChain(forward)
        if (next && next !== item) next.forceActiveFocus(forward ? Qt.TabFocusReason : Qt.BacktabFocusReason)
    }
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
        setlistPanel: setlistPanel
    }

    // ── 템플릿 / 생성 ──
    // 콘티 전체를 한 PPT로 만든다 (처음·곡 사이·끝의 빈 슬라이드는 ppt_engine이 넣는다).
    // 2줄 유지 중 3줄 이상 슬라이드가 있으면 먼저 묻고, 답에 맞춰 고친 뒤 저장 대화상자를 연다
    property string deckName: ""     // PPT 이름 (기본 파일 이름·문서 제목)

    function generate() {
        if (generating || saveDialog.visible) return
        prepareEdit()
        if (!deckSize) return    // 버튼과 단축키는 가사가 있을 때만 켜지지만 한 번 더 막는다
        longCheckTimer.stop()
        const fresh = keepTwo && confirmDialog ? freshLongInSetlist() : []
        if (fresh.length) askLongBeforeGenerate(fresh)
        else openSaveDialog()
    }

    function openSaveDialog() {
        deckName = E.deckTitle(setlist.map(id => id === currentId ? song : sessions[id].song), new Date())
        const name = E.safeFileName(deckName)
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

    // 콘티 전체를 fileUrl에 PPT로 저장한다 (저장 대화상자에서 고른 뒤)
    function writePpt(fileUrl) {
        prepareEdit()
        const songs = setlistGroups()
        const keys = {}
        songs.forEach(s => { keys[s.id] = E.serialize(s.groups) })
        deckName = E.deckTitle(songs.map(s => s.song), new Date())
        savedUrl = fileUrl
        generating = true
        generatingKeys = keys
        backend.generatePpt(JSON.stringify(songs.map(s => ({ title: s.song.title, artist: s.song.artist,
                                                             chunks: s.groups.map(lines => lines.join("\n")) }))),
                            fileUrl.toString(), deckName)
    }

    Connections {
        target: backend
        function onGenerateFinished(json) {
            page.generating = false
            const res = JSON.parse(json)
            if (res.error) {
                page.dialog.showError(res.error, res.detail)
            } else {
                // 이 내용까지는 PPT로 만들었다 (그 사이 다른 곡으로 바꿨을 수 있어 곡마다 반영)
                const keys = page.generatingKeys
                const next = Object.assign({}, page.sessions)
                Object.keys(keys).forEach(id => {
                    if (id === page.currentId) page.savedKey = keys[id]
                    else if (next[id]) next[id] = Object.assign({}, next[id], { savedKey: keys[id], dirty: page.textKey(next[id].text) !== keys[id] })
                })
                page.sessions = next
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
            const next = Object.assign({}, page.sessions)
            Object.keys(next).forEach(id => {
                next[id] = Object.assign({}, next[id], { wraps: page.countWraps(E.linesOf(E.parseBlocks(next[id].text))) })
            })
            page.sessions = next
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
            page.writePpt(selectedFile)
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
                    AppToolTip { visible: backButton.hovered; delay: 600; text: "뒤로 (Esc)" }
                }
                RoundedImage {
                    id: art
                    Layout.preferredWidth: 64
                    Layout.preferredHeight: 64
                    radius: 10
                    placeholder: Theme.surface2
                    // 앨범아트가 없으면(직접 입력·받지 못함) 음표
                    Icon { anchors.centerIn: parent; glyph: "music"; size: 26; color: Theme.text3; visible: !art.ready }
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2
                    // 제목·가수는 눌러서 고칠 수 있다 (PPT 파일 이름·콘티 목록에 쓰임)
                    TextField {
                        id: titleField
                        Layout.fillWidth: true
                        placeholderText: "제목"
                        placeholderTextColor: Theme.text3
                        color: Theme.text
                        font.family: Theme.font
                        font.pixelSize: 20
                        font.weight: Font.Bold
                        selectByMouse: true
                        leftPadding: 6; rightPadding: 6; topPadding: 2; bottomPadding: 2
                        background: Rectangle { radius: 6; color: "transparent"; border.width: titleField.activeFocus || titleField.hovered ? 1 : 0; border.color: titleField.activeFocus ? Theme.focusBorder : Theme.border }
                        hoverEnabled: true
                        onTextEdited: page.setSongInfo(text, artistField.text)
                        onEditingFinished: page.setSongInfo(text, artistField.text)
                        onAccepted: artistField.forceActiveFocus()
                        Accessible.name: "곡 제목"
                        ContextMenu.menu: AppTextMenu { editor: titleField }
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 0
                        TextField {
                            id: artistField
                            Layout.preferredWidth: Math.max(60, contentWidth + 14)
                            Layout.maximumWidth: 360
                            placeholderText: "가수"
                            placeholderTextColor: Theme.text3
                            color: Theme.text2
                            font.family: Theme.font
                            font.pixelSize: 14
                            selectByMouse: true
                            leftPadding: 6; rightPadding: 6; topPadding: 1; bottomPadding: 1
                            background: Rectangle { radius: 6; color: "transparent"; border.width: artistField.activeFocus || artistField.hovered ? 1 : 0; border.color: artistField.activeFocus ? Theme.focusBorder : Theme.border }
                            hoverEnabled: true
                            onTextEdited: page.setSongInfo(titleField.text, text)
                            onEditingFinished: page.setSongInfo(titleField.text, text)
                            onAccepted: lyrics.forceActiveFocus()
                            Accessible.name: "가수"
                            ContextMenu.menu: AppTextMenu { editor: artistField }
                        }
                        Text {
                            visible: !!(page.song && page.song.album)
                            text: page.song && page.song.album ? "· " + page.song.album : ""
                            textFormat: Text.PlainText
                            color: Theme.text3
                            font.family: Theme.font
                            font.pixelSize: 14
                            elide: Text.ElideRight
                            Layout.maximumWidth: 260
                        }
                        Item { Layout.fillWidth: true }
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

            // 콘티 (곡 목록)
            SetlistPanel {
                id: setlistPanel
                objectName: "setlistPanel"
                Layout.fillHeight: true
                Layout.preferredWidth: 200
                Layout.minimumWidth: 200
                entries: page.setlistEntries
                current: page.currentId
                deckSize: page.deckSize
                onSelected: (id) => page.selectSong(id)
                onRemoveRequested: (idx) => page.removeSong(idx)
                onMoveRequested: (from, to) => page.moveSong(from, to)
                onAddRequested: page.addSongRequested()
                onHelpRequested: help.setlistHelp()
            }

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
                    HelpButton { Layout.leftMargin: 2; label: "가사 편집"; onClicked: help.lyrics() }
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
                                    border.width: splitBtn.visualFocus ? 2 : 1
                                    border.color: splitBtn.hovered || splitBtn.visualFocus ? Theme.primary : Theme.border
                                }
                                onClicked: page.autoSplit(modelData)
                                Accessible.name: "자동 나누기 " + text
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
                            objectName: "lyricsInput"
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
                                    // 붙여 넣은 가사는 PPT를 망치는 글자(세로 탭·제로폭 문자 등)를 정리한다. 바뀐 구간만 고쳐 커서를 지킨다
                                    const cleaned = E.cleanText(text)
                                    if (cleaned !== text) page.setText(cleaned)
                                    page.record(lyrics.text)
                                } else {
                                    typingTimer.restart()
                                }
                            }
                            onCursorPositionChanged: if (!page.applying) page.syncActiveFromCaret()
                            onActiveFocusChanged: if (!activeFocus) longCheckTimer.restart()

                            // Tab은 탭 문자를 넣지 않고 다음(Shift+Tab은 이전) 컨트롤로 옮긴다. PPT에 탭이 남지 않고, 키보드로 뒤쪽 버튼에 닿는다
                            Keys.onTabPressed: (event) => { page.moveFocusFrom(lyrics, true); event.accepted = true }
                            Keys.onBacktabPressed: (event) => { page.moveFocusFrom(lyrics, false); event.accepted = true }
                            Accessible.name: "가사"

                            // 오른쪽 클릭 메뉴: 한국어, 되돌리기·다시 실행은 앱의 히스토리로
                            ContextMenu.menu: AppTextMenu {
                                editor: lyrics
                                useHistory: true
                                canUndo: page.histIdx > 0
                                canRedo: page.histIdx < page.hist.length - 1
                                undo: page.undo
                                redo: page.redo
                                beforePaste: page.notePaste
                            }

                            // ⌘Z / ⇧⌘Z 는 앱 전체 히스토리로 처리
                            Keys.onPressed: (event) => {
                                if (page.dragging) return
                                if (event.matches(StandardKey.Undo)) { page.undo(); event.accepted = true }
                                else if (event.matches(StandardKey.Redo)) { page.redo(); event.accepted = true }
                                else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) page.flushTyping()
                                else if (event.matches(StandardKey.Paste)) page.notePaste()
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
                        AppToolTip {
                            visible: wrapArea.containsMouse
                            delay: 400
                            text: "PPT에서 글상자 폭을 넘어 두 줄로 나뉘는 줄이 있어요. 누르면 차례로 보여줘요"
                                  + (page.fitBasis ? "\n기준: " + page.fitBasis : "")
                        }
                    }
                    HelpButton { Layout.leftMargin: 2; label: "슬라이드"; onClicked: help.slides() }
                    Item { Layout.fillWidth: true }
                    RowLayout {
                        id: keepTwoRow
                        spacing: 2
                        Layout.rightMargin: 6
                        CheckBox {
                            id: keepTwoBox
                            objectName: "keepTwoBox"
                            text: "2줄 유지"
                            checked: page.keepTwo
                            onToggled: page.keepTwo = checked
                            hoverEnabled: true
                            spacing: 6
                            padding: 4
                            AppToolTip {
                                visible: keepTwoBox.hovered
                                text: "줄을 옮길 때 넘치는 줄을 연쇄로 밀어서 슬라이드마다 2줄을 넘지 않게 해요. 줄을 준 슬라이드는 1줄로 남아요"
                            }
                            indicator: Rectangle {
                                x: keepTwoBox.leftPadding
                                anchors.verticalCenter: parent.verticalCenter
                                width: 16; height: 16; radius: 4
                                color: keepTwoBox.checked ? Theme.primary : Theme.surface
                                border.width: keepTwoBox.checked ? 0 : 1.5
                                border.color: keepTwoBox.hovered || keepTwoBox.visualFocus ? Theme.primary : Theme.border
                                // 키보드 포커스 링
                                Rectangle {
                                    anchors.fill: parent
                                    anchors.margins: -3
                                    radius: 7
                                    color: "transparent"
                                    border.width: 2
                                    border.color: Theme.primary
                                    visible: keepTwoBox.visualFocus
                                }
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
                        HelpButton { label: "2줄 유지"; onClicked: help.keepTwoHelp() }
                    }
                    RowLayout {
                        id: historyRow
                        spacing: 5
                        AppButton {
                            glyph: "undo"; variant: "ghost"; size: "small"
                            enabled: page.histIdx > 0
                            onClicked: page.undo()
                            Accessible.name: "되돌리기"
                            AppToolTip { visible: parent.hovered; delay: 600; text: "되돌리기 (" + Theme.undoKey + ")" }
                        }
                        AppButton {
                            glyph: "redo"; variant: "ghost"; size: "small"
                            enabled: page.histIdx < page.hist.length - 1
                            onClicked: page.redo()
                            Accessible.name: "다시 실행"
                            AppToolTip { visible: parent.hovered; delay: 600; text: "다시 실행 (" + Theme.redoKey + ")" }
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
                    HelpButton { label: "PPT 생성"; onClicked: help.generate() }
                }
                // '문의하기' (Main의 FeedbackDialog). 튜토리얼 강조 영역(templateRow)에 들어가지 않게 밖에 둔다
                AppButton {
                    Layout.leftMargin: 8
                    text: "문의하기"
                    glyph: "message"
                    variant: "ghost"
                    size: "small"
                    onClicked: page.feedbackRequested()
                }
                Item { Layout.fillWidth: true }
                // 꺼진 버튼은 호버를 받지 못해, 바깥에 둔 영역으로 이유를 보여 준다
                Item {
                    implicitWidth: 140
                    implicitHeight: generateButton.implicitHeight
                    AppButton {
                        id: generateButton
                        objectName: "generateButton"
                        anchors.fill: parent
                        text: "PPT 생성"
                        variant: "primary"
                        size: "large"
                        busy: page.generating
                        enabled: page.deckSize > 0
                        onClicked: page.generate()
                    }
                    MouseArea {
                        id: generateHint
                        anchors.fill: parent
                        visible: !generateButton.enabled
                        hoverEnabled: true
                        acceptedButtons: Qt.NoButton
                        AppToolTip { visible: generateHint.containsMouse; delay: 300; text: "가사를 입력하면 만들 수 있어요" }
                    }
                }
            }
        }
    }
}
