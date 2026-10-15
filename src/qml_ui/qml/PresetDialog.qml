import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import "."
import "editor.js" as E

// 프리셋 고르기. 불러오면 그 프리셋의 슬라이드 그대로 편집 화면이 열린다.
// 곡마다 카드 하나(앨범아트·제목·가수, 곡은 가나다순)에 프리셋을 한 줄씩(최근 저장한 것부터) 두고,
// 슬라이드는 줄을 눌러 펼쳐야 번호와 가사 줄로 보인다(높이가 정해진 칸 안에서 스크롤).
//   openFor(song): 한 곡의 프리셋 (검색 결과의 '프리셋 N' 배지). song은 검색 결과의 곡 { song_id, title, artist, album, manual }
//   openLibrary(opts): 보관함 — 모든 곡의 프리셋, 곡 제목·가수·프리셋 이름으로 찾기.
//     opts.currentId: 편집 중인 곡(맨 위에 '편집 중'), opts.fromEditor: 편집 화면에서 열었다(불러오면 콘티에 바로 더함)
Popup {
    id: dialog
    property var song: null             // 한 곡 보기일 때의 곡 (보관함이면 null)
    readonly property bool library: song === null
    property string currentId: ""
    property bool fromEditor: false
    property var songs: []              // 보이는 곡: [{ song_id, title, artist, album, manual, image_url, presets }]
    property int totalCount: 0          // 전체 프리셋 수 (찾기 전)
    property int songCount: 0           // 전체 곡 수 (찾기 전)
    property string expandedId: ""      // 슬라이드를 펼친 프리셋
    property string renamingId: ""      // 이름을 고치는 중인 프리셋
    property string deletingId: ""      // 삭제를 한 번 더 확인하는 중인 프리셋
    readonly property int previewHeight: 180    // 펼친 슬라이드 목록의 최대 높이 (넘으면 그 안에서 스크롤)
    signal loadRequested(var song, var preset, bool fromEditor)

    function reset() {
        filter.text = ""
        expandedId = ""
        renamingId = ""
        deletingId = ""
    }

    function openFor(s) {
        song = s
        currentId = ""
        fromEditor = false
        reset()
        refresh()
        if (songs.length) open()
    }

    function openLibrary(opts) {
        opts = opts || {}
        song = null
        currentId = opts.currentId || ""
        fromEditor = opts.fromEditor === true
        reset()
        refresh()
        open()
    }

    // 가나다순: 한글 → 영문 → 그 밖(숫자 등). 같은 무리 안에서는 글자 순, 제목이 같으면 가수
    function sortKey(text) {
        const t = (text || "").trim().toLowerCase()
        const c = t.charCodeAt(0)
        const group = c >= 0xAC00 && c <= 0xD7A3 || c >= 0x3131 && c <= 0x318E ? 0 : (c >= 97 && c <= 122 ? 1 : 2)
        return [group, t]
    }
    function compareSongs(a, b) {
        const ka = sortKey(a.title), kb = sortKey(b.title)
        if (ka[0] !== kb[0]) return ka[0] - kb[0]
        if (ka[1] !== kb[1]) return ka[1] < kb[1] ? -1 : 1
        return (a.artist || "") < (b.artist || "") ? -1 : (a.artist || "") > (b.artist || "") ? 1 : 0
    }

    function squash(text) { return (text || "").replace(/\s+/g, "").toLowerCase() }

    function refresh() {
        const all = JSON.parse(library ? backend.allPresets() : backend.presetsFor(song.song_id))
        totalCount = all.length
        // 곡마다 묶는다 (곡 안에서는 최근 저장한 것부터: 파일 순서)
        const groups = {}
        const list = []
        all.forEach(p => {
            if (!groups[p.song_id]) {
                groups[p.song_id] = { song_id: p.song_id, title: p.title, artist: p.artist, album: p.album || "",
                                      manual: p.manual === true, image_url: p.image_url || "", presets: [] }
                list.push(groups[p.song_id])
            }
            const g = groups[p.song_id]
            if (!g.image_url && p.image_url) g.image_url = p.image_url
            g.presets.push(p)
        })
        songCount = list.length
        list.sort(compareSongs)
        // 편집 화면에서 열었으면 편집 중인 곡이 맨 위
        const cur = list.findIndex(g => g.song_id === currentId)
        if (cur > 0) list.unshift(list.splice(cur, 1)[0])
        // 찾기: 곡 제목·가수가 맞으면 그 곡의 프리셋 모두, 프리셋 이름만 맞으면 그 프리셋만
        const key = squash(filter.text)
        songs = !key ? list : list.map(g => {
            if (squash(g.title + g.artist).indexOf(key) >= 0) return g
            const hits = g.presets.filter(p => squash(p.name).indexOf(key) >= 0)
            return hits.length ? Object.assign({}, g, { presets: hits }) : null
        }).filter(Boolean)
        if (!library && !songs.length) close()
    }

    // 프리셋에 저장된 곡 정보로 연다 (보관함에는 검색 결과의 곡이 없다)
    function songOf(group) {
        if (!library) return song
        return { song_id: group.song_id, title: group.title, artist: group.artist, album: group.album, manual: group.manual }
    }

    function load(group, preset) {
        const s = songOf(group)
        const editor = fromEditor
        close()
        loadRequested(s, preset, editor)
    }

    function toggle(preset) {
        deletingId = ""
        expandedId = expandedId === preset.id ? "" : preset.id
    }

    // 펼친 프리셋이 목록 아래로 잘리면 보이게 내린다 (위가 가려지지 않는 한에서).
    // 펼친 내용의 높이는 레이아웃이 다시 계산된 뒤에 정해지므로 잠깐 기다렸다가 잰다
    property Item revealTarget: null
    Timer { id: revealTimer; interval: 60; onTriggered: dialog.reveal(dialog.revealTarget) }
    function revealSoon(it) { revealTarget = it; revealTimer.restart() }
    function reveal(it) {
        if (!it || !it.visible) return
        const top = it.mapToItem(list.contentItem, 0, 0).y
        const bottom = top + it.height
        const viewBottom = list.contentY + list.height - list.bottomMargin
        if (bottom > viewBottom) list.contentY = Math.min(bottom - list.height + list.bottomMargin + 8, top - 8)
    }

    function startRename(preset) {
        deletingId = ""
        renamingId = preset.id
    }

    function finishRename(preset, name) {
        renamingId = ""
        if (name.trim() !== (preset.name || "")) backend.renamePreset(preset.id, name.trim())
        refresh()
    }

    function remove(preset) {
        renamingId = ""
        if (deletingId !== preset.id) { deletingId = preset.id; return }
        deletingId = ""
        backend.deletePreset(preset.id)
        refresh()
    }

    // '2026-10-15T14:03:00' → '2026년 10월 15일 오후 2:03' (short: '10월 15일', 올해가 아니면 '2025년 10월 15일')
    function dateText(iso, short) {
        const m = /^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2})/.exec(iso || "")
        if (!m) return ""
        const day = Number(m[2]) + "월 " + Number(m[3]) + "일"
        if (short) return (Number(m[1]) === new Date().getFullYear() ? "" : m[1] + "년 ") + day
        const h = Number(m[4])
        return m[1] + "년 " + day + " " + (h < 12 ? "오전 " : "오후 ") + ((h % 12) || 12) + ":" + m[5]
    }

    onAboutToShow: (library && totalCount ? filter : contentItem).forceActiveFocus()

    parent: Overlay.overlay
    anchors.centerIn: parent
    width: Math.min(600, parent.width - 32)
    // 내용에 맞추되, 찾는 동안 창이 출렁이지 않게 보관함은 최소 높이를 둔다
    height: Math.min(Math.max(implicitHeight, library ? 420 : 0), 720, parent.height - 64)
    modal: true
    focus: true
    padding: 0
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
    Overlay.modal: Rectangle { color: Qt.rgba(0, 0, 0, 0.4) }
    enter: Transition {
        NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 200 }
        NumberAnimation { property: "scale"; from: 0.96; to: 1; duration: 250; easing.type: Easing.OutCubic }
    }
    exit: Transition { NumberAnimation { property: "opacity"; to: 0; duration: 150 } }
    background: Rectangle { radius: 18; color: Theme.surface }

    contentItem: ColumnLayout {
        spacing: 0
        focus: true
        // Enter: 맨 위 곡의 맨 위 프리셋을 불러온다
        Keys.onReturnPressed: if (dialog.songs.length) dialog.load(dialog.songs[0], dialog.songs[0].presets[0])
        Keys.onEnterPressed: if (dialog.songs.length) dialog.load(dialog.songs[0], dialog.songs[0].presets[0])

        // ── 머리글: 제목·개수·닫기 ──
        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: 24
            Layout.rightMargin: 14
            Layout.topMargin: 18
            spacing: 8
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2
                Text {
                    text: dialog.library ? "보관함" : "프리셋"
                    color: Theme.text
                    font.family: Theme.font
                    font.pixelSize: 18
                    font.weight: Font.Bold
                }
                Text {
                    Layout.fillWidth: true
                    text: dialog.library
                          ? (dialog.totalCount ? "곡 " + dialog.songCount + "개 · 프리셋 " + dialog.totalCount + "개" : "저장한 프리셋이 없어요")
                          : (dialog.song ? [dialog.song.title, dialog.song.artist].filter(Boolean).join(" — ") : "")
                    textFormat: Text.PlainText
                    color: Theme.text3
                    font.family: Theme.font
                    font.pixelSize: 13
                    elide: Text.ElideRight
                }
            }
            AppButton {
                Layout.alignment: Qt.AlignTop
                glyph: "x"
                variant: "ghost"
                onClicked: dialog.close()
                Accessible.name: "닫기"
                AppToolTip { visible: parent.hovered; delay: 600; text: "닫기 (Esc)" }
            }
        }

        // ── 찾기 ──
        Rectangle {
            id: filterBox
            visible: dialog.library && dialog.totalCount > 0
            Layout.fillWidth: true
            Layout.leftMargin: 24
            Layout.rightMargin: 24
            Layout.topMargin: 14
            implicitHeight: 40
            radius: 10
            color: Theme.surface2
            border.width: filter.activeFocus ? 1.5 : 0
            border.color: Theme.focusBorder
            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 12
                anchors.rightMargin: 4
                spacing: 6
                Icon { glyph: "search"; size: 16; color: Theme.text3 }
                TextField {
                    id: filter
                    Layout.fillWidth: true
                    placeholderText: "곡 제목·가수·프리셋 이름으로 찾기"
                    placeholderTextColor: Theme.text3
                    color: Theme.text
                    font.family: Theme.font
                    font.pixelSize: 14
                    selectByMouse: true
                    leftPadding: 2; rightPadding: 2
                    background: null
                    onTextChanged: { dialog.expandedId = ""; dialog.refresh() }
                    Keys.onReturnPressed: if (dialog.songs.length) dialog.load(dialog.songs[0], dialog.songs[0].presets[0])
                    Keys.onEnterPressed: if (dialog.songs.length) dialog.load(dialog.songs[0], dialog.songs[0].presets[0])
                    Accessible.name: "보관함에서 찾기"
                    ContextMenu.menu: AppTextMenu { editor: filter }
                }
                AppButton {
                    visible: filter.text !== ""
                    glyph: "x"
                    variant: "ghost"
                    size: "small"
                    implicitHeight: 28
                    onClicked: { filter.text = ""; filter.forceActiveFocus() }
                    Accessible.name: "찾기 지우기"
                }
            }
        }

        // ── 비어 있을 때 ──
        ColumnLayout {
            visible: dialog.library && !dialog.songs.length
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.margins: 24
            spacing: 10
            Item { Layout.fillHeight: true }
            Icon { Layout.alignment: Qt.AlignHCenter; glyph: dialog.totalCount ? "search" : "library"; size: 32; color: Theme.text3; opacity: 0.6 }
            Text {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                text: dialog.totalCount ? "'" + filter.text.trim() + "'에 맞는 프리셋이 없어요"
                                        : "아직 저장한 프리셋이 없어요"
                textFormat: Text.PlainText
                color: Theme.text2
                font.family: Theme.font
                font.pixelSize: 14
                font.weight: Font.DemiBold
                wrapMode: Text.Wrap
            }
            Text {
                visible: !dialog.totalCount
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                text: "편집 화면 아래 '프리셋'의 '저장'으로 지금 슬라이드를 저장할 수 있어요"
                color: Theme.text3
                font.family: Theme.font
                font.pixelSize: 13
                wrapMode: Text.Wrap
            }
            Item { Layout.fillHeight: true }
        }

        // ── 곡 목록 ──
        ListView {
            id: list
            visible: dialog.songs.length > 0
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.topMargin: 14
            implicitHeight: contentHeight + bottomMargin
            clip: true
            spacing: 10
            leftMargin: 24
            rightMargin: 24
            bottomMargin: 20
            boundsBehavior: Flickable.StopAtBounds
            model: dialog.songs
            ScrollBar.vertical: ScrollBar {}

            // 곡 카드: 앨범아트·제목·가수, 아래에 프리셋 줄
            delegate: Rectangle {
                id: card
                required property var modelData
                readonly property bool current: modelData.song_id === dialog.currentId
                width: ListView.view.width - ListView.view.leftMargin - ListView.view.rightMargin
                height: cardColumn.implicitHeight + 16
                radius: Theme.radius
                color: Theme.surface
                border.width: 1
                border.color: current ? Theme.focusBorder : Theme.border

                // 앨범아트: 저장해 둔 그림 주소가 있으면 그림만 받는다 (보이는 카드만 만들어지므로 보이는 곡만 받음)
                Component.onCompleted: if (!modelData.manual) backend.loadArtFrom(modelData.song_id, modelData.image_url)
                Connections {
                    target: backend
                    function onArtReady(id) { if (id === card.modelData.song_id) art.source = "image://art/" + id }
                }

                ColumnLayout {
                    id: cardColumn
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: 8
                    spacing: 2

                    // 곡 머리글
                    RowLayout {
                        Layout.fillWidth: true
                        Layout.leftMargin: 6
                        Layout.rightMargin: 6
                        Layout.topMargin: 4
                        Layout.bottomMargin: 6
                        spacing: 12
                        RoundedImage {
                            id: art
                            Layout.preferredWidth: 40
                            Layout.preferredHeight: 40
                            radius: 8
                            placeholder: Theme.surface2
                            Icon { anchors.centerIn: parent; visible: !art.ready; glyph: "music"; size: 18; color: Theme.text3 }
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 1
                            Text {
                                Layout.fillWidth: true
                                text: card.modelData.title || "제목 없음"
                                textFormat: Text.PlainText
                                color: Theme.text
                                font.family: Theme.font
                                font.pixelSize: 15
                                font.weight: Font.Bold
                                elide: Text.ElideRight
                            }
                            Text {
                                Layout.fillWidth: true
                                text: [card.modelData.manual ? "직접 입력" : "", card.modelData.artist].filter(Boolean).join(" · ") || " "
                                textFormat: Text.PlainText
                                color: Theme.text3
                                font.family: Theme.font
                                font.pixelSize: 12
                                elide: Text.ElideRight
                            }
                        }
                        Rectangle {
                            visible: card.current
                            implicitWidth: currentLabel.implicitWidth + 14
                            implicitHeight: 22
                            radius: 11
                            color: Theme.primarySoft
                            Text { id: currentLabel; anchors.centerIn: parent; text: "편집 중"; color: Theme.primaryText; font.family: Theme.font; font.pixelSize: 11; font.weight: Font.Bold }
                        }
                    }

                    Repeater {
                        model: card.modelData.presets
                        delegate: ColumnLayout {
                            id: item
                            required property var modelData
                            readonly property var groups: E.linesOf(E.parseBlocks(modelData.text))
                            readonly property bool expanded: dialog.expandedId === modelData.id
                            readonly property bool renaming: dialog.renamingId === modelData.id
                            readonly property bool deleting: dialog.deletingId === modelData.id
                            readonly property bool named: !!modelData.name
                            readonly property string label: named ? modelData.name : dialog.dateText(modelData.saved_at, true) + " 저장"
                            // 연필·휴지통은 줄에 마우스를 올리거나 키보드로 왔을 때만 (불러오기는 늘)
                            readonly property bool showTools: rowHover.hovered || toggleArea.activeFocus || renameButton.activeFocus
                                                              || deleteButton.activeFocus || deleting
                            Layout.fillWidth: true
                            spacing: 0
                            onExpandedChanged: if (expanded) dialog.revealSoon(item)

                            Rectangle {
                                id: rowBox
                                Layout.fillWidth: true
                                implicitHeight: 44
                                radius: 10
                                color: item.expanded || rowHover.hovered ? Theme.surface2 : Theme.surface2Clear
                                Behavior on color { ColorAnimation { duration: Theme.fast } }
                                HoverHandler { id: rowHover }

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 6
                                    anchors.rightMargin: 6
                                    spacing: 2

                                    // 펼치기: 이름·정보를 누른다 (키보드는 Tab으로 와서 Space·Enter)
                                    Item {
                                        id: toggleArea
                                        Layout.fillWidth: true
                                        Layout.fillHeight: true
                                        visible: !item.renaming
                                        activeFocusOnTab: true
                                        Keys.onSpacePressed: dialog.toggle(item.modelData)
                                        Keys.onReturnPressed: dialog.toggle(item.modelData)
                                        Keys.onEnterPressed: dialog.toggle(item.modelData)
                                        Accessible.role: Accessible.Button
                                        Accessible.name: item.label + ", " + item.groups.length + "장, " + (item.expanded ? "슬라이드 접기" : "슬라이드 펼쳐 보기")
                                        Accessible.onPressAction: dialog.toggle(item.modelData)
                                        RowLayout {
                                            anchors.fill: parent
                                            spacing: 6
                                            Icon {
                                                glyph: "chevron-right"
                                                size: 14
                                                color: Theme.text3
                                                rotation: item.expanded ? 90 : 0
                                                Behavior on rotation { NumberAnimation { duration: Theme.fast } }
                                            }
                                            Text {
                                                Layout.maximumWidth: toggleArea.width * 0.65
                                                text: item.label
                                                textFormat: Text.PlainText
                                                color: item.named ? Theme.text : Theme.text2
                                                font.family: Theme.font
                                                font.pixelSize: 14
                                                font.weight: item.named ? Font.DemiBold : Font.Normal
                                                elide: Text.ElideRight
                                            }
                                            Text {
                                                Layout.fillWidth: true
                                                text: (item.named ? dialog.dateText(item.modelData.saved_at, true) + " · " : "") + item.groups.length + "장"
                                                color: Theme.text3
                                                font.family: Theme.font
                                                font.pixelSize: 12
                                                elide: Text.ElideRight
                                            }
                                        }
                                        MouseArea {
                                            anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: dialog.toggle(item.modelData)
                                        }
                                        Rectangle {
                                            anchors.fill: parent
                                            anchors.margins: -2
                                            radius: 8
                                            color: "transparent"
                                            border.width: 2
                                            border.color: Theme.primary
                                            visible: toggleArea.activeFocus
                                        }
                                    }

                                    // 이름 고치기 (Enter 저장, Esc 취소)
                                    TextField {
                                        id: renameField
                                        visible: item.renaming
                                        Layout.fillWidth: true
                                        implicitHeight: 34
                                        placeholderText: "프리셋 이름"
                                        placeholderTextColor: Theme.text3
                                        color: Theme.text
                                        font.family: Theme.font
                                        font.pixelSize: 14
                                        maximumLength: 60
                                        selectByMouse: true
                                        leftPadding: 10; rightPadding: 10
                                        background: Rectangle { radius: 8; color: Theme.surface; border.width: 1.5; border.color: Theme.focusBorder }
                                        onVisibleChanged: if (visible) { text = item.modelData.name || ""; forceActiveFocus(); selectAll() }
                                        onAccepted: { Qt.inputMethod.commit(); dialog.finishRename(item.modelData, text) }
                                        Keys.onEscapePressed: (event) => { dialog.renamingId = ""; event.accepted = true }
                                        Accessible.name: "프리셋 이름"
                                        ContextMenu.menu: AppTextMenu { editor: renameField }
                                    }
                                    AppButton {
                                        visible: item.renaming
                                        glyph: "check"; variant: "primary"; size: "small"
                                        onClicked: { Qt.inputMethod.commit(); dialog.finishRename(item.modelData, renameField.text) }
                                        Accessible.name: "이름 저장"
                                    }
                                    AppButton {
                                        visible: item.renaming
                                        glyph: "x"; variant: "ghost"; size: "small"
                                        onClicked: dialog.renamingId = ""
                                        Accessible.name: "이름 고치기 취소"
                                    }

                                    AppButton {
                                        id: renameButton
                                        visible: !item.renaming && !item.deleting
                                        opacity: item.showTools ? 1 : 0
                                        glyph: "pencil"; variant: "ghost"; size: "small"
                                        onClicked: dialog.startRename(item.modelData)
                                        Accessible.name: "이름 고치기: " + item.label
                                        AppToolTip { visible: parent.hovered; delay: 400; text: "이름 고치기" }
                                    }
                                    AppButton {
                                        id: deleteButton
                                        visible: !item.renaming
                                        opacity: item.showTools ? 1 : 0
                                        glyph: "trash"
                                        text: item.deleting ? "삭제" : ""
                                        variant: item.deleting ? "danger" : "ghost"
                                        size: "small"
                                        onClicked: dialog.remove(item.modelData)
                                        Accessible.name: item.deleting ? "삭제 확인" : "삭제: " + item.label
                                        AppToolTip { visible: parent.hovered && !item.deleting; delay: 400; text: "삭제 (한 번 더 누르면 지워져요)" }
                                    }
                                    AppButton {
                                        visible: !item.renaming
                                        Layout.leftMargin: 4
                                        text: "불러오기"
                                        variant: "primary"
                                        size: "small"
                                        onClicked: dialog.load(card.modelData, item.modelData)
                                        Accessible.name: "불러오기: " + item.label
                                    }
                                }
                            }

                            // 슬라이드별 가사 배치 (펼쳤을 때만): 번호와 줄만. 높이는 previewHeight까지, 넘으면 이 안에서 스크롤
                            Rectangle {
                                visible: item.expanded
                                Layout.fillWidth: true
                                Layout.leftMargin: 26
                                Layout.rightMargin: 6
                                Layout.topMargin: 4
                                Layout.bottomMargin: 6
                                implicitHeight: Math.min(slideColumn.implicitHeight + 16, dialog.previewHeight)
                                radius: 8
                                color: Theme.bg
                                border.width: 1
                                border.color: Theme.border
                                Flickable {
                                    id: preview
                                    anchors.fill: parent
                                    anchors.margins: 1
                                    clip: true
                                    contentHeight: slideColumn.implicitHeight + 14
                                    boundsBehavior: Flickable.StopAtBounds
                                    ScrollBar.vertical: ScrollBar { policy: preview.contentHeight > preview.height ? ScrollBar.AlwaysOn : ScrollBar.AsNeeded }
                                    Column {
                                        id: slideColumn
                                        x: 7
                                        y: 7
                                        width: preview.width - 26
                                        spacing: 8
                                        Repeater {
                                            model: item.expanded ? item.groups : []
                                            delegate: Row {
                                                id: slideLine
                                                required property var modelData
                                                required property int index
                                                width: slideColumn.width
                                                spacing: 8
                                                Text {
                                                    width: 20
                                                    horizontalAlignment: Text.AlignRight
                                                    text: slideLine.index + 1
                                                    color: Theme.text3
                                                    font.family: Theme.font
                                                    font.pixelSize: 12
                                                    font.weight: Font.DemiBold
                                                }
                                                Text {
                                                    width: parent.width - 28
                                                    text: slideLine.modelData.join("\n")
                                                    textFormat: Text.PlainText
                                                    color: Theme.text2
                                                    font.family: Theme.font
                                                    font.pixelSize: 13
                                                    lineHeight: 1.2
                                                    wrapMode: Text.Wrap
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        // 편집 화면에서 열었을 때만: 불러오면 어떻게 되는지
        Text {
            visible: dialog.fromEditor && dialog.songs.length > 0
            Layout.fillWidth: true
            Layout.leftMargin: 24
            Layout.rightMargin: 24
            Layout.bottomMargin: 16
            text: "불러오면 콘티에 더해요. 편집 중인 곡이면 가사를 그 프리셋으로 바꿔요(되돌릴 수 있어요)."
            color: Theme.text3
            font.family: Theme.font
            font.pixelSize: 12
            wrapMode: Text.Wrap
        }
    }
}
