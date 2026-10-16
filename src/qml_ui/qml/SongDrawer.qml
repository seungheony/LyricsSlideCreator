import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import "."

// 곡 찾기 서랍: 편집 화면의 '곡 추가'(⌘K/Ctrl+K)로 콘티 패널 오른쪽에서 열려 편집 영역을 덮는다.
// 멜론(SearchPanel) | 보관함(PresetLibrary) | 직접 입력(ManualForm) 탭에서 곡을 연달아 담는다.
// 서랍이 열려 있는 동안 담은 곡은 콘티에 쌓이기만 하고, 닫을 때 이번에 처음 담은 곡을 연다 (EditorPage.closeDrawer).
// 담는 일은 받는 쪽(Main·EditorPage)이 한다:
//   songClicked(song): 멜론 결과 행 / presetChosen(song, preset): 보관함의 ＋·'이걸로 바꾸기'
//   manualSubmitted(info, text): 직접 입력의 '콘티에 담기' (보낸 뒤 입력칸을 비운다)
// show(tab, opts): 탭을 바꾸고 포커스. opts.filterSong: 보관함을 그 곡만, opts.manual: 직접 입력 칸 미리 채우기(ManualForm.prefill)
Rectangle {
    id: drawer

    property bool opened: false
    property bool emptySetlist: false     // 콘티가 비었다 (머리말을 '어떤 곡으로 시작할까요?'로)
    property var setlist: []
    property var appliedTexts: ({})   // 콘티 곡의 지금 가사 (저장한 곡 탭에서 같은 프리셋의 '이걸로 바꾸기'를 끔)
    property var loadingIds: []
    property var addedIds: []             // 이번에 서랍을 연 뒤 담은 곡
    property string currentId: ""         // 편집기에 열린 곡 (저장한 곡 탭 맨 위에 '편집 중')
    property var tour: null
    property string tab: "melon"          // "melon" | "library" | "manual"
    property alias search: searchPanel
    property alias library: library
    property alias manual: manualForm

    signal closeRequested()
    signal songClicked(var song)
    signal presetChosen(var song, var preset)
    signal manualSubmitted(var info, string text)

    function focusSearch() { searchPanel.focusSearch() }

    function show(key, opts) {
        opts = opts || {}
        tab = key || "melon"
        if (tab === "library") {
            library.filterSong = opts.filterSong || ""
            library.reset()
            library.refresh()
            // 그 곡의 프리셋이 하나도 없으면 전체를 보인다
            if (library.filterSong && !library.songs.length) { library.filterSong = ""; library.refresh() }
        } else if (tab === "manual" && opts.manual) {
            manualForm.prefill(opts.manual)
        }
        Qt.callLater(focusTab)
    }

    function focusTab() {
        if (!opened) return
        if (tab === "melon") searchPanel.focusSearch()
        else if (tab === "library") { if (library.library && library.totalCount) library.focusFilter(); else drawer.forceActiveFocus() }
        else manualForm.focusFirst()
    }

    // Esc: 서랍 안에서 먼저 처리할 것이 있으면 처리하고 true (보관함의 이름 고치기·삭제 확인 취소)
    function handleEscape() {
        if (tab === "library" && (library.renamingId || library.deletingId)) {
            library.renamingId = ""
            library.deletingId = ""
            drawer.forceActiveFocus()
            return true
        }
        return false
    }

    Connections {
        target: backend
        // 프리셋을 저장·삭제하면 (⌘S는 서랍이 열려 있어도 된다) 보관함을 다시 그린다
        function onPresetsChanged() { if (drawer.tab === "library") library.refresh() }
    }

    color: Theme.surface
    visible: opacity > 0
    opacity: opened ? 1 : 0
    enabled: opened
    transform: Translate { x: drawer.opened ? 0 : -16; Behavior on x { NumberAnimation { duration: Theme.normal; easing.type: Easing.OutCubic } } }
    Behavior on opacity { NumberAnimation { duration: Theme.normal; easing.type: Easing.OutCubic } }

    // 아래(편집 영역)로 클릭·휠이 새지 않게 막는다
    MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons; onWheel: (wheel) => { wheel.accepted = true } }

    // 오른쪽 그림자 대신 경계선
    Rectangle { anchors.right: parent.right; width: 1; height: parent.height; color: Theme.border }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        // ── 머리말 ──
        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: 20
            Layout.rightMargin: 14
            Layout.topMargin: 16
            spacing: 8
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2
                RowLayout {
                    spacing: 4
                    Text {
                        text: drawer.emptySetlist ? "어떤 곡으로 시작할까요?" : "곡 추가"
                        color: Theme.text
                        font.family: Theme.font
                        font.pixelSize: drawer.emptySetlist ? 19 : 17
                        font.weight: Font.Bold
                    }
                    HelpButton { objectName: "drawerHelpButton"; label: "곡 추가"; onClicked: drawer.showHelp() }
                }
                Text {
                    Layout.fillWidth: true
                    text: drawer.emptySetlist ? "멜론에서 찾거나, 저장한 프리셋을 담거나, 가사를 직접 입력해요"
                                              : "여러 곡을 연달아 담을 수 있어요"
                    color: Theme.text3
                    font.family: Theme.font
                    font.pixelSize: 12
                    elide: Text.ElideRight
                }
            }
            AppButton {
                id: closeButton
                Layout.alignment: Qt.AlignTop
                glyph: "x"
                variant: "ghost"
                size: "small"
                onClicked: drawer.closeRequested()
                Accessible.name: "곡 추가 닫기"
                AppToolTip { visible: closeButton.hovered; delay: 600; text: "닫기 (Esc)" }
            }
        }

        // ── 탭: 멜론에서 찾기 | 직접 입력 | 저장한 곡 ── (설명이 붙은 카드 탭: 탭마다 하는 일을 한 줄로 알린다)
        RowLayout {
            id: tabBar
            readonly property var tabs: [
                { key: "melon", label: "멜론에서 찾기", sub: "제목·가수·가사로 찾아요", glyph: "search" },
                { key: "manual", label: "직접 입력", sub: "멜론에 없는 곡의 가사를 넣어요", glyph: "pencil" },
                { key: "library", label: "저장한 곡", sub: "저장한 프리셋과 직접 입력한 곡을 모아 둬요", glyph: "library" }]
            Layout.fillWidth: true
            Layout.leftMargin: 20
            Layout.rightMargin: 20
            Layout.topMargin: 12
            Layout.bottomMargin: 12
            spacing: 8
            Repeater {
                model: tabBar.tabs
                delegate: Button {
                    id: tabButton
                    required property var modelData
                    readonly property bool on: modelData.key === drawer.tab
                    readonly property color fg: on ? Theme.primaryText : Theme.text
                    objectName: "drawerTab_" + modelData.key
                    Layout.fillWidth: true
                    Layout.preferredWidth: 1          // 세 칸을 같은 폭으로
                    Layout.preferredHeight: 76
                    text: modelData.label
                    hoverEnabled: true
                    focusPolicy: Qt.TabFocus
                    padding: 12
                    Keys.onReturnPressed: click()
                    Keys.onEnterPressed: click()
                    Accessible.role: Accessible.PageTab
                    Accessible.name: modelData.label + ", " + modelData.sub
                    Accessible.selected: on
                    HoverHandler { cursorShape: Qt.PointingHandCursor }
                    // 탭을 직접 누르면 저장한 곡은 모든 곡을 보인다 (직접 입력은 쓰던 내용 그대로)
                    onClicked: drawer.show(modelData.key)
                    contentItem: Column {
                        spacing: 6
                        // 아이콘 옆에 탭 이름, 그 아래 설명
                        Row {
                            width: parent.width
                            spacing: 5
                            Icon { id: tabIcon; glyph: tabButton.modelData.glyph; size: 15; color: tabButton.fg; anchors.verticalCenter: parent.verticalCenter }
                            Text {
                                width: parent.width - tabIcon.width - parent.spacing
                                text: tabButton.text
                                color: tabButton.fg
                                font.family: Theme.font
                                font.pixelSize: 13
                                font.weight: Font.Bold
                                elide: Text.ElideRight
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }
                        Text {
                            width: parent.width
                            text: tabButton.modelData.sub
                            color: tabButton.on ? Theme.primaryText : Theme.text3
                            font.family: Theme.font
                            font.pixelSize: 11
                            wrapMode: Text.Wrap
                            maximumLineCount: 2
                            elide: Text.ElideRight
                            lineHeight: 1.15
                        }
                    }
                    background: Rectangle {
                        radius: 12
                        color: tabButton.on ? Theme.primarySoft : tabButton.hovered ? Theme.border : Theme.surface2
                        border.width: tabButton.visualFocus ? 2 : tabButton.on ? 1.5 : 0
                        border.color: tabButton.visualFocus ? Theme.primary : Theme.focusBorder
                        Behavior on color { ColorAnimation { duration: Theme.fast } }
                    }
                }
            }
        }

        StackLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            currentIndex: drawer.tab === "library" ? 1 : drawer.tab === "manual" ? 2 : 0

            SearchPanel {
                id: searchPanel
                objectName: "searchPanel"
                setlist: drawer.setlist
                loadingIds: drawer.loadingIds
                addedIds: drawer.addedIds
                onSongClicked: (song) => drawer.songClicked(song)
                onPresetsRequested: (song) => drawer.show("library", { filterSong: song.song_id })
                onManualRequested: (info) => drawer.show("manual", { manual: info })
            }

            // 보관함: 모든 곡의 프리셋 (검색 결과의 '프리셋 N' 배지로 오면 그 곡만)
            ColumnLayout {
                spacing: 0
                RowLayout {
                    Layout.fillWidth: true
                    Layout.leftMargin: 20
                    Layout.rightMargin: 20
                    Layout.preferredHeight: 28
                    spacing: 6
                    AppButton {
                        visible: !library.library
                        glyph: "chevron-left"
                        text: "모든 프리셋"
                        variant: "ghost"
                        size: "small"
                        onClicked: drawer.show("library")
                    }
                    Text {
                        Layout.fillWidth: true
                        text: !library.library
                              ? (library.songs.length ? [library.songs[0].title, library.songs[0].artist].filter(Boolean).join(" — ") : "")
                              : library.totalCount ? "곡 " + library.songCount + "개 · 프리셋 " + library.totalCount + "개" : ""
                        textFormat: Text.PlainText
                        color: Theme.text3
                        font.family: Theme.font
                        font.pixelSize: 12
                        elide: Text.ElideRight
                    }
                }
                PresetLibrary {
                    id: library
                    objectName: "drawerLibrary"
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    sideMargin: 20
                    setlist: drawer.setlist
                    currentId: drawer.currentId
                    appliedTexts: drawer.appliedTexts
                    onAddRequested: (song, preset) => drawer.presetChosen(song, preset)
                    onReplaceRequested: (song, preset) => drawer.presetChosen(song, preset)
                    // 한 곡 보기에서 마지막 프리셋을 지우면 모든 곡으로
                    onSongsChanged: if (!library.library && !library.songs.length) { library.filterSong = ""; library.refresh() }
                }
            }

            // 직접 입력: 칸이 모자라면 스크롤
            Flickable {
                id: manualScroll
                clip: true
                contentHeight: Math.max(height, manualForm.implicitHeight + 20)
                boundsBehavior: Flickable.StopAtBounds
                ScrollBar.vertical: ScrollBar {}
                ManualForm {
                    id: manualForm
                    objectName: "manualForm"
                    x: 20
                    width: manualScroll.width - 40
                    height: manualScroll.contentHeight - 20
                    onSubmitted: (info, text) => {
                        drawer.manualSubmitted(info, text)
                        manualForm.reset()
                        manualForm.focusFirst()
                    }
                }
            }
        }
    }

    // ── 도움말 (머리말의 ? 버튼, 첫 실행) ── 멜론 탭에서 보인다
    function showHelp(opts) {
        if (!tour) return
        show("melon")
        tour.start([
            { target: searchPanel.searchBoxItem, demo: searchDemo, title: "1. 멜론에서 찾기",
              body: "노래 제목이나 가수 이름을 입력하고 <b>Enter</b>를 누르면 멜론에서 찾아와요.<br><br>"
                  + "제목이 기억나지 않으면 <b>가사</b>를 입력해서 찾을 수도 있어요." },
            { target: searchPanel.resultsItem, demo: resultsDemo, title: "2. ＋로 담기",
              body: "곡을 누르면 콘티에 추가해요. 검색창은 열린 채로 <b>여러 곡을 연달아</b> 담을 수 있어요.<br><br>"
                  + "프리셋을 저장해 둔 곡은 오른쪽에 <b>프리셋</b> 표시가 있고, 누르면 그 프리셋에 저장한 그대로 콘티에 담아요." },
            { target: tabBar, title: "3. 직접 입력 · 저장한 곡",
              body: "<b>직접 입력</b>: 멜론에 없는 곡은 제목과 가사를 직접 적어요.<br>"
                  + "<b>저장한 곡</b>: 이전에 저장했던 프리셋이나 직접 입력한 곡을 모아서 보여 줘요." },
            { target: closeButton, title: "4. 닫고 편집하기",
              body: "다 담았으면 <b>✕</b>(또는 <b>Esc</b>), 바깥 영역 클릭으로 검색창을 닫고 편집을 시작해요.<br>"
                  + "나중에 곡을 더하려면 콘티의 <b>곡 추가</b>나 <b>" + Theme.mod + "K</b>를 눌러요." }
        ], opts)
    }

    // 검색창 복제본에 검색어를 한 글자씩 입력하고 Enter
    property Component searchDemo: Component {
        Demo {
            id: d
            readonly property string word: "노래 제목"
            property int typed: 0
            Rectangle { anchors.fill: parent; color: Theme.surface }
            Rectangle {
                id: demoBox
                anchors.fill: parent
                anchors.margins: drawer.tour.pad
                radius: 14
                color: Theme.surface
                border.width: 1.5
                border.color: Theme.focusBorder
                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 12
                    anchors.rightMargin: 6
                    spacing: 6
                    Icon { glyph: "search"; color: Theme.text3 }
                    Text {
                        Layout.fillWidth: true
                        leftPadding: 2
                        text: d.typed ? d.word.slice(0, d.typed) + "|" : "제목, 아티스트, 가사"
                        color: d.typed ? Theme.text : Theme.text3
                        font.family: Theme.font
                        font.pixelSize: 15
                    }
                    AppButton { id: demoSearchButton; text: "검색"; variant: "primary"; size: "small"; implicitHeight: 34 }
                }
            }
            onReset: { typed = 0; d.jumpTo(demoSearchButton, -2, 2.2) }
            script: {
                const steps = [[500, () => d.moveTo(demoBox, 0.4, 0.5)], [700, () => d.click()]]
                for (let i = 1; i <= word.length; i++) steps.push([i === 1 ? 400 : 140, () => d.typed++])
                steps.push([500, () => d.moveTo(demoSearchButton)], [750, () => d.click()])
                return steps
            }
        }
    }

    // 결과 목록 복제본에서 두 곡의 ＋를 차례로 누른다 (받는 중 → 담음)
    property Component resultsDemo: Component {
        Demo {
            id: d
            property var states: ["", "", ""]     // 행마다 "" / "loading" / "added"
            function setState(i, s) { const n = states.slice(); n[i] = s; states = n }
            Rectangle { anchors.fill: parent; color: Theme.surface }
            Column {
                id: rows
                anchors.fill: parent
                anchors.margins: drawer.tour.pad
                spacing: 4
                Repeater {
                    id: rowRepeater
                    model: 3
                    delegate: Rectangle {
                        id: row
                        required property int index
                        readonly property string status: d.states[index]
                        readonly property Item plus: plusButton
                        width: rows.width
                        height: 60
                        radius: Theme.radiusSm
                        color: status !== "" ? Theme.primarySoft : Theme.surface2Clear
                        Behavior on color { ColorAnimation { duration: Theme.fast } }
                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 8
                            anchors.rightMargin: 8
                            spacing: 12
                            Rectangle { Layout.preferredWidth: 44; Layout.preferredHeight: 44; radius: 8; color: Theme.skeleton }
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 3
                                Text { Layout.fillWidth: true; text: "노래 제목 " + (row.index + 1); color: Theme.text; font.family: Theme.font; font.pixelSize: 14; font.weight: Font.DemiBold }
                                Text { Layout.fillWidth: true; text: "가수 · 앨범"; color: Theme.text3; font.family: Theme.font; font.pixelSize: 12 }
                            }
                            Item {
                                Layout.preferredWidth: 64
                                Layout.preferredHeight: 36
                                Rectangle {
                                    id: plusButton
                                    anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    visible: row.status === ""
                                    width: 36; height: 36; radius: 18
                                    color: Theme.surface
                                    border.width: 1
                                    border.color: Theme.border
                                    Icon { anchors.centerIn: parent; glyph: "plus"; size: 16; color: Theme.text2 }
                                }
                                Row {
                                    anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    visible: row.status !== ""
                                    spacing: 4
                                    Icon {
                                        id: demoStatusIcon
                                        anchors.verticalCenter: parent.verticalCenter
                                        glyph: row.status === "loading" ? "loader" : "check"
                                        size: 14
                                        color: Theme.primaryText
                                        RotationAnimation on rotation {
                                            running: row.status === "loading"
                                            from: 0; to: 360; duration: 800; loops: Animation.Infinite
                                            onStopped: demoStatusIcon.rotation = 0
                                        }
                                    }
                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: row.status === "loading" ? "받는 중" : "담음"
                                        color: Theme.primaryText
                                        font.family: Theme.font
                                        font.pixelSize: 12
                                        font.weight: Font.Bold
                                    }
                                }
                            }
                        }
                    }
                }
            }
            onReset: { states = ["", "", ""]; d.jumpTo(rows, 0.6, 0.95) }
            script: [
                [500, () => d.moveTo(rowRepeater.itemAt(0).plus)],
                [600, () => { d.click(); d.setState(0, "loading") }],
                [700, () => d.setState(0, "added")],
                [400, () => d.moveTo(rowRepeater.itemAt(2).plus)],
                [600, () => { d.click(); d.setState(2, "loading") }],
                [700, () => d.setState(2, "added")]
            ]
        }
    }
}
