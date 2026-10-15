import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import "."

Item {
    id: page

    property bool hasResults: false
    property bool searching: false
    property var results: []
    property string emptyText: ""
    property string errorText: ""     // 검색을 못 했을 때 원인 안내 ('결과 없음'과 구분)
    property string loadingId: ""     // 가사를 불러오는 중인 곡
    property int token: 0             // 오래된 검색 응답 무시용
    property var tour: null
    property string mode: "song"      // 검색 방식: "song"(제목·가수) / "lyric"(가사 구절)
    property string resultMode: "song" // 지금 보이는 결과의 검색 방식 (곡 검색이 비면 가사 검색 결과로 바뀐다)
    property bool fallback: false     // 곡 검색 결과가 없어서 가사 검색 결과를 대신 보여 주는 중
    property int total: 0             // 멜론이 알려 준 전체 건수
    property bool loadingMore: false
    property real bottomInset: 0      // 화면 아래에 떠 있는 표시('편집 중' 칩)가 가리는 높이
    property string moreError: ""
    // 저장한 곡 구성 수 (곡 번호 → 수). 결과 행에 '저장된 구성' 배지를 띄운다
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
            song_id: r.song_id, title: r.title, artist: r.artist, album: r.album,
            adult: r.adult === true, snippet: r.snippet || "" })
    }
    readonly property bool hasMore: results.length > 0 && results.length < total
    function countText(n) { return Number(n).toLocaleString(Qt.locale("ko_KR"), "f", 0) }

    function showHelp(opts) {
        tour.start([
            { target: searchBox, demo: searchDemo, title: "1. 노래 검색",
              body: "노래 제목이나 가수 이름을 입력하고 <b>Enter</b>(또는 <b>검색</b>)를 누르면 멜론에서 찾아와요.<br><br>"
                  + "제목이 기억나지 않으면 <b>가사</b>를 눌러 가사 한 구절로 찾을 수 있어요. "
                  + "멜론에 없는 곡은 아래 <b>가사 직접 입력</b>으로 가사를 붙여 넣어 만들 수 있어요." },
            { target: resultsArea, demo: resultsDemo, title: "2. 곡 고르기",
              body: "검색 결과에서 곡을 누르면 가사와 앨범아트를 불러와 <b>편집 화면</b>으로 넘어가요.<br><br>"
                  + "편집 화면에서 <b>구성 저장</b>을 해 둔 곡은 오른쪽에 <b>저장된 구성</b>이 보여요. "
                  + "누르면 그때 슬라이드 구성 그대로 열어요." },
            { target: null, title: "3. 다듬고 PPT 만들기",
              body: "편집 화면에서 가사를 슬라이드 단위로 나누고, 아래의 <b>PPT 생성</b>을 누르면 끝이에요. "
                  + "왼쪽 <b>곡 추가</b>로 여러 곡을 순서대로 한 PPT로 만들 수도 있어요.<br><br>"
                  + "편집 화면 곳곳의 <b>?</b> 버튼을 누르면 그 부분의 사용 방법을 볼 수 있어요." }
        ], opts)
    }

    // 검색창 복제본에 검색어를 한 글자씩 입력하고 검색을 누른다
    property Component searchDemo: Component {
        Demo {
            id: d
            readonly property string word: "노래 제목"
            property int typed: 0
            Rectangle { anchors.fill: parent; color: Theme.bg }
            Rectangle {
                anchors.fill: parent
                anchors.margins: page.tour.pad
                radius: 16
                color: Theme.surface
                border.width: 1.5
                border.color: Theme.focusBorder
                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 16
                    anchors.rightMargin: 6
                    spacing: 8
                    Icon { glyph: "search"; color: Theme.text3 }
                    Text {
                        Layout.fillWidth: true
                        leftPadding: 6
                        text: d.typed ? d.word.slice(0, d.typed) + "|" : "노래 제목 또는 가수 이름"
                        color: d.typed ? Theme.text : Theme.text3
                        font.family: Theme.font
                        font.pixelSize: 16
                    }
                    AppButton { id: demoSearchButton; text: "검색"; variant: "primary"; implicitHeight: 44 }
                }
            }
            onReset: { typed = 0; d.jumpTo(demoSearchButton, -2, 2.2) }
            script: {
                const steps = [[500, () => d.moveTo(searchBox, 0.4, 0.5)], [700, () => d.click()]]
                for (let i = 1; i <= word.length; i++) steps.push([i === 1 ? 400 : 140, () => d.typed++])
                steps.push([500, () => d.moveTo(demoSearchButton)], [750, () => d.click()])
                return steps
            }
        }
    }

    // 결과 목록 복제본에서 곡 하나를 누른다
    property Component resultsDemo: Component {
        Demo {
            id: d
            property int hover: -1
            property bool loading: false
            Rectangle { anchors.fill: parent; color: Theme.bg }
            Column {
                id: rows
                anchors.fill: parent
                anchors.margins: page.tour.pad
                spacing: 4
                Repeater {
                    model: 3
                    delegate: Rectangle {
                        id: row
                        required property int index
                        width: rows.width
                        height: 72
                        radius: Theme.radius
                        color: d.hover === index ? Theme.surface : Theme.surfaceClear
                        Behavior on color { ColorAnimation { duration: Theme.fast } }
                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 12
                            anchors.rightMargin: 14
                            spacing: 14
                            Rectangle { Layout.preferredWidth: 52; Layout.preferredHeight: 52; radius: 8; color: Theme.surface2 }
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 3
                                Text { Layout.fillWidth: true; text: "노래 제목 " + (row.index + 1); color: Theme.text; font.family: Theme.font; font.pixelSize: 15; font.weight: Font.DemiBold }
                                Text { Layout.fillWidth: true; text: "가수 · 앨범"; color: Theme.text3; font.family: Theme.font; font.pixelSize: 13 }
                            }
                            Icon {
                                id: demoArrow
                                glyph: d.loading && d.hover === row.index ? "loader" : "chevron-right"
                                color: Theme.text3
                                opacity: d.hover === row.index ? 1 : 0
                                RotationAnimation on rotation {
                                    running: d.loading && d.hover === row.index
                                    from: 0; to: 360; duration: 800; loops: Animation.Infinite
                                    onStopped: demoArrow.rotation = 0
                                }
                            }
                        }
                    }
                }
            }
            onReset: { hover = -1; loading = false; d.jumpTo(rows, 0.7, 0.9) }
            script: [
                [500, () => d.moveTo(rows.children[1], 0.35, 0.5)],
                [450, () => { d.hover = 1 }],
                [500, () => { d.click(); d.loading = true }]
            ]
        }
    }

    signal songClicked(var song)
    // 결과 행의 '저장된 구성' 배지 (또는 그 행에서 →)
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
        backend.searchPage(token, searchedText, resultMode, results.length + 1)
    }

    function setMode(m) {
        if (mode === m) return
        mode = m
        if (hasResults && input.text.trim()) doSearch()
    }

    Connections {
        target: backend
        function onPresetsChanged() { page.presetCounts = JSON.parse(backend.presetCounts()) }
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
            page.setResults(res.results)
            page.total = res.total === null || res.total === undefined ? res.results.length : res.total
            page.resultMode = res.mode
            page.fallback = res.fallback
            page.errorText = res.error ? res.error.message : ""
            page.emptyText = res.results.length || res.error ? ""
                : (page.mode === "lyric" ? "이 구절이 들어간 가사를 찾지 못했어요" : "검색 결과가 없어요")
        }
    }

    ColumnLayout {
        id: column
        width: Math.min(640, page.width - 48)
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.topMargin: page.hasResults ? 28 : page.height * 0.22
        spacing: 0
        Behavior on anchors.topMargin { NumberAnimation { duration: 450; easing.type: Easing.OutCubic } }

        // ── 로고 / 제목 ──
        Item {
            Layout.alignment: Qt.AlignHCenter
            Layout.preferredWidth: page.hasResults ? 0 : 64
            Layout.preferredHeight: page.hasResults ? 0 : 64
            Layout.bottomMargin: page.hasResults ? 0 : 16
            opacity: page.hasResults ? 0 : 1
            Behavior on Layout.preferredWidth { NumberAnimation { duration: 450; easing.type: Easing.OutCubic } }
            Behavior on Layout.preferredHeight { NumberAnimation { duration: 450; easing.type: Easing.OutCubic } }
            Behavior on Layout.bottomMargin { NumberAnimation { duration: 450; easing.type: Easing.OutCubic } }
            Behavior on opacity { NumberAnimation { duration: 300 } }
            // 앱 아이콘. SVG는 1024 칸 안에 824 크기 둥근 사각형이 있어(여백 100) 그만큼 크게 그려 사각형이 이 칸에 맞게 한다
            Image {
                anchors.centerIn: parent
                width: parent.width * 1024 / 824
                height: width
                source: assetsUrl + "/app-icon/icon.svg"
                sourceSize: Qt.size(160, 160)
                smooth: true
                mipmap: true
            }
        }

        Text {
            Layout.alignment: Qt.AlignHCenter
            text: "Lyrics Slide Creator"
            color: Theme.text
            font.family: Theme.font
            font.pixelSize: page.hasResults ? 20 : 28
            font.weight: Font.ExtraBold
            font.letterSpacing: -0.4
            Behavior on font.pixelSize { NumberAnimation { duration: 450; easing.type: Easing.OutCubic } }

            // 제목 가운데 정렬이 흐트러지지 않도록 레이아웃 밖에서 오른쪽에 붙인다
            HelpButton {
                label: "검색 화면"
                anchors.left: parent.right
                anchors.leftMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                onClicked: page.showHelp()
            }
        }

        Text {
            Layout.alignment: Qt.AlignHCenter
            Layout.topMargin: page.hasResults ? 0 : 6
            Layout.preferredHeight: page.hasResults ? 0 : implicitHeight
            text: "멜론에서 노래를 검색하고 가사 슬라이드를 만들어보세요"
            color: Theme.text3
            font.family: Theme.font
            font.pixelSize: 14
            opacity: page.hasResults ? 0 : 1
            clip: true
            Behavior on opacity { NumberAnimation { duration: 300 } }
            Behavior on Layout.preferredHeight { NumberAnimation { duration: 450; easing.type: Easing.OutCubic } }
        }

        // ── 검색창 ──
        Rectangle {
            id: searchBox
            Layout.fillWidth: true
            Layout.topMargin: page.hasResults ? 14 : 28
            Layout.preferredHeight: 58
            radius: 16
            color: Theme.surface
            border.width: 1.5
            border.color: input.activeFocus ? Theme.focusBorder : Theme.border
            Behavior on Layout.topMargin { NumberAnimation { duration: 450; easing.type: Easing.OutCubic } }
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
                anchors.leftMargin: 16
                anchors.rightMargin: 6
                spacing: 8
                Icon { glyph: "search"; color: Theme.text3 }
                TextField {
                    id: input
                    Layout.fillWidth: true
                    placeholderText: page.mode === "lyric" ? "가사 한 구절" : "노래 제목 또는 가수 이름"
                    placeholderTextColor: Theme.text3
                    color: Theme.text
                    font.family: Theme.font
                    font.pixelSize: 16
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
                    implicitHeight: 34
                    radius: 10
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
                                width: label.implicitWidth + 20
                                height: 28
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
                                    font.pixelSize: 13
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
                    implicitHeight: 44
                    enabled: !page.searching
                    onClicked: page.doSearch()
                }
            }
        }

        // 멜론에 없는 곡(CCM·찬송가·자작곡)이나 연결이 안 될 때: 빈 편집 화면으로
        AppButton {
            id: manualButton
            Layout.alignment: Qt.AlignRight
            Layout.topMargin: 6
            text: "가사 직접 입력"
            glyph: "plus"
            variant: "ghost"
            size: "small"
            onClicked: page.manualRequested({ title: "", artist: "" })
            AppToolTip { visible: manualButton.hovered; text: "멜론에 없는 곡은 가사를 직접 붙여 넣어 만들 수 있어요" }
        }

        // ── 결과 ──
        Item {
            id: resultsArea
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.topMargin: 16

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
                bottomMargin: 40 + page.bottomInset
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
                    if (currentItem) page.songClicked(currentItem.modelData)
                }
                Keys.onReturnPressed: openCurrent()
                Keys.onEnterPressed: openCurrent()
                Keys.onSpacePressed: openCurrent()
                // →: 저장된 구성이 있으면 고르는 창을 연다
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
                    text: !page.results.length ? "" : (page.resultMode === "lyric"
                           ? (page.fallback ? "곡 제목에는 없어서 가사에서 찾았어요.\n" : "")
                             + "가사에 이 구절이 있는 노래 · "
                           : "")
                          + "총 " + page.countText(page.total) + "곡 중 " + page.countText(page.results.length) + "곡"
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
                    readonly property var modelData: ({ song_id: song_id, title: title, artist: artist,
                                                        album: album, adult: adult, snippet: snippet })
                    readonly property bool loading: page.loadingId === song_id
                    readonly property int presetCount: page.presetCounts[song_id] || 0
                    readonly property bool focused: ListView.isCurrentItem && list.activeFocus

                    width: ListView.view.width
                    height: modelData.snippet ? 100 : 72
                    radius: Theme.radius
                    readonly property bool hovered: hover.containsMouse || presetBadge.hovered
                    color: hovered || focused ? Theme.surface : Theme.surfaceClear
                    border.width: focused ? 2 : 0
                    border.color: Theme.primary
                    Behavior on color { ColorAnimation { duration: Theme.fast } }
                    Accessible.role: Accessible.Button
                    Accessible.name: [title, artist, album].filter(Boolean).join(", ")
                                     + (presetCount ? ", 저장된 구성 " + presetCount + "개 (오른쪽 화살표로 열기)" : "")
                    Accessible.onPressAction: page.songClicked(modelData)

                    // 나타날 때 아래에서 살짝 올라온다
                    opacity: 0
                    transform: Translate { id: shift; y: 8 }
                    Component.onCompleted: {
                        appear.start()
                        backend.loadArt(modelData.song_id)
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
                        anchors.leftMargin: 12
                        anchors.rightMargin: 14
                        spacing: 14
                        RoundedImage {
                            id: art
                            Layout.preferredWidth: 52
                            Layout.preferredHeight: 52
                            radius: 8
                            placeholder: Theme.skeleton
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
                                    font.pixelSize: 15
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
                                text: [row.modelData.artist, row.modelData.album].filter(Boolean).join(" · ")
                                textFormat: Text.PlainText
                                color: Theme.text3
                                font.family: Theme.font
                                font.pixelSize: 13
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
                        // 저장한 구성이 있는 곡: 누르면 고르는 창 (행을 누르면 지금처럼 멜론 가사로 연다)
                        AppButton {
                            id: presetBadge
                            visible: row.presetCount > 0
                            text: "저장된 구성 " + row.presetCount
                            variant: "primary"
                            size: "small"
                            focusPolicy: Qt.NoFocus      // 키보드는 목록에서 →
                            onClicked: page.presetsRequested(row.modelData)
                            AppToolTip { visible: presetBadge.hovered; delay: 400; text: "예전에 저장한 슬라이드 구성 그대로 열어요" }
                        }
                        Icon {
                            id: arrow
                            glyph: row.loading ? "loader" : "chevron-right"
                            color: Theme.text3
                            opacity: row.loading || row.hovered || row.focused ? 1 : 0
                            Behavior on opacity { NumberAnimation { duration: Theme.fast } }
                            RotationAnimation on rotation {
                                running: row.loading
                                from: 0; to: 360; duration: 800; loops: Animation.Infinite
                                onStopped: arrow.rotation = 0
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
                        onClicked: page.songClicked(row.modelData)
                    }
                }
            }
        }
    }
}
