import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import "."
import "editor.js" as E

// 프리셋 고르기. 불러오면 그 프리셋의 슬라이드 그대로 편집 화면이 열린다.
//   openFor(song): 한 곡의 프리셋 (검색 결과의 '프리셋 N' 배지). song은 검색 결과의 곡 { song_id, title, artist, album, manual }
//   openLibrary(): 보관함 — 모든 곡의 프리셋을 곡별로 묶어 보여 주고 곡 제목·가수·프리셋 이름으로 찾는다
Popup {
    id: dialog
    property var song: null             // 한 곡 보기일 때의 곡 (보관함이면 null)
    readonly property bool library: song === null
    property var presets: []            // 보이는 프리셋 (보관함은 곡별로 묶은 순서)
    property int totalCount: 0          // 보관함의 전체 프리셋 수 (찾기 전)
    property var songInfo: ({})         // song_id → { title, artist, manual } (보관함의 곡 머리글)
    property string deletingId: ""      // 삭제를 한 번 더 확인하는 중인 프리셋
    signal loadRequested(var song, var preset)

    function openFor(s) {
        song = s
        filter.text = ""
        deletingId = ""
        refresh()
        if (presets.length) open()
    }

    function openLibrary() {
        song = null
        filter.text = ""
        deletingId = ""
        refresh()
        open()
    }

    function refresh() {
        if (!library) {
            presets = JSON.parse(backend.presetsFor(song.song_id))
            if (!presets.length) close()
            return
        }
        const all = JSON.parse(backend.allPresets())
        totalCount = all.length
        // 곡마다 묶는다 (가장 최근에 저장한 곡부터, 곡 안에서는 최근 것부터)
        const order = []
        const groups = {}
        const info = {}
        all.forEach(p => {
            if (!groups[p.song_id]) {
                groups[p.song_id] = []
                order.push(p.song_id)
                info[p.song_id] = { title: p.title, artist: p.artist, manual: p.manual === true }
            }
            groups[p.song_id].push(p)
        })
        const key = filter.text.replace(/\s+/g, "").toLowerCase()
        const match = (p) => !key || (p.title + p.artist + (p.name || "")).replace(/\s+/g, "").toLowerCase().indexOf(key) >= 0
        songInfo = info
        // 곡의 첫 프리셋에 머리글을 붙인다 (first)
        presets = order.reduce((acc, id) => acc.concat(!groups[id].some(match) ? []
            : groups[id].map((p, i) => Object.assign({}, p, { first: i === 0 }))), [])
    }

    // 프리셋에 저장된 곡 정보로 연다 (보관함에는 검색 결과의 곡이 없다)
    function songOf(preset) {
        if (!library) return song
        return { song_id: preset.song_id, title: preset.title, artist: preset.artist,
                 album: preset.album || "", manual: preset.manual === true }
    }

    function load(preset) {
        const s = songOf(preset)
        close()
        loadRequested(s, preset)
    }

    function remove(preset) {
        if (deletingId !== preset.id) { deletingId = preset.id; return }
        deletingId = ""
        backend.deletePreset(preset.id)
        refresh()
    }

    // '2026-10-15T14:03:00' → '2026년 10월 15일 오후 2:03'
    function dateText(iso) {
        const m = /^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2})/.exec(iso || "")
        if (!m) return ""
        const h = Number(m[4])
        return m[1] + "년 " + Number(m[2]) + "월 " + Number(m[3]) + "일 " + (h < 12 ? "오전 " : "오후 ")
               + ((h % 12) || 12) + ":" + m[5]
    }

    onAboutToShow: (library ? filter : contentItem).forceActiveFocus()

    parent: Overlay.overlay
    anchors.centerIn: parent
    width: Math.min(library ? 560 : 480, parent.width - 32)
    height: library ? Math.min(640, parent.height - 64) : Math.min(implicitHeight, parent.height - 64)
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
        // Enter: 맨 위(가장 최근) 프리셋을 불러온다
        Keys.onReturnPressed: if (dialog.presets.length) dialog.load(dialog.presets[0])
        Keys.onEnterPressed: if (dialog.presets.length) dialog.load(dialog.presets[0])

        Text {
            Layout.fillWidth: true
            text: dialog.library ? "보관함" : "프리셋"
            color: Theme.text
            font.family: Theme.font
            font.pixelSize: 17
            font.weight: Font.Bold
        }
        Text {
            Layout.fillWidth: true
            text: dialog.library
                  ? "저장한 프리셋 " + dialog.totalCount + "개 · 멜론 곡과 직접 입력한 곡 모두 여기에 있어요"
                  : (dialog.song ? [dialog.song.title, dialog.song.artist].filter(Boolean).join(" — ") : "")
            textFormat: Text.PlainText
            color: Theme.text3
            font.family: Theme.font
            font.pixelSize: 13
            elide: Text.ElideRight
        }
        Text {
            Layout.fillWidth: true
            Layout.bottomMargin: 6
            text: "불러오면 저장할 때의 슬라이드 그대로 편집 화면이 열려요."
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
            Keys.onReturnPressed: if (dialog.presets.length) dialog.load(dialog.presets[0])
            Keys.onEnterPressed: if (dialog.presets.length) dialog.load(dialog.presets[0])
            Accessible.name: "보관함에서 찾기"
            ContextMenu.menu: AppTextMenu { editor: filter }
        }

        // 비어 있을 때
        Text {
            visible: dialog.library && !dialog.presets.length
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.topMargin: 24
            horizontalAlignment: Text.AlignHCenter
            text: dialog.totalCount ? "찾는 프리셋이 없어요"
                                    : "아직 저장한 프리셋이 없어요.\n편집 화면 아래 '프리셋 저장'으로 지금 슬라이드를 저장할 수 있어요."
            color: Theme.text3
            font.family: Theme.font
            font.pixelSize: 14
            lineHeight: 1.4
            wrapMode: Text.Wrap
        }

        ListView {
            id: list
            visible: dialog.presets.length > 0
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.preferredHeight: dialog.library ? -1 : contentHeight
            implicitHeight: contentHeight
            clip: true
            spacing: 8
            boundsBehavior: Flickable.StopAtBounds
            model: dialog.presets
            ScrollBar.vertical: ScrollBar {}

            delegate: Column {
                id: item
                required property var modelData
                required property int index
                readonly property var groups: E.linesOf(E.parseBlocks(modelData.text))
                readonly property var info: dialog.songInfo[modelData.song_id] || {}
                width: ListView.view.width
                spacing: 0
                // 보관함: 곡마다 머리글
                Item {
                    visible: dialog.library && item.modelData.first === true
                    width: parent.width
                    height: visible ? 34 : 0
                    RowLayout {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: 6
                        spacing: 6
                        Text {
                            Layout.fillWidth: true
                            text: [item.info.title || "제목 없음", item.info.artist].filter(Boolean).join(" — ")
                            textFormat: Text.PlainText
                            color: Theme.text
                            font.family: Theme.font
                            font.pixelSize: 14
                            font.weight: Font.Bold
                            elide: Text.ElideRight
                        }
                        Rectangle {
                            visible: item.info.manual === true
                            implicitWidth: manualLabel.implicitWidth + 12
                            implicitHeight: 20
                            radius: 6
                            color: Theme.surface2
                            Text { id: manualLabel; anchors.centerIn: parent; text: "직접 입력"; color: Theme.text3; font.family: Theme.font; font.pixelSize: 11; font.weight: Font.DemiBold }
                        }
                    }
                }
                Rectangle {
                    width: parent.width
                    height: itemRow.implicitHeight + 24
                    radius: Theme.radiusSm
                    color: Theme.surface2
                    RowLayout {
                        id: itemRow
                        anchors.fill: parent
                        anchors.margins: 12
                        spacing: 10
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 3
                            Text {
                                Layout.fillWidth: true
                                text: item.modelData.name || dialog.dateText(item.modelData.saved_at)
                                textFormat: Text.PlainText
                                color: Theme.text
                                font.family: Theme.font
                                font.pixelSize: 14
                                font.weight: Font.DemiBold
                                elide: Text.ElideRight
                            }
                            Text {
                                Layout.fillWidth: true
                                text: (item.modelData.name ? dialog.dateText(item.modelData.saved_at) + " · " : "") + item.groups.length + "장"
                                color: Theme.text3
                                font.family: Theme.font
                                font.pixelSize: 12
                            }
                            // 처음 두 슬라이드 미리보기 (슬라이드 사이는 /)
                            Text {
                                Layout.fillWidth: true
                                text: item.groups.slice(0, 2).map(lines => lines.join(" ")).join("  /  ")
                                textFormat: Text.PlainText
                                color: Theme.text3
                                font.family: Theme.font
                                font.pixelSize: 12
                                elide: Text.ElideRight
                            }
                        }
                        AppButton {
                            glyph: "trash"
                            text: dialog.deletingId === item.modelData.id ? "삭제" : ""
                            variant: dialog.deletingId === item.modelData.id ? "danger" : "ghost"
                            size: "small"
                            onClicked: dialog.remove(item.modelData)
                            Accessible.name: dialog.deletingId === item.modelData.id ? "삭제 확인" : "이 프리셋 삭제"
                            AppToolTip { visible: parent.hovered && dialog.deletingId !== item.modelData.id; delay: 400; text: "이 프리셋 삭제" }
                        }
                        AppButton {
                            text: "불러오기"
                            variant: "primary"
                            size: "small"
                            onClicked: dialog.load(item.modelData)
                            Accessible.name: "불러오기: " + (item.modelData.name || dialog.dateText(item.modelData.saved_at))
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
