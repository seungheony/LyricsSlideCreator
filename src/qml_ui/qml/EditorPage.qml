import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import QtQuick.Dialogs
import QtQuick.Effects
import "."
import "editor.js" as E

Item {
    id: page

    property var toastHost: null
    property var dialog: null

    property var song: null
    property var blocks: []          // 가사 텍스트에서 파생된 슬라이드 목록
    property int active: -1          // 가사 커서가 위치한 슬라이드
    property bool applying: false    // 코드에서 텍스트를 바꾸는 중 (입력 이벤트 무시)
    property bool generating: false

    signal backRequested()

    readonly property bool lyricsFocused: lyrics.activeFocus
    readonly property bool dragging: slideList.dragging

    // ── 곡 불러오기 ──
    function load(newSong, lyricsText) {
        song = newSong
        art.source = "image://art/" + newSong.song_id
        backdrop.source = "image://art/" + newSong.song_id
        // 멜론 가사는 절 사이에 빈 줄이 섞여 있으므로 처음에는 2줄씩 자동으로 나눈다
        const text = E.serialize(E.regroup(E.allLines(E.parseBlocks(lyricsText)), 2))
        active = -1
        setText(text)
        resetHistory(text)
        lyrics.cursorPosition = 0
        lyricsScroll.contentItem.contentY = 0
        slideList.scrollToTop()
    }

    // ── 텍스트 반영 ──
    function setText(text) {
        const flick = lyricsScroll.contentItem
        const y = flick.contentY
        applying = true
        lyrics.text = text
        applying = false
        flick.contentY = y
        sync()
    }

    function sync() {
        blocks = E.parseBlocks(lyrics.text)
        if (active >= blocks.length) active = blocks.length - 1
    }

    // 구조 편집: 텍스트를 새로 쓰고 히스토리에 남긴 뒤 바뀐 슬라이드를 강조한다
    function commit(groups, opts) {
        opts = opts || {}
        flushTyping()
        setText(E.serialize(groups))
        record(lyrics.text)
        if (opts.focus !== undefined && opts.focus >= 0) {
            active = opts.focus
            Qt.callLater(slideList.flash, opts.focus)
        }
        if (opts.message && toastHost)
            toastHost.show(opts.message, { actionLabel: "되돌리기", onAction: page.undo })
    }

    function cutSlide(idx, at) {
        const groups = E.linesOf(blocks)
        const lines = groups[idx]
        groups.splice(idx, 1, lines.slice(0, at), lines.slice(at))
        commit(groups, { focus: idx + 1 })
    }

    function joinSlides(idx) {
        const groups = E.linesOf(blocks)
        groups.splice(idx, 2, groups[idx].concat(groups[idx + 1]))
        commit(groups, { focus: idx })
    }

    function removeSlide(idx) {
        const groups = E.linesOf(blocks)
        groups.splice(idx, 1)
        active = -1
        commit(groups, { message: (idx + 1) + "번 슬라이드를 삭제했어요" })
    }

    function autoSplit(n) {
        active = -1
        commit(E.regroup(E.allLines(blocks), n), { message: n + "줄씩 다시 나눴어요" })
        slideList.scrollToTop()
    }

    // 줄 드래그: 옆 슬라이드로만 옮기고, 넘치면 연쇄로 민다. 2줄 유지를 켜면 빈자리를 연쇄로 당겨 채운다
    property bool keepTwo: false

    // 놓으려는 위치를 허용된 동작으로 바꾼다. 허용되지 않거나 바뀌는 게 없으면 null
    function resolveDrop(src, raw) {
        const target = E.resolveDrop(blocks, src, raw)
        return target && E.planDrop(blocks, src, target, keepTwo) ? target : null
    }

    function moveLine(src, target) {
        const plan = E.planDrop(blocks, src, target, keepTwo)
        if (plan) commit(plan.groups, { focus: plan.focus })
    }

    // ── 히스토리 (⌘Z) ──
    // 타이핑과 구조 편집을 하나의 스냅샷 스택으로 관리한다.
    property var hist: []
    property int histIdx: -1

    function record(text) {
        typingTimer.stop()
        if (hist[histIdx] === text) return
        const next = hist.slice(0, histIdx + 1)
        next.push(text)
        if (next.length > 200) next.shift()
        hist = next
        histIdx = next.length - 1
    }

    function resetHistory(text) {
        typingTimer.stop()
        hist = [text]
        histIdx = 0
    }

    function flushTyping() {
        if (typingTimer.running) record(lyrics.text)
    }

    function undo() {
        flushTyping()
        if (histIdx <= 0) return
        histIdx--
        setText(hist[histIdx])
    }

    function redo() {
        flushTyping()
        if (histIdx >= hist.length - 1) return
        histIdx++
        setText(hist[histIdx])
    }

    Timer { id: typingTimer; interval: 600; onTriggered: page.record(lyrics.text) }

    // ── 가사 ↔ 슬라이드 연결 ──
    function syncActiveFromCaret() {
        const idx = E.blockIndexAt(blocks, lyrics.cursorPosition)
        if (idx !== active) {
            active = idx
            slideList.ensureVisible(idx)
        }
    }

    function revealInText(idx) {
        const block = blocks[idx]
        if (!block) return
        lyrics.forceActiveFocus()
        lyrics.select(block.start, block.end)
        // 선택한 가사가 위에서 1/3 지점에 오도록 스크롤
        const flick = lyricsScroll.contentItem
        const rect = lyrics.positionToRectangle(block.start)
        const max = Math.max(0, flick.contentHeight - flick.height)
        flick.contentY = Math.max(0, Math.min(max, rect.y - flick.height / 3))
        active = idx
    }

    function blurLyrics() { page.forceActiveFocus() }
    function cancelDrag() { slideList.cancelDrag() }

    // ── 템플릿 / 생성 ──
    function generate() {
        if (generating) return
        if (!blocks.length) {
            dialog.showError("가사가 없습니다.")
            return
        }
        const name = (song ? song.title + " — " + song.artist : "lyrics").replace(/[\/\\:*?"<>|]/g, "_")
        saveDialog.selectedFile = saveDialog.currentFolder + "/" + name + ".pptx"
        saveDialog.open()
    }

    Connections {
        target: backend
        function onGenerateFinished(json) {
            page.generating = false
            const res = JSON.parse(json)
            if (res.error) page.dialog.showError(res.error, res.detail)
            else page.toastHost.show("PPT 생성이 완료되었습니다!")
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
            page.generating = true
            backend.generatePpt(JSON.stringify(page.blocks.map(b => b.lines.join("\n"))), selectedFile.toString())
        }
    }

    FileDialog {
        id: templateDialog
        title: "PPT 템플릿"
        fileMode: FileDialog.OpenFile
        nameFilters: ["PowerPoint (*.pptx)"]
        onAccepted: {
            templateName.text = backend.setTemplate(selectedFile.toString())
            page.toastHost.show("템플릿을 변경했습니다")
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
                        color: Theme.text
                        font.family: Theme.font
                        font.pixelSize: 20
                        font.weight: Font.Bold
                        elide: Text.ElideRight
                    }
                    Text {
                        Layout.fillWidth: true
                        text: page.song ? page.song.artist + " · " + page.song.album : ""
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
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.preferredWidth: 1000
                spacing: 10

                RowLayout {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 34
                    Text { text: "가사"; color: Theme.text; font.family: Theme.font; font.pixelSize: 15; font.weight: Font.Bold }
                    Item { Layout.fillWidth: true }
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

                Rectangle {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    radius: Theme.radius
                    color: Theme.surface
                    border.width: 1.5
                    border.color: lyrics.activeFocus ? Theme.primary : Theme.border
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
                                page.sync()
                                page.syncActiveFromCaret()
                                typingTimer.restart()
                            }
                            onCursorPositionChanged: if (!page.applying) page.syncActiveFromCaret()

                            // ⌘Z / ⇧⌘Z 는 앱 전체 히스토리로 처리
                            Keys.onPressed: (event) => {
                                if (event.matches(StandardKey.Undo)) { page.undo(); event.accepted = true }
                                else if (event.matches(StandardKey.Redo)) { page.redo(); event.accepted = true }
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
                        text: "하나가 슬라이드 경계예요 · Enter 두 번으로 나누고, 빈 줄을 지우면 합쳐져요"
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
                Layout.preferredWidth: 1150
                spacing: 10

                RowLayout {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 34
                    Text { text: "슬라이드"; color: Theme.text; font.family: Theme.font; font.pixelSize: 15; font.weight: Font.Bold }
                    Rectangle {
                        visible: page.blocks.length > 0
                        width: countText.implicitWidth + 16; height: 20; radius: 10
                        color: Theme.primarySoft
                        Text { id: countText; anchors.centerIn: parent; text: page.blocks.length + "장"; color: Theme.primary; font.family: Theme.font; font.pixelSize: 12; font.weight: Font.DemiBold }
                    }
                    Item { Layout.fillWidth: true }
                    CheckBox {
                        id: keepTwoBox
                        text: "2줄 유지"
                        checked: page.keepTwo
                        onToggled: page.keepTwo = checked
                        hoverEnabled: true
                        spacing: 6
                        padding: 4
                        Layout.rightMargin: 6
                        ToolTip.visible: hovered
                        ToolTip.delay: 500
                        ToolTip.text: "줄을 옮기면 빈자리를 뒤(또는 앞) 슬라이드에서 연쇄로 당겨와 2줄씩 유지해요"
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
                    AppButton {
                        glyph: "undo"; variant: "ghost"; size: "small"
                        enabled: page.histIdx > 0
                        onClicked: page.undo()
                        ToolTip.visible: hovered; ToolTip.delay: 600; ToolTip.text: "되돌리기 (⌘Z)"
                    }
                    AppButton {
                        glyph: "redo"; variant: "ghost"; size: "small"
                        enabled: page.histIdx < page.hist.length - 1
                        onClicked: page.redo()
                        ToolTip.visible: hovered; ToolTip.delay: 600; ToolTip.text: "다시 실행 (⇧⌘Z)"
                    }
                }

                SlideList {
                    id: slideList
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    blocks: page.blocks
                    active: page.active
                    resolveDrop: (src, raw) => page.resolveDrop(src, raw)
                    onCutRequested: (slide, at) => page.cutSlide(slide, at)
                    onJoinRequested: (slide) => page.joinSlides(slide)
                    onRemoveRequested: (slide) => page.removeSlide(slide)
                    onMoveRequested: (src, target) => page.moveLine(src, target)
                    onRevealRequested: (slide) => page.revealInText(slide)
                }

                Text {
                    Layout.fillWidth: true
                    text: "첫 줄은 앞, 마지막 줄은 뒤 슬라이드로 <b>드래그</b> · 줄 사이 <b>✂</b> → 나누기 · 슬라이드 사이 → 합치기 · 클릭 → 가사로 이동"
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
                Icon { glyph: "monitor"; color: Theme.text3 }
                Text { text: "템플릿"; color: Theme.text3; font.family: Theme.font; font.pixelSize: 13 }
                Text {
                    id: templateName
                    Component.onCompleted: text = backend.templateName()
                    color: Theme.text
                    font.family: Theme.font
                    font.pixelSize: 13
                    font.weight: Font.DemiBold
                    elide: Text.ElideMiddle
                    Layout.maximumWidth: 260
                }
                AppButton { text: "변경"; variant: "ghost"; size: "small"; onClicked: templateDialog.open() }
                Item { Layout.fillWidth: true }
                AppButton {
                    text: "PPT 생성"
                    variant: "primary"
                    size: "large"
                    busy: page.generating
                    implicitWidth: 140
                    onClicked: page.generate()
                }
            }
        }
    }
}
