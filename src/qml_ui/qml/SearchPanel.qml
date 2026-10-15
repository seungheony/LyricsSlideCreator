import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import "."

// 곡 찾기 서랍(SongDrawer)의 멜론 탭: 검색·결과·더 보기·가사 검색 대체·직접 입력 곡 결과·프리셋 배지.
// 결과 행을 누르면 songClicked로 알리고, 담는 일은 Main·EditorPage가 한다 (행 오른쪽에 ＋ / 받는 중 / 담음 / 콘티에 있음)
Item {
    id: page

    property bool hasResults: false
    property bool searching: false
    property var results: []
    property string emptyText: ""
    property string errorText: ""     // 검색을 못 했을 때 원인 안내 ('결과 없음'과 구분)
    // 콘티 상태 (행 오른쪽 표시): 콘티의 곡 / 가사를 받는 중인 곡 / 이번에 서랍을 연 뒤 담은 곡 (모두 song_id)
    property var setlist: []
    property var loadingIds: []
    property var addedIds: []
    property int token: 0             // 오래된 검색 응답 무시용
    property string mode: "song"      // 검색 방식: "song"(제목·가수) / "lyric"(가사 구절)
    property string resultMode: "song" // 지금 보이는 결과의 검색 방식 (곡 검색이 비면 가사 검색 결과로 바뀐다)
    property bool fallback: false     // 곡 검색 결과가 없어서 가사 검색 결과를 대신 보여 주는 중
    property int total: 0             // 멜론이 알려 준 전체 건수
    property bool loadingMore: false
    property string moreError: ""
    property string melonError: ""    // 직접 입력한 곡 결과는 있는데 멜론 검색만 실패했을 때 (목록 위에 알림)
    // 저장한 프리셋 수 (곡 번호 → 수). 결과 행에 '프리셋 N' 배지를 띄운다
    property var presetCounts: JSON.parse(backend.presetCounts())
    // 목록은 ListModel에 이어 붙인다 (배열을 통째로 바꾸면 다음 쪽을 붙일 때 스크롤이 맨 위로 돌아간다)
    ListModel { id: resultModel }
    function setResults(items) {
        resultModel.clear()
        appendResults(items)
        results = items
    }
    function appendResults(items) {
        for (const r of items) resultModel.append({
            song_id: r.song_id, title: r.title, artist: r.artist, album: r.album || "",
            adult: r.adult === true, snippet: r.snippet || "", manual: r.manual === true })
    }
    // 직접 입력한 곡의 프리셋 중 검색어에 맞는 곡 (멜론 결과보다 위에 둔다, results 앞쪽 localCount개)
    property int localCount: 0
    function manualMatches(keyword, modes) {
        const seen = {}
        const out = []
        modes.forEach(m => JSON.parse(backend.searchManualPresets(keyword, m)).forEach(r => {
            if (!seen[r.song_id]) { seen[r.song_id] = true; out.push(r) }
        }))
        return out
    }
    readonly property int melonCount: results.length - localCount
    readonly property bool hasMore: melonCount > 0 && melonCount < total
    function countText(n) { return Number(n).toLocaleString(Qt.locale("ko_KR"), "f", 0) }

    signal songClicked(var song)
    // 결과 행의 '프리셋 N' 배지 (또는 그 행에서 →, 직접 입력한 곡은 행을 눌러도)
    signal presetsRequested(var song)
    // 멜론 없이 가사를 직접 입력해서 연다. info: { title, artist }
    signal manualRequested(var info)

    function focusSearch() { input.forceActiveFocus(); input.selectAll() }
    // 검색칸에서 ↓: 결과 목록의 첫 곡으로. 목록이 없거나 검색 중이면 하지 않는다
    function focusList() {
        if (searching || !resultModel.count) return false
        if (list.currentIndex < 0) list.currentIndex = 0
        list.forceActiveFocus(Qt.TabFocusReason)
        return true
    }

    property string searchedKeyword: ""   // 마지막으로 검색한 검색어 (검색 중 같은 검색어 중복 요청 방지)

    function doSearch() {
        Qt.inputMethod.commit()    // 한글 조합 중인 글자를 확정한 뒤 읽는다
        const keyword = input.text.trim()
        if (!keyword) return
        const key = mode + ":" + keyword
        if (searching && key === searchedKeyword) return
        searchedKeyword = key
        searchedText = keyword
        token++
        hasResults = true
        searching = true
        setResults([])
        total = 0
        fallback = false
        loadingMore = false
        moreError = ""
        emptyText = ""
        errorText = ""
        melonError = ""
        localCount = 0
        resultMode = mode
        backend.searchPage(token, keyword, mode, 1)
    }

    property string searchedText: ""      // 마지막으로 검색한 검색어 (다음 쪽을 받을 때 쓴다)

    // 다음 쪽을 받아 목록 끝에 붙인다
    function loadMore() {
        if (loadingMore || searching || !hasMore) return
        loadingMore = true
        moreError = ""
        token++
        backend.searchPage(token, searchedText, resultMode, melonCount + 1)
    }

    function setMode(m) {
        if (mode === m) return
        mode = m
        if (hasResults && input.text.trim()) doSearch()
    }

    Connections {
        target: backend
        function onPresetsChanged() {
            page.presetCounts = JSON.parse(backend.presetCounts())
            // 프리셋을 모두 지운 직접 입력 곡은 결과에서 뺀다
            for (let i = page.localCount - 1; i >= 0; i--) {
                if (!page.presetCounts[page.results[i].song_id]) {
                    resultModel.remove(i)
                    page.results = page.results.slice(0, i).concat(page.results.slice(i + 1))
                    page.localCount--
                }
            }
        }
        function onSearchFinished(t, json) {
            if (t !== page.token) return
            const res = JSON.parse(json)
            if (res.start > 1) {                       // 다음 쪽
                page.loadingMore = false
                if (res.error) { page.moreError = "더 불러오지 못했어요. 다시 시도해 주세요."; return }
                const seen = {}
                page.results.forEach(r => { seen[r.song_id] = true })
                const fresh = res.results.filter(r => !seen[r.song_id])
                if (!fresh.length) page.total = page.results.length   // 더 받을 게 없다
                else { page.appendResults(fresh); page.results = page.results.concat(fresh) }
                return
            }
            page.searching = false
            // 직접 입력한 곡이 맨 위 (곡 검색이 가사 검색으로 바뀌었으면 둘 다로 찾는다)
            const locals = page.manualMatches(page.searchedText, res.fallback ? ["song", "lyric"] : [res.mode])
            page.localCount = locals.length
            page.setResults(locals.concat(res.results))
            page.total = res.total === null || res.total === undefined ? res.results.length : res.total
            page.resultMode = res.mode
            page.fallback = res.fallback
            const failed = res.error ? res.error.message : ""
            page.errorText = locals.length ? "" : failed
            page.melonError = locals.length && failed ? failed.split("\n")[0] : ""
            page.emptyText = page.results.length || res.error ? ""
                : (page.mode === "lyric" ? "이 구절이 들어간 가사를 찾지 못했어요" : "검색 결과가 없어요")
        }
    }

    ColumnLayout {
        id: column
        anchors.fill: parent
        anchors.leftMargin: 20
        anchors.rightMargin: 20
        spacing: 0

        // ── 검색창 ──
        Rectangle {
            id: searchBox
            Layout.fillWidth: true
            Layout.topMargin: 4
            Layout.preferredHeight: 48
            radius: 14
            color: Theme.surface
            border.width: 1.5
            border.color: input.activeFocus ? Theme.focusBorder : Theme.border
            Behavior on border.color { ColorAnimation { duration: Theme.fast } }

            // 포커스 링
            Rectangle {
                anchors.fill: parent
                anchors.margins: -4
                radius: 20
                color: "transparent"
                border.width: 4
                border.color: Theme.primarySoft
                visible: input.activeFocus
                z: -1
            }

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 12
                anchors.rightMargin: 6
                spacing: 6
                Icon { glyph: "search"; color: Theme.text3 }
                TextField {
                    id: input
                    Layout.fillWidth: true
                    placeholderText: page.mode === "lyric" ? "가사 한 구절" : "노래 제목 또는 가수 이름"
                    placeholderTextColor: Theme.text3
                    color: Theme.text
                    font.family: Theme.font
                    font.pixelSize: 15
                    background: null
                    selectByMouse: true
                    focus: true
                    onAccepted: page.doSearch()
                    Keys.onDownPressed: (event) => { event.accepted = page.focusList() }
                    Accessible.name: "검색어"
                    ContextMenu.menu: AppTextMenu { editor: input }
                }
                // 검색 방식 전환
                Rectangle {
                    id: modeSwitch
                    implicitWidth: modeRow.implicitWidth + 6
                    implicitHeight: 32
                    radius: 9
                    color: Theme.surface2
                    Row {
                        id: modeRow
                        anchors.centerIn: parent
                        spacing: 2
                        Repeater {
                            model: [{ key: "song", label: "제목·가수" }, { key: "lyric", label: "가사" }]
                            delegate: Rectangle {
                                required property var modelData
                                readonly property bool on: page.mode === modelData.key
                                width: label.implicitWidth + 14
                                height: 26
                                radius: 8
                                color: on ? Theme.surface : "transparent"
                                border.width: on ? 1 : 0
                                border.color: Theme.border
                                Accessible.role: Accessible.RadioButton
                                Accessible.name: modelData.label
                                Accessible.checked: on
                                Accessible.onPressAction: page.setMode(modelData.key)
                                // Tab으로 닿고, Space·Enter로 고른다 (포커스가 있으면 테두리)
                                activeFocusOnTab: true
                                Keys.onSpacePressed: page.setMode(modelData.key)
                                Keys.onReturnPressed: page.setMode(modelData.key)
                                Keys.onEnterPressed: page.setMode(modelData.key)
                                Rectangle {
                                    anchors.fill: parent
                                    radius: parent.radius
                                    color: "transparent"
                                    border.width: 2
                                    border.color: Theme.primary
                                    visible: parent.activeFocus
                                }
                                Text {
                                    id: label
                                    anchors.centerIn: parent
                                    text: parent.modelData.label
                                    color: parent.on ? Theme.text : Theme.text3
                                    font.family: Theme.font
                                    font.pixelSize: 12
                                    font.weight: parent.on ? Font.DemiBold : Font.Normal
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: { page.setMode(parent.modelData.key); input.forceActiveFocus() }
                                }
                            }
                        }
                    }
                }
                AppButton {
                    text: "검색"
                    variant: "primary"
                    size: "small"
                    implicitHeight: 34
                    enabled: !page.searching
                    onClicked: page.doSearch()
                }
            }
        }

        // ── 결과 ──
        Item {
            id: resultsArea
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.topMargin: 12

            // 스켈레톤
            Column {
                anchors.fill: parent
                visible: page.searching
                spacing: 4
                Repeater {
                    model: 6
                    Row {
                        spacing: 14
                        leftPadding: 12
                        topPadding: 10
                        bottomPadding: 10
                        Rectangle { width: 52; height: 52; radius: 8; color: Theme.skeleton }
                        Column {
                            spacing: 8
                            anchors.verticalCenter: parent.verticalCenter
                            Rectangle { width: 180 + (index * 37) % 90; height: 12; radius: 6; color: Theme.skeleton }
                            Rectangle { width: 100 + (index * 23) % 60; height: 12; radius: 6; color: Theme.skeleton }
                        }
                        SequentialAnimation on opacity {
                            running: page.searching
                            loops: Animation.Infinite
                            NumberAnimation { to: 0.45; duration: 600; easing.type: Easing.InOutSine }
                            NumberAnimation { to: 1; duration: 600; easing.type: Easing.InOutSine }
                        }
                    }
                }
            }

            // 검색하기 전
            Column {
                anchors.horizontalCenter: parent.horizontalCenter
                y: 40
                width: parent.width - 32
                spacing: 10
                visible: !page.hasResults
                Icon { anchors.horizontalCenter: parent.horizontalCenter; glyph: "search"; size: 32; color: Theme.text3; opacity: 0.6 }
                Text {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    text: "노래 제목이나 가수 이름으로 멜론에서 찾아요.\n제목이 기억나지 않으면 '가사'로 한 구절을 검색해 보세요."
                    color: Theme.text3
                    font.family: Theme.font
                    font.pixelSize: 13
                    lineHeight: 1.4
                    wrapMode: Text.Wrap
                }
            }

            // 결과 없음
            Column {
                anchors.horizontalCenter: parent.horizontalCenter
                y: 48
                spacing: 10
                visible: !page.searching && page.emptyText !== ""
                Icon { anchors.horizontalCenter: parent.horizontalCenter; glyph: "music"; size: 36; color: Theme.text3; opacity: 0.6 }
                Text { anchors.horizontalCenter: parent.horizontalCenter; text: page.emptyText; color: Theme.text3; font.family: Theme.font; font.pixelSize: 14 }
                AppButton {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "직접 입력으로 열기"
                    onClicked: page.manualRequested({ title: page.mode === "song" ? page.searchedText : "", artist: "" })
                }
            }

            // 검색 실패 (연결·응답·화면 변경)
            Column {
                anchors.horizontalCenter: parent.horizontalCenter
                y: 48
                spacing: 14
                visible: !page.searching && page.errorText !== ""
                Icon { anchors.horizontalCenter: parent.horizontalCenter; glyph: "music"; size: 36; color: Theme.warning; opacity: 0.8 }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    horizontalAlignment: Text.AlignHCenter
                    text: page.errorText
                    textFormat: Text.PlainText
                    color: Theme.text2
                    font.family: Theme.font
                    font.pixelSize: 14
                    lineHeight: 1.4
                }
                Row {
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: 8
                    AppButton { text: "직접 입력으로 열기"; onClicked: page.manualRequested({ title: page.resultMode === "song" ? page.searchedText : "", artist: "" }) }
                    AppButton { text: "다시 시도"; variant: "primary"; onClicked: page.doSearch() }
                }
            }

            ListView {
                id: list
                objectName: "resultList"
                anchors.fill: parent
                visible: !page.searching
                model: resultModel
                spacing: 4
                clip: true
                bottomMargin: 24
                boundsBehavior: Flickable.StopAtBounds
                ScrollBar.vertical: ScrollBar {}

                // 키보드: 검색칸 ↓ 또는 Tab으로 들어와 ↑↓로 고르고 Enter로 연다. 첫 곡에서 ↑는 검색칸으로
                currentIndex: -1
                activeFocusOnTab: count > 0
                keyNavigationEnabled: true
                onActiveFocusChanged: if (activeFocus && currentIndex < 0 && count > 0) currentIndex = 0
                Keys.onUpPressed: (event) => {
                    if (currentIndex > 0) { event.accepted = false; return }
                    input.forceActiveFocus(Qt.BacktabFocusReason)
                    event.accepted = true
                }
                function openCurrent() {
                    if (currentItem) currentItem.open()
                }
                Keys.onReturnPressed: openCurrent()
                Keys.onEnterPressed: openCurrent()
                Keys.onSpacePressed: openCurrent()
                // →: 프리셋이 있으면 고르는 창을 연다
                Keys.onRightPressed: (event) => {
                    event.accepted = !!(currentItem && currentItem.presetCount)
                    if (event.accepted) page.presetsRequested(currentItem.modelData)
                }

                // 끝 근처까지 내려오면 다음 쪽을 자동으로 받는다 (받는 중이면 loadMore가 막고, 실패하면 '다시 시도'를 누를 때까지 멈춘다)
                function checkEnd() {
                    if (page.moreError === "" && contentHeight > 0 && contentY + height > contentHeight - 400) page.loadMore()
                }
                onContentYChanged: checkEnd()
                onContentHeightChanged: checkEnd()

                header: Text {
                    width: list.width
                    bottomPadding: 10
                    wrapMode: Text.Wrap
                    textFormat: Text.PlainText
                    leftPadding: 12
                    color: Theme.text3
                    font.family: Theme.font
                    font.pixelSize: 13
                    text: !page.results.length ? "" : (page.melonError ? "멜론 검색은 하지 못했어요. " + page.melonError + "\n" : "")
                          + (page.resultMode === "lyric"
                           ? (page.fallback ? "곡 제목에는 없어서 가사에서 찾았어요.\n" : "")
                             + "가사에 이 구절이 있는 노래 · "
                           : "")
                          + (page.localCount ? "직접 입력한 곡 " + page.localCount + "곡" + (page.melonCount || page.total ? " · " : "") : "")
                          + (page.melonCount || page.total
                             ? "멜론 총 " + page.countText(page.total) + "곡 중 " + page.countText(page.melonCount) + "곡" : "")
                }

                footer: Item {
                    width: list.width
                    height: page.hasMore ? 64 : 0
                    visible: page.hasMore
                    ColumnLayout {
                        anchors.centerIn: parent
                        spacing: 6
                        Text {
                            visible: page.moreError !== ""
                            Layout.alignment: Qt.AlignHCenter
                            text: page.moreError
                            color: Theme.warning
                            font.family: Theme.font
                            font.pixelSize: 13
                        }
                        AppButton {
                            visible: page.moreError !== ""
                            Layout.alignment: Qt.AlignHCenter
                            text: "다시 시도"
                            onClicked: page.loadMore()
                        }
                        Icon {
                            visible: page.loadingMore && page.moreError === ""
                            Layout.alignment: Qt.AlignHCenter
                            glyph: "loader"
                            size: 20
                            color: Theme.text3
                            RotationAnimator on rotation { running: page.loadingMore; from: 0; to: 360; duration: 900; loops: Animation.Infinite }
                        }
                    }
                }

                delegate: Rectangle {
                    id: row
                    required property int index
                    required property string song_id
                    required property string title
                    required property string artist
                    required property string album
                    required property bool adult
                    required property string snippet
                    required property bool manual
                    readonly property var modelData: ({ song_id: song_id, title: title, artist: artist,
                                                        album: album, adult: adult, snippet: snippet, manual: manual })
                    // 직접 입력한 곡은 멜론 가사가 없으므로 프리셋을 고르는 창을 연다
                    function open() {
                        if (manual) page.presetsRequested(modelData)
                        else page.songClicked(modelData)
                    }
                    // 콘티 상태: "loading"(가사 받는 중) / "added"(이번에 담음) / "inSetlist"(전에 담은 곡) / ""(＋)
                    readonly property string status: page.loadingIds.indexOf(song_id) >= 0 ? "loading"
                        : page.addedIds.indexOf(song_id) >= 0 ? "added"
                        : page.setlist.indexOf(song_id) >= 0 ? "inSetlist" : ""
                    readonly property int presetCount: page.presetCounts[song_id] || 0
                    readonly property bool focused: ListView.isCurrentItem && list.activeFocus

                    width: ListView.view.width
                    height: modelData.snippet ? 92 : 60
                    radius: Theme.radiusSm
                    readonly property bool hovered: hover.containsMouse || presetBadge.hovered || addButton.hovered
                    color: status === "added" || status === "loading" ? Theme.primarySoft
                         : hovered || focused ? Theme.surface2 : Theme.surface2Clear
                    border.width: focused ? 2 : 0
                    border.color: Theme.primary
                    Behavior on color { ColorAnimation { duration: Theme.fast } }
                    Accessible.role: Accessible.Button
                    Accessible.name: [title, artist, album].filter(Boolean).join(", ")
                                     + (manual ? ", 직접 입력한 곡, 프리셋 " + presetCount + "개"
                                        : presetCount ? ", 프리셋 " + presetCount + "개 (오른쪽 화살표로 열기)" : "")
                                     + (status === "loading" ? ", 가사 받는 중" : status === "added" ? ", 담음"
                                        : status === "inSetlist" ? ", 콘티에 있음" : "")
                    Accessible.onPressAction: open()

                    // 나타날 때 아래에서 살짝 올라온다
                    opacity: 0
                    transform: Translate { id: shift; y: 8 }
                    Component.onCompleted: {
                        appear.start()
                        if (!manual) backend.loadArt(modelData.song_id)
                    }
                    ParallelAnimation {
                        id: appear
                        SequentialAnimation {
                            PauseAnimation { duration: Math.max(0, Math.min(row.index, 8)) * 35 }
                            ParallelAnimation {
                                NumberAnimation { target: row; property: "opacity"; to: 1; duration: 350; easing.type: Easing.OutCubic }
                                NumberAnimation { target: shift; property: "y"; to: 0; duration: 350; easing.type: Easing.OutCubic }
                            }
                        }
                    }

                    Connections {
                        target: backend
                        function onArtReady(id) {
                            if (id === row.modelData.song_id) art.source = "image://art/" + id
                        }
                    }

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 8
                        anchors.rightMargin: 8
                        spacing: 12
                        RoundedImage {
                            id: art
                            Layout.preferredWidth: 44
                            Layout.preferredHeight: 44
                            radius: 8
                            placeholder: row.manual ? Theme.surface2 : Theme.skeleton
                            Icon { anchors.centerIn: parent; visible: row.manual; glyph: "music"; size: 22; color: Theme.text3 }
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 3
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 6
                                Text {
                                    Layout.fillWidth: true
                                    text: row.modelData.title
                                    textFormat: Text.PlainText
                                    color: Theme.text
                                    font.family: Theme.font
                                    font.pixelSize: 14
                                    font.weight: Font.DemiBold
                                    elide: Text.ElideRight
                                }
                                // 19금: 멜론이 성인 인증한 사용자에게만 가사를 보여 줘서 가져올 수 없다
                                Rectangle {
                                    visible: row.modelData.adult === true
                                    implicitWidth: adultLabel.implicitWidth + 10
                                    implicitHeight: 18
                                    radius: 4
                                    color: Theme.warningSoft
                                    Text {
                                        id: adultLabel
                                        anchors.centerIn: parent
                                        text: "19"
                                        color: Theme.warning
                                        font.family: Theme.font
                                        font.pixelSize: 11
                                        font.weight: Font.Bold
                                    }
                                }
                            }
                            Text {
                                Layout.fillWidth: true
                                text: [row.manual ? "직접 입력" : "", row.modelData.artist, row.modelData.album].filter(Boolean).join(" · ")
                                textFormat: Text.PlainText
                                color: Theme.text3
                                font.family: Theme.font
                                font.pixelSize: 12
                                elide: Text.ElideRight
                            }
                            // 가사 검색: 일치한 가사 일부 (일치한 구절은 굵게)
                            Text {
                                visible: !!row.modelData.snippet
                                Layout.fillWidth: true
                                text: row.modelData.snippet || ""
                                textFormat: Text.StyledText
                                color: Theme.text2
                                font.family: Theme.font
                                font.pixelSize: 13
                                wrapMode: Text.Wrap
                                maximumLineCount: 2
                                elide: Text.ElideRight
                            }
                        }
                        // 프리셋이 있는 곡: 누르면 고르는 창 (멜론 곡은 행을 누르면 지금처럼 멜론 가사로 연다)
                        AppButton {
                            id: presetBadge
                            visible: row.presetCount > 0
                            glyph: "bookmark"
                            text: "프리셋 " + row.presetCount
                            variant: "primary"
                            size: "small"
                            focusPolicy: Qt.NoFocus      // 키보드는 목록에서 →
                            onClicked: page.presetsRequested(row.modelData)
                            AppToolTip { visible: presetBadge.hovered; delay: 400; text: "예전에 저장한 슬라이드 그대로 열어요" }
                        }
                        // 콘티 상태: ＋(누르면 담음) / 받는 중 / 담음 / 콘티에 있음
                        Item {
                            Layout.preferredWidth: row.status === "" ? 36 : statusText.implicitWidth + (row.status === "inSetlist" ? 0 : 18)
                            Layout.preferredHeight: 36
                            AppButton {
                                id: addButton
                                anchors.centerIn: parent
                                visible: row.status === ""
                                glyph: "plus"
                                variant: "ghost"
                                focusPolicy: Qt.NoFocus      // 키보드는 목록에서 Enter
                                implicitHeight: 36
                                onClicked: row.open()
                                Accessible.name: "'" + row.title + "' 콘티에 담기"
                                background: Rectangle {
                                    radius: 18
                                    color: addButton.hovered ? Theme.surface2 : Theme.surface
                                    border.width: 1
                                    border.color: addButton.hovered ? Theme.primary : Theme.border
                                }
                                AppToolTip { visible: addButton.hovered; delay: 400; text: row.manual ? "프리셋을 골라 콘티에 담아요" : "콘티에 담아요" }
                            }
                            Row {
                                id: statusRow
                                anchors.centerIn: parent
                                visible: row.status !== ""
                                spacing: 4
                                Icon {
                                    id: statusIcon
                                    visible: row.status !== "inSetlist"
                                    anchors.verticalCenter: parent.verticalCenter
                                    glyph: row.status === "loading" ? "loader" : "check"
                                    size: 14
                                    color: Theme.primaryText
                                    RotationAnimation on rotation {
                                        running: row.status === "loading"
                                        from: 0; to: 360; duration: 800; loops: Animation.Infinite
                                        onStopped: statusIcon.rotation = 0
                                    }
                                }
                                Text {
                                    id: statusText
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: row.status === "loading" ? "받는 중" : row.status === "added" ? "담음" : "콘티에 있음"
                                    color: row.status === "inSetlist" ? Theme.text3 : Theme.primaryText
                                    font.family: Theme.font
                                    font.pixelSize: 12
                                    font.weight: row.status === "inSetlist" ? Font.Normal : Font.Bold
                                }
                            }
                        }
                    }

                    // 행 전체를 누르는 영역. 배지 버튼이 위에서 클릭을 받도록 아래에 둔다
                    MouseArea {
                        id: hover
                        z: -1
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: row.open()
                    }
                }
            }
        }
    }
}
