import QtQuick
import QtQuick.Controls.Basic
import "."

// 프리셋이 있는 곡의 설정 버튼 (멜론 검색 결과 행·보관함 카드 오른쪽): [보관함 아이콘 지금 설정 이름].
// 이 곡이 담길 버전(멜론 가사 그대로 또는 프리셋)을 보이고, 누르면 버튼 아래(오른쪽 끝 맞춤)에 고르기 목록(PresetChoices)을 띄운다.
// 고르면 그 곡의 설정이 바뀔 뿐 담지는 않는다 (담기는 행·카드를 누르거나 콘티로 끌어다 놓기)
Rectangle {
    id: picker
    property var song: null
    property var presets: []          // 설정된 프리셋(default: true)이 맨 앞
    property bool melon: true         // 목록에 '멜론 가사 그대로' (직접 입력한 곡은 없음)
    readonly property var selected: presets.find(p => p.default === true) || null    // null이면 멜론 가사
    readonly property string label: selected ? (selected.name || dateLabel(selected.saved_at)) : "멜론 가사"
    readonly property bool hovered: area.containsMouse
    readonly property bool menuOpen: menu.opened

    function dateLabel(iso) {
        const m = /^(\d{4})-(\d{2})-(\d{2})/.exec(iso || "")
        return m ? Number(m[2]) + "월 " + Number(m[3]) + "일 저장" : "프리셋"
    }
    function openMenu() { menu.open() }
    // 탭을 바꾸거나 서랍을 닫아 버튼이 안 보이게 되면 목록도 닫는다 (Popup은 부모가 숨어도 남아 있다)
    onVisibleChanged: if (!visible) menu.close()

    implicitWidth: pickerRow.implicitWidth + 24
    implicitHeight: 30
    radius: 15
    // 회색 알약 (초록은 눈에 너무 띄어서 쓰지 않는다)
    color: area.containsMouse || menu.opened ? Theme.border : Theme.surface2
    Behavior on color { ColorAnimation { duration: Theme.fast } }
    Accessible.role: Accessible.ComboBox
    Accessible.name: "담을 버전: " + label

    Row {
        id: pickerRow
        anchors.centerIn: parent
        spacing: 5
        Icon { glyph: "library"; size: 13; color: Theme.text3; anchors.verticalCenter: parent.verticalCenter }
        Text {
            width: Math.min(implicitWidth, 120)
            anchors.verticalCenter: parent.verticalCenter
            text: picker.label
            textFormat: Text.PlainText
            elide: Text.ElideRight
            color: Theme.text2
            font.family: Theme.font
            font.pixelSize: 13
            font.weight: Font.DemiBold
        }
    }
    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: menu.opened ? menu.close() : menu.open()
    }
    AppToolTip { visible: area.containsMouse && !menu.opened; delay: 400; text: "이 곡을 담을 버전 · 눌러서 바꿔요" }

    Popup {
        id: menu
        popupType: Popup.Item
        x: picker.width - width
        y: picker.height + 4
        width: 280
        padding: 6
        margins: 8
        focus: true
        // 떠 있는 동안 뒤 목록이 스크롤되지 않게 (스크롤되면 목록이 버튼에서 떨어진다). 바깥을 누르면 닫힌다
        modal: true
        dim: false
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
        onClosed: { choicesList.renamingId = ""; choicesList.deletingId = "" }
        background: Rectangle {
            radius: 10
            color: Theme.surface
            border.width: 1
            border.color: Theme.border
        }
        contentItem: PresetChoices {
            id: choicesList
            song: picker.song
            presets: picker.presets
            melon: picker.melon
            onChosen: menu.close()
        }
    }
}
