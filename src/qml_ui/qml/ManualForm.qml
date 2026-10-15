import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import "."
import "editor.js" as E

// 곡 찾기 서랍의 '직접 입력' 탭: 제목·가수·가사를 넣어 콘티에 담는다.
// prefill(info): info = { title, artist, album, song_id, notice } — 멜론 곡에서 왔으면 album·song_id를 이어받으려고 보관한다
// submitted(info, text): info = { title, artist, album, song_id } (없으면 빈 값).
//   song_id 만들기(Main.manualId)와 콘티에 더하기는 받는 쪽이 한다. 멜론 가사를 처음 열 때처럼 정리하고 2줄씩 나눈다(newEntry)
// reset(), focusFirst()
Item {
    id: form

    signal submitted(var info, string text)

    property string notice: ""
    property string album: ""
    property string songId: ""
    // 담으면 2줄씩 나뉘므로 그 기준의 장 수
    readonly property int slideCount: E.regroupWithin(lyrics.text, 2).length
    readonly property bool canSubmit: slideCount > 0

    implicitWidth: 360
    implicitHeight: column.implicitHeight

    function prefill(info) {
        info = info || {}
        reset()
        titleField.text = info.title || ""
        artistField.text = info.artist || ""
        album = info.album || ""
        songId = info.song_id || ""
        notice = info.notice || ""
    }

    function reset() {
        titleField.text = ""
        artistField.text = ""
        lyrics.text = ""
        album = ""
        songId = ""
        notice = ""
    }

    // 제목이 비었으면 제목, 미리 채웠으면 가사부터
    function focusFirst() {
        if (titleField.text.trim() === "") titleField.forceActiveFocus(Qt.TabFocusReason)
        else lyrics.forceActiveFocus(Qt.TabFocusReason)
    }

    function submit() {
        Qt.inputMethod.commit()    // 한글 조합 중인 글자를 확정한 뒤 읽는다
        if (!canSubmit) return
        submitted({ title: titleField.text.trim(), artist: artistField.text.trim(), album: album, song_id: songId },
                  lyrics.text)
    }

    // ⌘↵ / Ctrl+Enter: 어느 칸에서든 담기
    function submitKey(event) {
        if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && (event.modifiers & Qt.ControlModifier)) {
            submit()
            event.accepted = true
        }
    }

    function moveFocusFrom(item, forward) {
        const next = item.nextItemInFocusChain(forward)
        if (next && next !== item) next.forceActiveFocus(forward ? Qt.TabFocusReason : Qt.BacktabFocusReason)
    }

    Keys.onPressed: (event) => submitKey(event)

    component FieldLabel: Text {
        color: Theme.text3
        font.family: Theme.font
        font.pixelSize: 12
        font.weight: Font.DemiBold
    }

    component Field: TextField {
        id: field
        Layout.fillWidth: true
        placeholderTextColor: Theme.text3
        color: Theme.text
        font.family: Theme.font
        font.pixelSize: 14
        selectByMouse: true
        leftPadding: 12; rightPadding: 12
        implicitHeight: 40
        background: Rectangle { radius: Theme.radiusSm; color: Theme.surface2; border.width: field.activeFocus ? 1.5 : 0; border.color: Theme.focusBorder }
        Keys.onPressed: (event) => form.submitKey(event)
        ContextMenu.menu: AppTextMenu { editor: field }
    }

    ColumnLayout {
        id: column
        anchors.fill: parent
        spacing: 6

        // 멜론에서 찾지 못해 넘어온 경우 등의 안내
        Rectangle {
            Layout.fillWidth: true
            Layout.bottomMargin: 6
            visible: form.notice !== ""
            implicitHeight: noticeText.implicitHeight + 20
            radius: Theme.radiusSm
            color: Theme.primarySoft
            Text {
                id: noticeText
                objectName: "manualNotice"
                anchors.fill: parent
                anchors.margins: 10
                anchors.leftMargin: 12
                anchors.rightMargin: 12
                text: form.notice
                textFormat: Text.PlainText
                color: Theme.primaryText
                font.family: Theme.font
                font.pixelSize: 13
                lineHeight: 1.3
                wrapMode: Text.Wrap
                verticalAlignment: Text.AlignVCenter
            }
        }

        FieldLabel { text: "제목" }
        Field {
            id: titleField
            objectName: "manualTitle"
            placeholderText: "곡 제목"
            maximumLength: 200
            onAccepted: artistField.forceActiveFocus()
            Accessible.name: "곡 제목"
        }

        FieldLabel { text: "가수 (선택)"; Layout.topMargin: 6 }
        Field {
            id: artistField
            objectName: "manualArtist"
            placeholderText: "가수"
            maximumLength: 200
            onAccepted: lyrics.forceActiveFocus()
            Accessible.name: "가수"
        }

        FieldLabel { text: "가사"; Layout.topMargin: 6 }
        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.minimumHeight: 120
            radius: Theme.radiusSm
            color: Theme.surface
            border.width: 1.5
            border.color: lyrics.activeFocus ? Theme.focusBorder : Theme.border
            Behavior on border.color { ColorAnimation { duration: Theme.fast } }

            ScrollView {
                anchors.fill: parent
                anchors.margins: 2

                TextArea {
                    id: lyrics
                    objectName: "manualLyrics"
                    padding: 12
                    color: Theme.text
                    font.family: Theme.font
                    font.pixelSize: 14
                    selectByMouse: true
                    selectionColor: Theme.primarySoft
                    selectedTextColor: Theme.text
                    wrapMode: TextEdit.Wrap
                    placeholderText: "가사를 붙여 넣거나 입력하세요"
                    placeholderTextColor: Theme.text3
                    background: null
                    // Tab은 탭 문자를 넣지 않고 다음(Shift+Tab은 이전) 컨트롤로 옮긴다
                    Keys.onTabPressed: (event) => { form.moveFocusFrom(lyrics, true); event.accepted = true }
                    Keys.onBacktabPressed: (event) => { form.moveFocusFrom(lyrics, false); event.accepted = true }
                    Keys.onPressed: (event) => form.submitKey(event)
                    Accessible.name: "가사"
                    ContextMenu.menu: AppTextMenu { editor: lyrics }
                }
            }
        }

        Text {
            objectName: "manualSlideCount"
            text: form.slideCount === 0 ? "슬라이드 없음" : "슬라이드 " + form.slideCount + "장"
            color: form.slideCount === 0 ? Theme.text3 : Theme.text
            font.family: Theme.font
            font.pixelSize: 13
            font.weight: Font.DemiBold
        }

        AppButton {
            id: submitButton
            objectName: "manualSubmit"
            Layout.fillWidth: true
            Layout.topMargin: 6
            variant: "primary"
            glyph: "plus"
            text: "콘티에 담기"
            enabled: form.canSubmit
            onClicked: form.submit()
            Accessible.name: "콘티에 담기"
            AppToolTip {
                visible: submitButton.hovered
                text: "콘티에 담기 (" + Theme.mod + (Qt.platform.os === "osx" ? "↵" : "Enter") + ")"
            }
        }
    }
}
