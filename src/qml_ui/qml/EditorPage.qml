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
    // sessions: song_id → { song, text, hist, histIdx, cursor, contentY, slideY, kept, savedKey, dirty, slides, wraps, loading }
    //   지금 편집 중인 곡은 화면이 최신이고 sessions의 값은 곡을 바꾸거나 곡 찾기 서랍을 열 때 갱신한다(storeCurrent).
    //   콘티에서 뺀 곡도 남겨 두어, 다시 넣으면 이어서 편집한다.
    //   loading: 멜론에서 가사를 받는 중인 곡 (콘티에 자리만 잡아 둔다, addLoading → fillLoading/dropLoading). 열지 않고 PPT·프리셋에서 건너뛴다
    property var sessions: ({})
    property var setlist: []            // 콘티 곡 순서 (song_id). 0곡까지 비울 수 있다 (빈 상태 + 서랍)
    readonly property string currentId: song ? song.song_id : ""
    // 곡 목록 패널에 보일 내용 (지금 곡은 편집 중인 내용으로)
    readonly property var setlistEntries: setlist.map(id => id === currentId
        ? { id: id, title: song.title || "제목 없음", artist: song.artist, slides: blocks.length, wraps: wrapSlides.length, loading: false }
        : { id: id, title: sessions[id].song.title || "제목 없음", artist: sessions[id].song.artist,
            slides: sessions[id].slides, wraps: sessions[id].wraps, loading: sessions[id].loading === true })
    readonly property int deckSize: E.deckSize(setlistEntries.map(e => e.slides))
    // 가사를 받는 중인 곡 (받는 동안 PPT 생성을 꺼 둔다)
    readonly property var loadingIds: setlist.filter(id => sessions[id] && sessions[id].loading === true)
    readonly property bool anyLoading: loadingIds.length > 0
    // 머리글의 콘티 요약
    readonly property string setlistSummary: !setlist.length ? "새 콘티"
        : "콘티 " + setlist.length + "곡" + (anyLoading ? " · 가사 받는 중 " + loadingIds.length + "곡" : "")
    // PPT로 만들지 않은 편집이 있는지 (콘티에서 뺀 곡까지 포함해서)
    readonly property bool anyDirty: dirty || Object.keys(sessions).some(id => id !== currentId && sessions[id].dirty)

    signal feedbackRequested()

    // ── 곡 찾기 서랍 ── '곡 추가'(⌘K/Ctrl+K)로 연다. 열려 있는 동안 담은 곡은 콘티에 쌓이기만 하고 편집기는 그대로,
    // 닫을 때 이번에 처음 담은 곡을 연다 (아직 가사를 받는 중이면 다 받은 뒤 연다, pendingOpenId)
    property alias drawer: songDrawer
    readonly property bool drawerOpen: songDrawer.opened
    property var drawerAdded: []        // 이번에 서랍을 연 뒤 콘티에 새로 담은 곡
    property string pendingOpenId: ""   // 가사를 다 받으면 열 곡
    // 서랍이 열려 있는 동안 콘티 곡의 지금 가사 (song_id → 텍스트). 편집기에 열린 곡은 화면의 가사로(서랍에서 바꾸면 sessions는 그대로라서)
    readonly property var appliedTexts: {
        if (!songDrawer.opened) return ({})
        const m = {}
        setlist.forEach(id => {
            if (song && id === currentId) m[id] = lyrics.text
            else if (sessions[id] && !sessions[id].loading) m[id] = sessions[id].text
        })
        return m
    }

    // tab: "melon"(검색칸에 포커스) | "library" | "manual". opts: SongDrawer.show의 opts (filterSong·manual)
    // tab을 주지 않으면 닫혀 있을 때는 멜론 탭으로 열고, 열려 있으면 탭을 그대로 둔다 (콘티를 다 뺐을 때 등)
    function openDrawer(tab, opts) {
        if (!songDrawer.opened) {
            prepareEdit()
            longCheckTimer.stop()
            storeCurrent()
            drawerAdded = []
            pendingOpenId = ""
            songDrawer.opened = true
            songDrawer.show(tab || "melon", opts)
        } else if (tab) {
            songDrawer.show(tab, opts)
        }
    }

    // openAdded: 이번에 담은 곡을 연다 (콘티를 되돌려 서랍을 닫을 때는 false)
    function closeDrawer(openAdded) {
        if (!songDrawer.opened) return
        songDrawer.opened = false
        const first = openAdded === false ? undefined : drawerAdded.find(id => setlist.indexOf(id) >= 0)
        drawerAdded = []
        page.forceActiveFocus()
        if (first !== undefined) openWhenReady(first)
        else if (!song) openFirstReady()
    }

    function noteAdded(id) {
        if (songDrawer.opened && drawerAdded.indexOf(id) < 0) drawerAdded = drawerAdded.concat([id])
    }

    function isLoading(id) { return !!sessions[id] && sessions[id].loading === true }

    function openWhenReady(id) {
        if (isLoading(id)) pendingOpenId = id
        else selectSong(id)
    }

    // 편집기가 비었을 때: 콘티에서 가사가 있는 첫 곡을 연다 (모두 받는 중이면 첫 곡을 받은 뒤)
    function openFirstReady() {
        const ready = setlist.find(id => !isLoading(id))
        if (ready !== undefined) selectSong(ready)
        else if (setlist.length) pendingOpenId = setlist[0]
    }

    readonly property bool lyricsFocused: lyrics.activeFocus
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

    // 프리셋으로 여는 곡: 텍스트를 그대로 쓴다 (정리·자동 나누기 없음).
    // 저장할 때 있던 3줄 이상 슬라이드는 그렇게 쓰기로 한 것이라 다시 묻지 않는다
    function presetEntry(newSong, text) {
        const groups = E.linesOf(E.parseBlocks(text))
        return { song: newSong, text: text, hist: [text], histIdx: 0,
                 cursor: 0, contentY: 0, slideY: 0, kept: longKeys(groups), savedKey: text, dirty: false,
                 slides: groups.length, wraps: countWraps(groups), notice: "" }
    }

    function longKeys(groups) {
        const kept = {}
        E.longSlides(groups, {}).forEach(i => { kept[E.slideKey(groups[i])] = true })
        return kept
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
    // 곡을 콘티 끝에 더한다. lyricsText가 null이면 보관된 편집 상태로 이어서 편집한다.
    // open: 그 곡을 편집기에 연다 (기본: 서랍이 닫혀 있을 때만. 서랍이 열려 있으면 콘티에 쌓기만 한다)
    // 반환: 새로 더했으면 true, 이미 콘티에 있던 곡이면 false
    function addSong(newSong, lyricsText, open) {
        if (open === undefined) open = !songDrawer.opened
        if (open) storeCurrent()
        const id = newSong.song_id
        if (!sessions[id] || isLoading(id)) setEntry(id, newEntry(newSong, lyricsText))
        const added = setlist.indexOf(id) < 0
        if (added) {
            setlist = setlist.concat([id])
            noteAdded(id)
        }
        if (open && id !== currentId) openEntry(id)
        return added
    }

    // 멜론에서 가사를 받는 동안 콘티 끝에 자리를 먼저 잡는다 (콘티 패널에 '가사 받는 중…')
    function addLoading(newSong) {
        const id = newSong.song_id
        setEntry(id, { song: newSong, loading: true, text: "", hist: [""], histIdx: 0,
                       cursor: 0, contentY: 0, slideY: 0, kept: {}, savedKey: "", dirty: false,
                       slides: 0, wraps: 0, notice: "" })
        if (setlist.indexOf(id) < 0) setlist = setlist.concat([id])
        noteAdded(id)
        if (!songDrawer.opened) pendingOpenId = id     // 서랍 밖(오류 창의 '다시 시도')에서 담았으면 받은 뒤 연다
    }

    // 받은 가사로 자리를 채운다. 열기로 한 곡이거나 편집기가 비어 있으면 연다
    function fillLoading(id, lyricsText) {
        if (!isLoading(id)) return
        setEntry(id, newEntry(sessions[id].song, lyricsText))
        if (songDrawer.opened || setlist.indexOf(id) < 0) return
        if (pendingOpenId === id || !song) {
            pendingOpenId = ""
            selectSong(id)
        }
    }

    // 가사를 받지 못했다: 잡아 둔 자리를 뺀다. 반환: 콘티에 있던 곡이면 true (오류를 알린다)
    function dropLoading(id) {
        if (!isLoading(id)) return false
        const listed = setlist.indexOf(id) >= 0
        setlist = setlist.filter(x => x !== id)
        drawerAdded = drawerAdded.filter(x => x !== id)
        const next = Object.assign({}, sessions)
        delete next[id]
        sessions = next
        if (pendingOpenId === id) pendingOpenId = ""
        if (!songDrawer.opened && !song) {
            if (setlist.length) openFirstReady()
            else openDrawer()
        }
        return listed
    }

    // 편집기를 비운다 (콘티가 비었을 때). 부르기 전에 storeCurrent()
    function clearEditor() {
        longCheckTimer.stop()
        typingTimer.stop()
        dismissUndoToast()
        song = null
        art.source = ""
        backdrop.source = ""
        keptLongSlides = {}
        savedKey = ""
        applying = true
        lyrics.text = ""
        applying = false
        sync()
        hist = []
        histIdx = -1
        active = -1
        wrapCursor = -1
    }

    // 콘티 비우기 (⋯ 메뉴): 확인 없이 비우고 되돌리기 토스트. 곡마다 편집한 내용은 sessions에 남아 다시 담으면 이어서 편집
    function clearSetlist() {
        if (!setlist.length) return
        prepareEdit()
        storeCurrent()
        const prev = setlist
        setlist = []
        pendingOpenId = ""
        clearEditor()
        openDrawer()
        if (toastHost)
            toastHost.show("콘티를 비웠어요", { actionLabel: "되돌리기", duration: 6000, onAction: () => page.restoreSetlist(prev) })
    }

    // 비운 콘티를 되돌린다 (그 사이 담은 곡은 뒤에 둔다)
    function restoreSetlist(prev) {
        const keep = prev.filter(id => !!sessions[id])
        setlist = keep.concat(setlist.filter(id => keep.indexOf(id) < 0))
        if (songDrawer.opened) closeDrawer(false)
        if (!song) openFirstReady()
    }

    // 직접 입력한 곡을 담는다 (서랍의 '직접 입력' 탭). 처음 여는 멜론 곡처럼 정리하고 2줄씩 나눈다(newEntry).
    // 이미 편집하던 곡이면(멜론 곡에서 넘어와 song_id가 같은 경우) 프리셋을 불러올 때처럼 히스토리에 남기고 바꾼다
    function addManual(newSong, text) {
        const id = newSong.song_id
        const entry = newEntry(newSong, text)
        if (sessions[id] && !isLoading(id)) {
            loadPreset(newSong, entry.text)
            return
        }
        const open = !songDrawer.opened
        if (open) storeCurrent()
        setEntry(id, entry)
        if (setlist.indexOf(id) < 0) {
            setlist = setlist.concat([id])
            noteAdded(id)
        }
        if (pendingOpenId === id) pendingOpenId = ""
        if (open) openEntry(id)
        if (toastHost) toastHost.show("'" + (newSong.title || "제목 없음") + "' 곡을 콘티에 담았어요")
    }

    // 프리셋으로 곡을 담는다. 이어서 편집하던 곡이면 가사를 그 프리셋으로 바꾸고 되돌릴 수 있게 한다
    // open: 그 곡을 편집기에 연다 (기본: 서랍이 닫혀 있을 때만)
    function loadPreset(newSong, text, open) {
        if (open === undefined) open = !songDrawer.opened
        if (open) storeCurrent()
        const id = newSong.song_id
        const existed = !!sessions[id] && !isLoading(id)
        if (!existed) setEntry(id, presetEntry(newSong, text))
        if (open && pendingOpenId === id) pendingOpenId = ""
        if (setlist.indexOf(id) < 0) {
            setlist = setlist.concat([id])
            noteAdded(id)
        }
        if (!existed) {
            if (open && id !== currentId) openEntry(id)
            if (toastHost) toastHost.show(open ? "프리셋으로 열었어요" : "프리셋을 콘티에 담았어요")
            return
        }
        // 서랍에서 담았는데 편집기에 열려 있지 않은 곡: 그 곡의 히스토리에 남기고 바꾼다
        if (!open && id !== currentId) {
            if (sessions[id].text === text) {
                if (toastHost) toastHost.show("이미 이 프리셋과 같아요")
                return
            }
            rewriteStored(id, text)
            keepLongIn(id, Object.keys(longKeys(E.linesOf(E.parseBlocks(text)))))
            if (toastHost) toastHost.show("'" + (newSong.title || "제목 없음") + "' 가사를 프리셋으로 바꿨어요 · 그 곡에서 되돌릴 수 있어요")
            return
        }
        if (id !== currentId) openEntry(id)
        prepareEdit()
        flushTyping()
        if (lyrics.text === text) {
            if (toastHost) toastHost.show("이미 이 프리셋과 같아요")
            return
        }
        keepLong(Object.keys(longKeys(E.linesOf(E.parseBlocks(text)))))
        setText(text)
        record(lyrics.text)
        lyrics.cursorPosition = 0
        setLyricsY(0)
        slideList.scrollToTop()
        showUndoToast("편집하던 가사를 프리셋으로 바꿨어요")
    }

    // 프리셋 저장 (PPT 생성과 따로): 이름을 물어 콘티 곡마다 지금 슬라이드를 저장한다.
    // 멜론 곡은 검색 결과의 '프리셋' 배지로, 직접 입력한 곡은 검색 결과 맨 위에, 모두 보관함에서 다시 불러온다
    // 편집 화면이 띄운 창 (열려 있으면 Main이 단축키를 끈다): 프리셋 저장, 보관한 PPT 관리
    readonly property bool presetSaveOpen: presetSaveDialog.opened || savedPptDialog.opened
    function savePresets() {
        prepareEdit()
        const songs = setlistGroups().filter(s => s.groups.length)
        if (!songs.length || presetSaveDialog.opened) return
        const now = new Date()
        presetSaveDialog.ask(songs.map(s => "'" + (s.song.title || "제목 없음") + "'"),
                             (now.getMonth() + 1) + "월 " + now.getDate() + "일",
                             (name) => page.writePresets(songs, name))
    }

    function writePresets(songs, name) {
        const res = JSON.parse(backend.savePresets(JSON.stringify(songs.map(s => ({
            song_id: s.id, title: s.song.title, artist: s.song.artist, album: s.song.album || "",
            manual: s.song.manual === true, text: E.serialize(s.groups) }))), name))
        if (res.error) {
            if (dialog) dialog.showError(res.error, res.detail)
            return
        }
        if (toastHost)
            toastHost.show((songs.length > 1 ? songs.length + "곡의 프리셋을 저장했어요" : "프리셋을 저장했어요")
                           + " · 저장한 곡에서 볼 수 있어요", { duration: 4000 })
    }

    PresetSaveDialog { id: presetSaveDialog; objectName: "presetSaveDialog" }
    SavedPptDialog {
        id: savedPptDialog
        objectName: "savedPptDialog"
        items: page.savedPpts
        placed: setlistPanel.placedSaved
        onDeleteRequested: (id) => page.deleteSavedPpt(id)
    }

    // 콘티에서 곡을 고른다. 가사를 받는 중인 곡은 다 받은 뒤 연다
    function selectSong(id) {
        if (id === currentId || !sessions[id]) return
        if (isLoading(id)) { pendingOpenId = id; return }
        storeCurrent()
        openEntry(id)
    }

    function moveSong(from, to) {
        setlist = E.moveItem(setlist, from, to)
    }

    // ── 서랍에서 콘티로 끌어다 놓기 ── (SongDragArea가 화면 좌표로 알린다)
    // 놓으면 누를 때와 같이 담고(멜론 곡·프리셋), 새로 담긴 곡을 놓은 자리로 옮긴다.
    // 콘티에 이미 있는 곡의 프리셋은 그 곡의 가사를 바꾸고 순서는 그대로
    property var songDrag: null          // { payload, label }
    function beginSongDrag(payload, label, sx, sy) {
        songDrag = { payload: payload, label: label }
        moveSongDrag(sx, sy)
    }
    function moveSongDrag(sx, sy) {
        const p = page.mapFromItem(null, sx, sy)
        dragGhost.x = p.x + 14
        dragGhost.y = p.y + 10
        const q = setlistPanel.mapFromItem(null, sx, sy)
        const inside = q.x >= 0 && q.y >= 0 && q.x <= setlistPanel.width && q.y <= setlistPanel.height
        setlistPanel.externalDrop = inside ? setlistPanel.gapAt(q.y) : -1
    }
    function endSongDrag(sx, sy) {
        moveSongDrag(sx, sy)
        const at = setlistPanel.externalDrop
        const drag = songDrag
        cancelSongDrag()
        if (at < 0 || !drag) return
        const before = setlist.length
        if (drag.payload.kind === "preset") songDrawer.presetChosen(drag.payload.song, drag.payload.preset)
        else songDrawer.songClicked(drag.payload.song)
        if (setlist.length === before + 1 && at < before) moveSong(before, at)
    }
    function cancelSongDrag() {
        songDrag = null
        setlistPanel.externalDrop = -1
    }

    // 콘티에서 뺀다 (편집 내용은 남아 되돌리거나 다시 넣으면 이어서 편집). 다 빼면 빈 상태와 함께 서랍을 연다
    function removeSong(idx) {
        if (idx < 0 || idx >= setlist.length) return
        storeCurrent()
        const id = setlist[idx]
        const next = setlist.slice()
        next.splice(idx, 1)
        setlist = next
        if (pendingOpenId === id) pendingOpenId = ""
        if (id === currentId) openNear(idx)
        if (toastHost)
            toastHost.show("'" + (sessions[id].song.title || "제목 없음") + "' 곡을 콘티에서 뺐어요",
                           { actionLabel: "되돌리기", duration: 5000, onAction: () => page.restoreSong(id, idx) })
        if (!setlist.length) openDrawer()
    }

    // ── 앞·뒤에 붙일 PPT ── (콘티 패널의 AttachList. 경로 목록은 backend가 state.json에 기억한다)
    property var attachments: ({ before: [], after: [], slides: 0, problems: 0 })
    property string attachSide: "before"     // 파일 대화상자로 고를 목록

    property var savedPpts: []               // 보관한 PPT (＋ 메뉴)

    // 목록 항목: 원본 파일 경로 또는 보관한 PPT { saved: id }
    function attachLists() {
        const entry = i => i.saved ? { saved: i.id } : i.path
        return { before: attachments.before.map(entry), after: attachments.after.map(entry) }
    }
    function setAttachLists(lists) {
        attachments = JSON.parse(backend.setAttachments(JSON.stringify(lists)))
    }
    // 파일이 옮겨졌거나 고쳐졌을 수 있어 앱으로 돌아올 때·PPT를 만들기 전에 다시 읽는다
    function refreshAttachments() {
        attachments = JSON.parse(backend.attachments())
        savedPpts = JSON.parse(backend.savedPpts())
    }
    function keepAttachment(side, idx) {
        const res = JSON.parse(backend.keepAttachment(side, idx))
        if (res.error) { dialog.showError(res.error, res.detail || ""); return }
        attachments = res.attachments
        savedPpts = JSON.parse(backend.savedPpts())
        const name = attachments[side][idx].name
        if (toastHost) toastHost.show(res.replaced ? "보관해 둔 '" + name + "' 파일을 새 파일로 바꿨어요"
                                                   : "'" + name + "' 파일을 보관했어요 · 목록에서 빼도 ＋에서 다시 불러와요")
    }
    function unkeepAttachment(side, idx) {
        const res = JSON.parse(backend.unkeepAttachment(side, idx))
        if (res.error) { if (toastHost) toastHost.show(res.error); return }
        attachments = res.attachments
        savedPpts = JSON.parse(backend.savedPpts())
        if (toastHost) toastHost.show("'" + res.name + "' 파일 보관을 풀었어요 · 원본 파일을 그때그때 읽어요")
    }
    function openSavedPpts() {
        savedPpts = JSON.parse(backend.savedPpts())
        savedPptDialog.open()
    }
    function addSavedAttachment(side, id) {
        const lists = attachLists()
        if (lists[side].some(e => e.saved === id)) return
        lists[side].push({ saved: id })
        setAttachLists(lists)
    }
    function deleteSavedPpt(id) {
        const item = savedPpts.find(i => i.id === id)
        attachments = JSON.parse(backend.deleteSavedPpt(id))
        savedPpts = JSON.parse(backend.savedPpts())
        if (toastHost && item) toastHost.show("보관한 '" + item.name + "' 파일을 지웠어요")
    }
    function addAttachments(side, urls) {
        const lists = attachLists()
        const skipped = []
        let added = 0
        for (const url of urls) {
            const info = JSON.parse(backend.inspectAttachment(url.toString()))
            if (!/\.pptx$/i.test(info.name) && !info.error) info.error = "PPT(.pptx) 파일만 넣을 수 있어요."
            if (info.error) { skipped.push(info); continue }
            if (lists[side].indexOf(info.path) >= 0) continue
            lists[side].push(info.path)
            added++
        }
        if (added) setAttachLists(lists)
        if (skipped.length && toastHost)
            toastHost.show(skipped.length === 1 ? "'" + skipped[0].name + "' 파일은 넣을 수 없어요 · " + skipped[0].error
                                                : skipped.length + "개 파일은 넣을 수 없어요 · PPT(.pptx) 파일만 넣을 수 있어요",
                           { duration: 6000 })
    }
    function removeAttachment(side, idx) {
        const before = attachLists()
        const lists = attachLists()
        const name = attachments[side][idx].name
        lists[side].splice(idx, 1)
        setAttachLists(lists)
        if (toastHost)
            toastHost.show("'" + name + "' 파일을 뺐어요", { actionLabel: "되돌리기", duration: 5000, onAction: () => page.setAttachLists(before) })
    }
    function moveAttachment(side, from, to) {
        const lists = attachLists()
        lists[side] = E.moveItem(lists[side], from, to)
        setAttachLists(lists)
    }
    function browseAttachments(side) {
        attachSide = side
        if (attachDialog.currentFolder.toString() === "")
            attachDialog.currentFolder = StandardPaths.writableLocation(StandardPaths.DocumentsLocation)
        attachDialog.open()
    }

    Connections {
        target: Qt.application
        function onStateChanged() {
            if (Qt.application.state === Qt.ApplicationActive) page.refreshAttachments()
        }
    }

    // 지금 곡을 뺀 뒤: idx 자리에서 가장 가까운, 가사가 있는 곡을 연다 (없으면 편집기를 비운다)
    function openNear(idx) {
        for (let d = 0; d < setlist.length; d++) {
            for (const i of [idx + d, idx - 1 - d]) {
                if (i >= 0 && i < setlist.length && !isLoading(setlist[i])) { openEntry(setlist[i]); return }
            }
        }
        clearEditor()
        if (setlist.length && !songDrawer.opened) pendingOpenId = setlist[0]
    }

    function restoreSong(id, idx) {
        if (setlist.indexOf(id) >= 0 || !sessions[id]) return
        const next = setlist.slice()
        next.splice(Math.min(idx, next.length), 0, id)
        setlist = next
        if (songDrawer.opened) closeDrawer(false)
        selectSong(id)
    }

    // 콘티 곡별 슬라이드 (지금 곡은 편집 중인 내용으로, 가사를 받는 중인 곡은 건너뜀). 부르기 전에 prepareEdit()
    function setlistGroups() {
        return setlist.filter(id => !isLoading(id)).map(id => id === currentId
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
    }

    // 지금 히스토리 위치에서 되돌릴 수 있는 토스트 (편집이 이어지면 record()에서 숨김)
    function showUndoToast(message) {
        if (!toastHost) return
        const mine = histIdx
        toastHist = mine
        toastHost.show(message, { actionLabel: "되돌리기", duration: 5000,
                                  onAction: () => { if (page.histIdx === mine) page.undo() } })
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

    Component.onCompleted: {
        refreshAttachments()
        updateFitBasis()
        // 시작할 때 콘티가 비어 있으면 곡 찾기 서랍을 연다
        if (!setlist.length) Qt.callLater(openDrawer)
    }

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
        const multi = setlistGroups().length > 1
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
        if (toastHost) toastHost.show(songs + "곡에서 긴 슬라이드를 2줄씩 나눴어요 · 곡마다 되돌릴 수 있어요")
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
        if (confirmDialog.visible || (tour && tour.visible) || (dialog && dialog.visible) || saveDialog.visible || presetSaveDialog.visible || savedPptDialog.visible) return
        if (songDrawer.opened || !song) return    // 곡 찾기 서랍으로 옮겨 갔다 (페이지 전환과 같음)
        if (generating || generateButton.pressed || loadPresetButton.pressed || savePresetButton.pressed || setlistPanel.busy) return
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
        if (r.count) commit(r.groups, { message: "긴 슬라이드를 2줄씩 나눴어요" })
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

    // 빈 곳을 누름: 가사·제목 입력 커서를 빼고 슬라이드 강조를 푼다 (가사를 다시 누르면 커서 위치의 슬라이드가 다시 강조됨)
    function clearSelection() {
        if (dragging) return
        page.forceActiveFocus()
        active = -1
    }

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
        savePresetButton: presetGroup
        setlistPanel: setlistPanel
    }

    // ── 템플릿 / 생성 ──
    // 콘티 전체를 한 PPT로 만든다 (처음·곡 사이·끝의 빈 슬라이드는 ppt_engine이 넣는다).
    // 2줄 유지 중 3줄 이상 슬라이드가 있으면 먼저 묻고, 답에 맞춰 고친 뒤 저장 대화상자를 연다
    property string deckName: ""     // PPT 이름 (기본 파일 이름·문서 제목)

    function generate() {
        if (generating || saveDialog.visible) return
        prepareEdit()
        if (!deckSize || anyLoading) return    // 버튼과 단축키는 가사가 있고 받는 중인 곡이 없을 때만 켜지지만 한 번 더 막는다
        refreshAttachments()
        if (attachments.problems) {
            const bad = attachments.before.concat(attachments.after).filter(i => i.error)
            dialog.showError("붙일 PPT에 문제가 있어요\n콘티의 앞·뒤 PPT 목록에서 빨갛게 표시된 파일을 빼거나 다시 넣어 주세요.",
                             bad.map(i => i.path + "\n" + i.error).join("\n\n"))
            return
        }
        longCheckTimer.stop()
        const fresh = keepTwo && confirmDialog ? freshLongInSetlist() : []
        if (fresh.length) askLongBeforeGenerate(fresh)
        else openSaveDialog()
    }

    function openSaveDialog() {
        deckName = E.deckTitle(setlistGroups().map(s => s.song), new Date())
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

    FileDialog {
        id: attachDialog
        title: page.attachSide === "before" ? "앞에 붙일 PPT" : "뒤에 붙일 PPT"
        fileMode: FileDialog.OpenFiles
        nameFilters: ["PowerPoint (*.pptx)"]
        onAccepted: page.addAttachments(page.attachSide, selectedFiles)
    }

    // 맨 아래 깔린 빈 곳 누름 받기: 버튼·입력칸·목록이 받지 않은 누름(머리글·여백·막대 바탕 등)은 여기로 와서 선택을 푼다
    MouseArea {
        anchors.fill: parent
        onPressed: (mouse) => { page.clearSelection(); mouse.accepted = false }
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        // ── 머리글: 앱 이름 · 콘티 요약 (오른쪽 끝에는 Main의 버전 표시가 놓인다) ──
        Rectangle {
            id: topBar
            Layout.fillWidth: true
            Layout.preferredHeight: 52
            color: Theme.surface
            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 20
                anchors.rightMargin: 120
                spacing: 12
                Text {
                    text: "Lyrics Slide Creator"
                    color: Theme.text
                    font.family: Theme.font
                    font.pixelSize: 16
                    font.weight: Font.ExtraBold
                    font.letterSpacing: -0.3
                }
                Text {
                    objectName: "setlistSummary"
                    Layout.fillWidth: true
                    text: page.setlistSummary
                    textFormat: Text.PlainText
                    color: Theme.text3
                    font.family: Theme.font
                    font.pixelSize: 13
                    elide: Text.ElideRight
                }
            }
            Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Theme.border }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 0

            // 콘티 (곡 목록)
            Rectangle {
                id: setlistColumn
                Layout.fillHeight: true
                Layout.preferredWidth: 230
                Layout.minimumWidth: 230
                color: Theme.surface
                Rectangle { anchors.right: parent.right; width: 1; height: parent.height; color: Theme.border }

                SetlistPanel {
                    id: setlistPanel
                    objectName: "setlistPanel"
                    anchors.fill: parent
                    anchors.topMargin: 14
                    anchors.leftMargin: 12
                    anchors.rightMargin: 12
                    anchors.bottomMargin: 12
                    entries: page.setlistEntries
                    pendingId: page.pendingOpenId
                    current: page.currentId
                    onSelected: (id) => page.selectSong(id)
                    onRemoveRequested: (idx) => page.removeSong(idx)
                    onMoveRequested: (from, to) => page.moveSong(from, to)
                    onAddRequested: page.openDrawer("melon")
                    onClearRequested: page.clearSetlist()
                    onHelpRequested: help.setlistHelp()
                    attachments: page.attachments
                    onAttachDropped: (side, urls) => page.addAttachments(side, urls)
                    onAttachBrowse: (side) => page.browseAttachments(side)
                    onAttachRemove: (side, idx) => page.removeAttachment(side, idx)
                    onAttachMove: (side, from, to) => page.moveAttachment(side, from, to)
                    savedPpts: page.savedPpts
                    onAttachKeep: (side, idx) => page.keepAttachment(side, idx)
                    onAttachSaved: (side, id) => page.addSavedAttachment(side, id)
                    onAttachUnkeep: (side, idx) => page.unkeepAttachment(side, idx)
                    onManageSaved: page.openSavedPpts()
                }

            }

            // 편집 영역: 곡을 열었으면 곡 정보 + 가사 | 슬라이드, 아니면 빈 상태
            Item {
                id: editorArea
                Layout.fillWidth: true
                Layout.fillHeight: true

                ColumnLayout {
                    anchors.fill: parent
                    spacing: 0
                    visible: page.song !== null

                // ── 곡 정보 ──
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 64      // 콘티·앞뒤 PPT 줄(40)과 어울리게 낮게
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
                        RoundedImage {
                            id: art
                            Layout.preferredWidth: 44
                            Layout.preferredHeight: 44
                            radius: 8
                            placeholder: Theme.surface2
                            // 앨범아트가 없으면(직접 입력·받지 못함) 음표
                            Icon { anchors.centerIn: parent; glyph: "music"; size: 20; color: Theme.text3; visible: !art.ready }
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 2
                            // 제목·가수는 글자로만 보인다 (고치지 않는다)
                            Text {
                                Layout.fillWidth: true
                                text: page.song ? page.song.title || "제목 없음" : ""
                                textFormat: Text.PlainText
                                color: Theme.text
                                font.family: Theme.font
                                font.pixelSize: 18
                                font.weight: Font.Bold
                                elide: Text.ElideRight
                            }
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 0
                                Text {
                                    visible: !!(page.song && page.song.artist)
                                    text: page.song ? page.song.artist : ""
                                    textFormat: Text.PlainText
                                    color: Theme.text2
                                    font.family: Theme.font
                                    font.pixelSize: 14
                                    elide: Text.ElideRight
                                    Layout.maximumWidth: 360
                                    Layout.rightMargin: 4
                                }
                                Text {
                                    visible: !!(page.song && page.song.album)
                                    text: page.song && page.song.album ? (page.song.artist ? "· " : "") + page.song.album : ""
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
                    Layout.margins: 20
                    Layout.topMargin: 16
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
                                    onActiveFocusChanged: {
                                        if (!activeFocus) longCheckTimer.restart()
                                        else if (!page.applying) page.syncActiveFromCaret()   // 빈 곳을 눌러 강조를 푼 뒤 같은 자리로 돌아와도 다시 강조
                                    }

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
                            // PPT에서 줄바꿈되는 슬라이드가 있다는 표시. 누르면 그 슬라이드를 차례로 보여준다
                            Rectangle {
                                visible: page.wrapSlides.length > 0
                                width: wrapRow.implicitWidth + 16; height: 20; radius: 10
                                color: wrapArea.containsMouse ? Qt.darker(Theme.warningSoft, 1.05) : Theme.warningSoft
                                Row {
                                    id: wrapRow
                                    anchors.centerIn: parent
                                    spacing: 4
                                    Icon { glyph: "alert"; size: 12; color: Theme.warning; anchors.verticalCenter: parent.verticalCenter }
                                    Text { text: "줄바꿈 있음"; color: Theme.warning; font.family: Theme.font; font.pixelSize: 12; font.weight: Font.DemiBold }
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
                            onBackgroundClicked: page.clearSelection()
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

                }

                // 빈 상태: 콘티가 비었거나 아직 가사를 받는 중
                // 서랍이 열려 있으면 서랍 옆(오른쪽)에, 닫히면 편집 영역 가운데에 둔다.
                // 서랍과 같은 속도로 두 자리 사이를 옮긴다 (비율만 움직여서 창 크기를 바꿀 때는 바로 따라감)
                Column {
                    objectName: "editorEmptyState"
                    visible: page.song === null
                    anchors.verticalCenter: parent.verticalCenter
                    property real besideDrawer: page.drawerOpen ? 1 : 0
                    Behavior on besideDrawer { NumberAnimation { duration: Theme.normal; easing.type: Easing.OutCubic } }
                    readonly property real centerX: (parent.width - width) / 2
                    readonly property real rightX: parent.width - width - Math.max(24, Math.min(60, parent.width - 430 - 24 - width))
                    x: centerX + (rightX - centerX) * besideDrawer
                    width: Math.min(300, parent.width - 48)
                    spacing: 10
                    Text {
                        width: parent.width
                        text: !page.setlist.length ? "곡을 담으면 여기서 가사를 다듬어요"
                            : page.drawerOpen ? "검색창을 닫으면 담은 곡을 열어요" : "가사를 받는 중이에요"
                        color: Theme.text
                        font.family: Theme.font
                        font.pixelSize: 17
                        font.weight: Font.Bold
                        wrapMode: Text.Wrap
                    }
                    Text {
                        width: parent.width
                        text: !page.setlist.length ? "빈 줄로 슬라이드를 나누고, 줄을 끌어 옮기고, 콘티 전체를 PPT 한 파일로 만들어요"
                            : page.drawerOpen ? "곡을 더 담거나 검색창을 닫아 주세요" : "다 받으면 바로 열어요"
                        color: Theme.text2
                        font.family: Theme.font
                        font.pixelSize: 13
                        lineHeight: 1.4
                        wrapMode: Text.Wrap
                    }
                }
            }
        }

        // ── 하단: 템플릿 / 생성 ── (곡 찾기 서랍은 이 막대 위까지만 연다)
        Rectangle {
            id: bottomBar
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
                // 프리셋: 불러오기(보관함) | 저장(이름을 붙여 콘티 곡마다). PPT 생성과 따로
                Rectangle {
                    id: presetGroup
                    objectName: "presetGroup"
                    implicitWidth: presetRow.implicitWidth + 8
                    implicitHeight: 46
                    radius: Theme.radiusSm
                    color: Theme.surface
                    border.width: 1
                    border.color: Theme.border
                    RowLayout {
                        id: presetRow
                        anchors.centerIn: parent
                        spacing: 2
                        Text {
                            Layout.leftMargin: 10
                            Layout.rightMargin: 4
                            text: "프리셋"
                            color: Theme.text3
                            font.family: Theme.font
                            font.pixelSize: 13
                            font.weight: Font.DemiBold
                        }
                        AppButton {
                            id: loadPresetButton
                            objectName: "loadPresetButton"
                            text: "불러오기"
                            glyph: "library"
                            variant: "ghost"
                            implicitHeight: 38
                            onClicked: page.openDrawer("library")
                            AppToolTip { visible: loadPresetButton.hovered; delay: 400; text: "저장한 곡에서 프리셋을 골라 콘티에 더해요. 콘티에 있는 곡이면 가사를 그 프리셋으로 바꿔요" }
                        }
                        Rectangle { Layout.preferredWidth: 1; Layout.preferredHeight: 20; color: Theme.border }
                        AppButton {
                            id: savePresetButton
                            objectName: "savePresetButton"
                            text: "저장"
                            glyph: "save"
                            variant: "ghost"
                            implicitHeight: 38
                            enabled: page.deckSize > 0
                            onClicked: page.savePresets()
                            AppToolTip {
                                visible: savePresetButton.hovered
                                delay: 400
                                text: "곡마다 지금 슬라이드를 이름을 붙여 저장해요 (" + Theme.mod + "S). 다음에 검색 결과나 저장한 곡에서 그대로 불러올 수 있어요"
                            }
                        }
                    }
                }
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
                        enabled: page.deckSize > 0 && !page.anyLoading
                        onClicked: page.generate()
                    }
                    MouseArea {
                        id: generateHint
                        anchors.fill: parent
                        visible: !generateButton.enabled
                        hoverEnabled: true
                        acceptedButtons: Qt.NoButton
                        AppToolTip { visible: generateHint.containsMouse; delay: 300; text: page.anyLoading ? "가사를 다 받으면 만들 수 있어요" : "가사를 입력하면 만들 수 있어요" }
                    }
                }
            }
        }
    }

    // ── 곡 찾기 서랍 ── 콘티 패널 오른쪽에서 열려 편집 영역을 덮는다. 뒤는 옅게 가리고, 누르면 닫는다
    Rectangle {
        id: drawerScrim
        x: setlistColumn.width
        y: topBar.height
        width: page.width - x
        height: bottomBar.y - y
        // 편집기가 비었으면(빈 상태 안내) 가리지 않는다
        color: Qt.rgba(0.08, 0.09, 0.11, !page.song ? 0 : Theme.dark ? 0.45 : 0.18)
        visible: opacity > 0
        opacity: songDrawer.opened ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Theme.normal } }
        MouseArea { anchors.fill: parent; enabled: songDrawer.opened; onClicked: page.closeDrawer() }
    }

    // 끌고 있는 곡 (커서를 따라간다, 서랍 위에 그린다)
    Rectangle {
        id: dragGhost
        visible: page.songDrag !== null
        z: 1000
        width: Math.min(260, ghostRow.implicitWidth + 24)
        height: 36
        radius: 10
        color: Theme.toastBg
        opacity: 0.94
        Row {
            id: ghostRow
            anchors.centerIn: parent
            spacing: 6
            Icon { glyph: "music"; size: 14; color: setlistPanel.externalDrop >= 0 ? Theme.primary : "white"; anchors.verticalCenter: parent.verticalCenter }
            Text {
                width: Math.min(implicitWidth, 214)
                text: page.songDrag ? page.songDrag.label : ""
                textFormat: Text.PlainText
                color: "white"
                font.family: Theme.font
                font.pixelSize: 13
                font.weight: Font.DemiBold
                elide: Text.ElideRight
                anchors.verticalCenter: parent.verticalCenter
            }
        }
    }

    SongDrawer {
        id: songDrawer
        objectName: "songDrawer"
        dragHost: page
        x: setlistColumn.width
        y: topBar.height
        width: Math.min(430, page.width - x)
        height: bottomBar.y - y
        emptySetlist: page.setlist.length === 0
        setlist: page.setlist
        loadingIds: page.loadingIds
        addedIds: page.drawerAdded
        currentId: page.currentId
        appliedTexts: page.appliedTexts
        tour: page.tour
        onCloseRequested: page.closeDrawer()
    }
}
