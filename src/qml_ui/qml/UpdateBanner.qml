import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import "."

// 새 버전 알림 막대 (창 맨 위). 화면을 아래로 밀어서 검색창·편집 머리글을 가리지 않는다
Rectangle {
    id: banner
    property string version: ""
    property bool shown: false

    signal updateClicked()
    signal notesClicked()
    signal dismissed()

    readonly property int barHeight: 48
    height: shown ? barHeight : 0
    visible: height > 0
    clip: true
    color: Theme.surface
    Behavior on height { NumberAnimation { duration: Theme.normal; easing.type: Easing.OutCubic } }

    Rectangle { anchors.fill: parent; color: Theme.primarySoft }
    Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Theme.border }

    // 접히는 동안 내용이 위로 밀려 올라가도록 아래쪽에 붙인다
    RowLayout {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.leftMargin: 20
        anchors.rightMargin: 12
        height: banner.barHeight
        spacing: 8
        Rectangle {
            width: 26; height: 26; radius: 13
            color: Theme.primarySoft
            Icon { anchors.centerIn: parent; glyph: "download"; size: 14; color: Theme.primaryText }
        }
        Text {
            Layout.fillWidth: true
            // 버전 뒤에 조사를 바로 붙이지 않는다 (숫자 읽기에 따라 이/가가 달라짐)
            text: "<b>v" + banner.version + "</b> 버전이 나왔어요"
            textFormat: Text.StyledText
            elide: Text.ElideRight
            color: Theme.text
            font.family: Theme.font
            font.pixelSize: 13
        }
        AppButton { text: "변경 내용"; variant: "ghost"; size: "small"; onClicked: banner.notesClicked() }
        AppButton { text: "업데이트"; variant: "primary"; size: "small"; onClicked: banner.updateClicked() }
        AppButton { glyph: "x"; variant: "ghost"; size: "small"; Accessible.name: "알림 닫기"; onClicked: banner.dismissed() }
    }
}
