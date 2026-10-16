import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import "."

// 보관함: 프리셋이 있는 곡을 곡마다 카드 하나(앨범아트·제목·가수, 곡은 가나다순)로 보인다.
// 카드 오른쪽은 멜론 검색 결과 행과 같은 담을 버전 버튼(PresetPicker: 지금 설정 — 멜론 가사 그대로 또는 프리셋, 누르면 바꾸기·이름 고치기·삭제).
// 카드를 누르거나 콘티로 끌어다 놓으면 그 설정대로 담는다(콘티에 있는 곡이면 가사를 바꾼다).
// 곡 찾기 서랍(SongDrawer)의 '보관함' 탭. 내용은 refresh()를 불러야 다시 읽는다.
//   setlist: 콘티에 있는 song_id 배열. 들어 있는 곡 카드에는 '콘티 N번' 배지, 누르면 가사 바꾸기(replaceRequested)
//   filterSong: 비어 있지 않으면 그 곡 카드만. 찾기 칸은 숨긴다
//   currentId: 편집 중인 곡(맨 위)
//   appliedTexts: 콘티 곡의 지금 가사 (song_id → 텍스트). 설정된 프리셋과 같으면 카드를 연한 초록으로
Item {
    id: lib
    property var setlist: []
    property string filterSong: ""
    property string currentId: ""
    property var appliedTexts: ({})
    property int sideMargin: 24
    readonly property bool library: filterSong === ""
    property var songs: []              // 보이는 곡: [{ song_id, title, artist, album, manual, image_url, presets }]
    property int totalCount: 0          // 전체 프리셋 수 (찾기 전)
    property int songCount: 0           // 전체 곡 수 (찾기 전)
    property var dragHost: null       // 카드를 콘티로 끌어다 놓기 (EditorPage, SongDragArea)
    signal addRequested(var song, var preset)
    signal replaceRequested(var song, var preset)
    signal melonRequested(var song)     // 설정이 '멜론 가사 그대로'인 곡을 담기

    implicitHeight: body.implicitHeight

    function reset() { filter.text = "" }

    function focusFilter() { filter.forceActiveFocus() }

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
        const all = JSON.parse(library ? backend.allPresets() : backend.presetsFor(filterSong))
        totalCount = all.length
        // 곡마다 묶는다 (곡 안에서는 설정된 것이 맨 앞, 나머지는 최근 저장한 것부터: backend 순서)
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
        // 편집 중인 곡이 맨 위
        const cur = list.findIndex(g => g.song_id === currentId)
        if (cur > 0) list.unshift(list.splice(cur, 1)[0])
        // 찾기: 곡 제목·가수, 그 곡의 프리셋 이름 또는 가사 (공백·줄바꿈·대소문자 무시)
        const key = squash(filter.text)
        songs = !key ? list : list.filter(g => squash(g.title + g.artist).indexOf(key) >= 0
                                              || g.presets.some(p => squash(p.name).indexOf(key) >= 0 || squash(p.text).indexOf(key) >= 0))
    }

    // 프리셋에 저장된 곡 정보 (보관함에는 검색 결과의 곡이 없다)
    function songOf(group) {
        return { song_id: group.song_id, title: group.title, artist: group.artist, album: group.album, manual: group.manual }
    }

    function inSetlist(songId) { return (setlist || []).indexOf(songId) >= 0 }

    // 그 곡의 설정된 프리셋 (null이면 멜론 가사 그대로)
    function selectedOf(group) { return group.presets.find(p => p.default === true) || null }

    // 설정대로 담는다 (콘티에 있는 곡이면 프리셋으로 가사를 바꾼다)
    function add(group) {
        const s = songOf(group)
        const preset = selectedOf(group)
        if (!preset) melonRequested(s)
        else if (inSetlist(group.song_id)) replaceRequested(s, preset)
        else addRequested(s, preset)
    }

    // 찾기 칸에서 Enter: 맨 위 곡
    function loadFirst() {
        if (songs.length) add(songs[0])
    }

    ColumnLayout {
        id: body
        anchors.fill: parent
        spacing: 0

        // ── 찾기 ──
        Rectangle {
            id: filterBox
            visible: lib.library && lib.totalCount > 0
            Layout.fillWidth: true
            Layout.leftMargin: lib.sideMargin
            Layout.rightMargin: lib.sideMargin
            Layout.topMargin: 6
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
                    placeholderText: "곡 제목·가수·가사·프리셋 이름으로 찾기"
                    placeholderTextColor: Theme.text3
                    color: Theme.text
                    font.family: Theme.font
                    font.pixelSize: 14
                    selectByMouse: true
                    leftPadding: 2; rightPadding: 2
                    background: null
                    onTextChanged: lib.refresh()
                    Keys.onReturnPressed: lib.loadFirst()
                    Keys.onEnterPressed: lib.loadFirst()
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

        // ── 비어 있을 때 ── (양식 보관함과 같은 모양: 위쪽 가운데에 아이콘 · 제목 · 설명)
        ColumnLayout {
            visible: lib.library && !lib.songs.length
            Layout.fillWidth: true
            Layout.leftMargin: lib.sideMargin
            Layout.rightMargin: lib.sideMargin
            Layout.topMargin: 30
            spacing: 6
            Icon { Layout.alignment: Qt.AlignHCenter; glyph: lib.totalCount ? "search" : "library"; size: 28; color: Theme.text3; opacity: 0.6 }
            Text {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                text: lib.totalCount ? "'" + filter.text.trim() + "'에 맞는 곡이 없어요"
                                     : "아직 저장한 프리셋이 없어요"
                textFormat: Text.PlainText
                color: Theme.text2
                font.family: Theme.font
                font.pixelSize: 14
                font.weight: Font.DemiBold
                wrapMode: Text.Wrap
            }
            BalancedText {
                visible: !lib.totalCount
                maxWidth: Math.min(360, parent.width)
                Layout.preferredWidth: fitWidth
                Layout.alignment: Qt.AlignHCenter
                horizontalAlignment: Text.AlignHCenter
                source: "편집 화면 아래 '프리셋'의 '저장'으로 곡마다 지금 슬라이드를 저장해 두면 여기서 콘티에 바로 넣을 수 있어요."
                color: Theme.text3
                font.family: Theme.font
                font.pixelSize: 13
                lineHeight: 1.4
            }
        }
        Item { visible: lib.library && !lib.songs.length; Layout.fillHeight: true }

        // ── 곡 목록 ──
        ListView {
            id: list
            visible: lib.songs.length > 0
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.topMargin: 14
            implicitHeight: contentHeight + bottomMargin
            clip: true
            spacing: 10
            leftMargin: lib.sideMargin
            rightMargin: lib.sideMargin
            bottomMargin: 20
            boundsBehavior: Flickable.StopAtBounds
            model: lib.songs
            ScrollBar.vertical: ScrollBar {}

            // 곡 카드: 앨범아트·제목·가수, 오른쪽에 '콘티 N번'·담을 버전 버튼. 누르거나 끌어다 놓으면 설정대로 담는다
            delegate: Rectangle {
                id: card
                required property var modelData
                readonly property int setlistNo: (lib.setlist || []).indexOf(modelData.song_id) + 1
                readonly property var selected: lib.selectedOf(modelData)
                readonly property bool applied: setlistNo > 0 && !!selected && lib.appliedTexts[modelData.song_id] === selected.text
                width: ListView.view.width - ListView.view.leftMargin - ListView.view.rightMargin
                height: 64
                radius: Theme.radius
                color: applied ? (cardArea.containsMouse ? Theme.primarySoftHover : Theme.primarySoft)
                     : cardArea.containsMouse || picker.hovered ? Theme.surface2 : Theme.surface
                Behavior on color { ColorAnimation { duration: Theme.fast } }
                border.width: cardFocus.activeFocus ? 2 : 1
                border.color: cardFocus.activeFocus ? Theme.primary : Theme.border

                // 앨범아트: 저장해 둔 그림 주소가 있으면 그림만 받는다 (보이는 카드만 만들어지므로 보이는 곡만 받음)
                Component.onCompleted: if (!modelData.manual) backend.loadArtFrom(modelData.song_id, modelData.image_url)
                Connections {
                    target: backend
                    function onArtReady(id) { if (id === card.modelData.song_id) art.source = "image://art/" + id }
                }

                // 키보드: Tab으로 와서 Enter·Space 담기, → 담을 버전 고르기
                Item {
                    id: cardFocus
                    anchors.fill: parent
                    activeFocusOnTab: true
                    Keys.onReturnPressed: lib.add(card.modelData)
                    Keys.onEnterPressed: lib.add(card.modelData)
                    Keys.onSpacePressed: lib.add(card.modelData)
                    Keys.onRightPressed: picker.openMenu()
                    Accessible.role: Accessible.Button
                    Accessible.name: card.modelData.title + ", " + picker.label + "으로 " + (card.setlistNo > 0 ? "가사 바꾸기" : "콘티에 담기")
                                     + (card.applied ? ", 지금 적용 중" : "")
                    Accessible.onPressAction: lib.add(card.modelData)
                }
                // 누르면 담기, 콘티로 끌어다 놓으면 놓은 자리에 담기 (버튼이 위에서 클릭을 받도록 아래에 둔다)
                SongDragArea {
                    id: cardArea
                    anchors.fill: parent
                    dragHost: lib.dragHost
                    payload: card.selected ? ({ kind: "preset", song: lib.songOf(card.modelData), preset: card.selected })
                                           : ({ kind: "song", song: lib.songOf(card.modelData) })
                    dragLabel: card.modelData.title + " · " + picker.label
                    onTapped: lib.add(card.modelData)
                }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 12
                    anchors.rightMargin: 12
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
                        visible: card.setlistNo > 0
                        implicitWidth: setlistLabel.implicitWidth + 14
                        implicitHeight: 22
                        radius: 11
                        color: card.applied ? Theme.surface : Theme.surface2
                        Text { id: setlistLabel; anchors.centerIn: parent; text: "콘티 " + card.setlistNo + "번"; color: Theme.text2; font.family: Theme.font; font.pixelSize: 11; font.weight: Font.Bold }
                    }
                    PresetPicker {
                        id: picker
                        objectName: "presetPicker"
                        song: lib.songOf(card.modelData)
                        presets: card.modelData.presets
                        melon: !card.modelData.manual
                    }
                }
            }
        }
    }
}
