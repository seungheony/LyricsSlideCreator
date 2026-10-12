import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import "."

// 새 버전 알림 카드 (창 오른쪽 위)
Rectangle {
    id: banner
    property string version: ""
    property bool shown: false

    signal updateClicked()
    signal notesClicked()

    width: row.implicitWidth + 28
    height: 52
    radius: Theme.radius
    color: Theme.surface
    border.width: 1
    border.color: Theme.border
    opacity: shown ? 1 : 0
    visible: opacity > 0
    transform: Translate { y: banner.shown ? 0 : -12; Behavior on y { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } } }
    Behavior on opacity { NumberAnimation { duration: 250 } }

    // 그림자 대신 살짝 겹친 테두리
    Rectangle { anchors.fill: parent; anchors.margins: -3; radius: parent.radius + 3; color: "transparent"; border.width: 3; border.color: Theme.primarySoft; z: -1 }

    RowLayout {
        id: row
        anchors.centerIn: parent
        spacing: 8
        Rectangle {
            width: 26; height: 26; radius: 13
            color: Theme.primarySoft
            Icon { anchors.centerIn: parent; glyph: "download"; size: 14; color: Theme.primary }
        }
        Text {
            text: "새 버전 <b>v" + banner.version + "</b>이 나왔어요"
            textFormat: Text.StyledText
            color: Theme.text
            font.family: Theme.font
            font.pixelSize: 13
            Layout.rightMargin: 4
        }
        AppButton { text: "변경 내용"; variant: "ghost"; size: "small"; onClicked: banner.notesClicked() }
        AppButton { text: "업데이트"; variant: "primary"; size: "small"; onClicked: banner.updateClicked() }
        AppButton { glyph: "x"; variant: "ghost"; size: "small"; onClicked: banner.shown = false }
    }
}
