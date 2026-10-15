import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import "."
import "editor.js" as E

// 프리셋 고르기. 불러오면 그 프리셋의 슬라이드 그대로 편집 화면이 열린다.
// 곡마다 카드 하나(앨범아트·제목·가수)에 프리셋을 한 줄씩 두고, 슬라이드는 펼쳐야 보인다.
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
    property string expandedId: ""      // 슬라이드를 펼친 프리셋
    property string renamingId: ""      // 이름을 고치는 중인 프리셋
    property string deletingId: ""      // 삭제를 한 번 더 확인하는 중인 프리셋
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

    function refresh() {
        const all = JSON.parse(library ? backend.allPresets() : backend.presetsFor(song.song_id))
        totalCount = all.length
        // 곡마다 묶는다 (가장 최근에 저장한 곡부터, 곡 안에서는 최근 것부터). 편집 중인 곡은 맨 위
        const order = []
        const groups = {}
        all.forEach(p => {
            if (!groups[p.song_id]) {
                groups[p.song_id] = { song_id: p.song_id, title: p.title, artist: p.artist, album: p.album || "",
                                      manual: p.manual === true, image_url: p.image_url || "", presets: [] }
                order.push(p.song_id)
            }
            const g = groups[p.song_id]
            if (!g.image_url && p.image_url) g.image_url = p.image_url
            g.presets.push(p)
        })
        const cur = order.indexOf(currentId)
        if (cur > 0) order.unshift(order.splice(cur, 1)[0])
        const key = filter.text.replace(/\s+/g, "").toLowerCase()
        const match = (p) => !key || (p.title + p.artist + (p.name || "")).replace(/\s+/g, "").toLowerCase().indexOf(key) >= 0
        songs = order.map(id => groups[id]).filter(g => g.presets.some(match))
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

    function toggle(preset) { expandedId = expandedId === preset.id ? "" : preset.id }

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

    // '2026-10-15T14:03:00' → '2026년 10월 15일 오후 2:03' (short: '10월 15일')
    function dateText(iso, short) {
        const m = /^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2})/.exec(iso || "")
        if (!m) return ""
        if (short) return Number(m[2]) + "월 " + Number(m[3]) + "일"
        const h = Number(m[4])
        return m[1] + "년 " + Number(m[2]) + "월 " + Number(m[3]) + "일 " + (h < 12 ? "오전 " : "오후 ")
               + ((h % 12) || 12) + ":" + m[5]
    }

    onAboutToShow: (library && totalCount ? filter : contentItem).forceActiveFocus()

    parent: Overlay.overlay
    anchors.centerIn: parent
    width: Math.min(620, parent.width - 32)
    height: library ? Math.min(680, parent.height - 64) : Math.min(implicitHeight, parent.height - 64)
    modal: true
    focus: true
    padding: 24
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
    Overlay.modal: Rectangle { color: Qt.rgba(0, 0, 0, 0.4) }
    enter: Transition {
        NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 200 }
        NumberAnimation { property: "scale"; from: 0.96; to: 1; duration: 250; easing.type: Easing.OutCubic }
    }
    exit: Transition { NumberAnimation { property: "opacity"; to: 0; duration: 150 } }
    background: Rectangle { radius: 18; color: Theme.surface }

    contentItem: ColumnLayout {
        spacing: 6
        focus: true
        // Enter: 맨 위 곡의 가장 최근 프리셋을 불러온다
        Keys.onReturnPressed: if (dialog.songs.length) dialog.load(dialog.songs[0], dialog.songs[0].presets[0])
        Keys.onEnterPressed: if (dialog.songs.length) dialog.load(dialog.songs[0], dialog.songs[0].presets[0])

        RowLayout {
            Layout.fillWidth: true
            spacing: 8
            Text {
                text: dialog.library ? "보관함" : "프리셋"
                color: Theme.text
                font.family: Theme.font
                font.pixelSize: 17
                font.weight: Font.Bold
            }
            Text {
                visible: dialog.library && dialog.totalCount > 0
                text: dialog.totalCount + "개"
                color: Theme.text3
                font.family: Theme.font
                font.pixelSize: 14
            }
            Item { Layout.fillWidth: true }
        }
        Text {
            Layout.fillWidth: true
            Layout.bottomMargin: 6
            text: dialog.fromEditor ? "불러오면 콘티에 더해요. 편집 중인 곡이면 가사를 그 프리셋으로 바꿔요(되돌릴 수 있어요)."
                                    : "불러오면 저장할 때의 슬라이드 그대로 편집 화면이 열려요."
            color: Theme.text2
            font.family: Theme.font
            font.pixelSize: 13
            wrapMode: Text.Wrap
        }

        // 보관함에서 찾기
        TextField {
            id: filter
            visible: dialog.library && dialog.totalCount > 0
            Layout.fillWidth: true
            Layout.bottomMargin: 6
            placeholderText: "곡 제목·가수·프리셋 이름으로 찾기"
            placeholderTextColor: Theme.text3
            color: Theme.text
            font.family: Theme.font
            font.pixelSize: 14
            selectByMouse: true
            leftPadding: 12; rightPadding: 12
            implicitHeight: 38
            background: Rectangle { radius: 10; color: Theme.surface2; border.width: filter.activeFocus ? 1.5 : 0; border.color: Theme.focusBorder }
            onTextChanged: dialog.refresh()
            Keys.onReturnPressed: if (dialog.songs.length) dialog.load(dialog.songs[0], dialog.songs[0].presets[0])
            Keys.onEnterPressed: if (dialog.songs.length) dialog.load(dialog.songs[0], dialog.songs[0].presets[0])
            Accessible.name: "보관함에서 찾기"
            ContextMenu.menu: AppTextMenu { editor: filter }
        }

        // 비어 있을 때
        Text {
            visible: dialog.library && !dialog.songs.length
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.topMargin: 24
            horizontalAlignment: Text.AlignHCenter
            text: dialog.totalCount ? "찾는 프리셋이 없어요"
                                    : "아직 저장한 프리셋이 없어요.\n편집 화면 아래 '프리셋'의 '저장'으로 지금 슬라이드를 저장할 수 있어요."
            color: Theme.text3
            font.family: Theme.font
            font.pixelSize: 14
            lineHeight: 1.4
            wrapMode: Text.Wrap
        }

        ListView {
            id: list
            visible: dialog.songs.length > 0
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.preferredHeight: dialog.library ? -1 : contentHeight
            implicitHeight: contentHeight
            clip: true
            spacing: 12
            boundsBehavior: Flickable.StopAtBounds
            model: dialog.songs
            ScrollBar.vertical: ScrollBar {}

            // 곡 카드: 앨범아트·제목·가수, 아래에 프리셋 줄
            delegate: Rectangle {
                id: card
                required property var modelData
                readonly property bool current: modelData.song_id === dialog.currentId
                width: ListView.view.width
                height: cardColumn.implicitHeight + 24
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
                    anchors.margins: 12
                    spacing: 6

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 12
                        RoundedImage {
                            id: art
                            Layout.preferredWidth: 44
                            Layout.preferredHeight: 44
                            radius: 8
                            placeholder: Theme.surface2
                            Icon { anchors.centerIn: parent; visible: !art.ready; glyph: "music"; size: 20; color: Theme.text3 }
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 2
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
                                text: [card.modelData.manual ? "직접 입력" : "", card.modelData.artist,
                                       "프리셋 " + card.modelData.presets.length + "개"].filter(Boolean).join(" · ")
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
                            readonly property string label: modelData.name || dialog.dateText(modelData.saved_at)
                            Layout.fillWidth: true
                            spacing: 0

                            Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: Theme.border }

                            RowLayout {
                                Layout.fillWidth: true
                                Layout.topMargin: 6
                                Layout.bottomMargin: item.expanded ? 4 : 0
                                spacing: 4

                                // 펼치기: 이름·정보 줄을 누른다 (키보드는 Tab으로 와서 Space·Enter)
                                Item {
                                    id: toggleArea
                                    Layout.fillWidth: true
                                    implicitHeight: 34
                                    visible: !item.renaming
                                    activeFocusOnTab: true
                                    Keys.onSpacePressed: dialog.toggle(item.modelData)
                                    Keys.onReturnPressed: dialog.toggle(item.modelData)
                                    Keys.onEnterPressed: dialog.toggle(item.modelData)
                                    Accessible.role: Accessible.Button
                                    Accessible.name: item.label + ", " + item.groups.length + "장, " + (item.expanded ? "접기" : "슬라이드 펼쳐 보기")
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
                                            Layout.maximumWidth: toggleArea.width * 0.6
                                            text: item.label
                                            textFormat: Text.PlainText
                                            color: Theme.text
                                            font.family: Theme.font
                                            font.pixelSize: 14
                                            font.weight: Font.DemiBold
                                            elide: Text.ElideRight
                                        }
                                        Text {
                                            Layout.fillWidth: true
                                            text: (item.modelData.name ? dialog.dateText(item.modelData.saved_at, true) + " · " : "") + item.groups.length + "장"
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
                                        radius: 6
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
                                    background: Rectangle { radius: 8; color: Theme.surface2; border.width: 1.5; border.color: Theme.focusBorder }
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
                                    visible: !item.renaming && !item.deleting
                                    glyph: "pencil"; variant: "ghost"; size: "small"
                                    onClicked: dialog.startRename(item.modelData)
                                    Accessible.name: "이름 고치기"
                                    AppToolTip { visible: parent.hovered; delay: 400; text: "이름 고치기" }
                                }
                                AppButton {
                                    visible: !item.renaming
                                    glyph: "trash"
                                    text: item.deleting ? "삭제" : ""
                                    variant: item.deleting ? "danger" : "ghost"
                                    size: "small"
                                    onClicked: dialog.remove(item.modelData)
                                    Accessible.name: item.deleting ? "삭제 확인" : "이 프리셋 삭제"
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

                            // 슬라이드별 가사 배치 (펼쳤을 때만): 번호와 줄만 보인다
                            Rectangle {
                                visible: item.expanded
                                Layout.fillWidth: true
                                Layout.leftMargin: 20
                                Layout.bottomMargin: 8
                                implicitHeight: slideColumn.implicitHeight + 16
                                radius: 8
                                color: Theme.surface2
                                Column {
                                    id: slideColumn
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.top: parent.top
                                    anchors.margins: 8
                                    spacing: 6
                                    Repeater {
                                        model: item.expanded ? item.groups : []
                                        delegate: Row {
                                            id: slideLine
                                            required property var modelData
                                            required property int index
                                            width: slideColumn.width
                                            spacing: 8
                                            Text {
                                                width: 22
                                                horizontalAlignment: Text.AlignRight
                                                text: slideLine.index + 1
                                                color: Theme.text3
                                                font.family: Theme.font
                                                font.pixelSize: 12
                                                font.weight: Font.DemiBold
                                            }
                                            Text {
                                                width: parent.width - 30
                                                text: slideLine.modelData.join("\n")
                                                textFormat: Text.PlainText
                                                color: Theme.text2
                                                font.family: Theme.font
                                                font.pixelSize: 13
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

        AppButton {
            Layout.alignment: Qt.AlignRight
            Layout.topMargin: 10
            text: "닫기"
            variant: "ghost"
            onClicked: dialog.close()
        }
    }
}
