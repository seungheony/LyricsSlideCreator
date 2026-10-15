import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import "."

// 곡 찾기 서랍: 편집 화면의 '곡 추가'(⌘K/Ctrl+K)로 콘티 패널 오른쪽에서 열려 편집 영역을 덮는다.
// 멜론 | 보관함 | 직접 입력 탭에서 곡을 연달아 담는다. 서랍이 열려 있는 동안 담은 곡은 콘티에 쌓이기만 하고,
// 닫을 때 이번에 처음 담은 곡을 연다 (EditorPage.closeDrawer).
// 보관함·직접 입력 탭은 아직 자리만 있다: 누르면 지금의 보관함 창(PresetDialog)과 직접 입력 흐름을 부른다
Rectangle {
    id: drawer

    property bool opened: false
    property bool emptySetlist: false     // 콘티가 비었다 (머리말을 '어떤 곡으로 시작할까요?'로)
    property var setlist: []
    property var loadingIds: []
    property var addedIds: []             // 이번에 서랍을 연 뒤 담은 곡
    property alias search: searchPanel

    signal closeRequested()
    signal songClicked(var song)
    signal presetsRequested(var song)
    signal libraryRequested()
    signal manualRequested(var info)

    function focusSearch() { searchPanel.focusSearch() }

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
                Text {
                    text: drawer.emptySetlist ? "어떤 곡으로 시작할까요?" : "곡 추가"
                    color: Theme.text
                    font.family: Theme.font
                    font.pixelSize: drawer.emptySetlist ? 19 : 17
                    font.weight: Font.Bold
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

        // ── 탭: 멜론 | 보관함 | 직접 입력 ──
        Rectangle {
            Layout.fillWidth: true
            Layout.leftMargin: 20
            Layout.rightMargin: 20
            Layout.topMargin: 12
            Layout.bottomMargin: 12
            implicitHeight: 38
            radius: 10
            color: Theme.surface2
            RowLayout {
                anchors.fill: parent
                anchors.margins: 3
                spacing: 4
                Repeater {
                    model: [{ key: "melon", label: "멜론" }, { key: "library", label: "보관함" }, { key: "manual", label: "직접 입력" }]
                    delegate: Button {
                        id: tab
                        required property var modelData
                        readonly property bool on: modelData.key === "melon"
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        text: modelData.label
                        hoverEnabled: true
                        focusPolicy: Qt.TabFocus
                        Keys.onReturnPressed: click()
                        Keys.onEnterPressed: click()
                        Accessible.role: Accessible.PageTab
                        Accessible.name: modelData.label
                        Accessible.selected: on
                        HoverHandler { cursorShape: Qt.PointingHandCursor }
                        onClicked: {
                            if (modelData.key === "library") drawer.libraryRequested()
                            else if (modelData.key === "manual") drawer.manualRequested({ title: "", artist: "" })
                            else drawer.focusSearch()
                        }
                        contentItem: Text {
                            text: tab.text
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                            color: tab.on || tab.hovered ? Theme.text : Theme.text3
                            font.family: Theme.font
                            font.pixelSize: 13
                            font.weight: tab.on ? Font.Bold : Font.Normal
                        }
                        background: Rectangle {
                            radius: 8
                            color: tab.on ? Theme.surface : "transparent"
                            border.width: tab.visualFocus ? 2 : tab.on ? 1 : 0
                            border.color: tab.visualFocus ? Theme.primary : Theme.border
                        }
                    }
                }
            }
        }

        SearchPanel {
            id: searchPanel
            objectName: "searchPanel"
            Layout.fillWidth: true
            Layout.fillHeight: true
            setlist: drawer.setlist
            loadingIds: drawer.loadingIds
            addedIds: drawer.addedIds
            onSongClicked: (song) => drawer.songClicked(song)
            onPresetsRequested: (song) => drawer.presetsRequested(song)
            onManualRequested: (info) => drawer.manualRequested(info)
        }

        // ── 아래 막대 ──
        Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: Theme.border }
        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: 64
            Layout.leftMargin: 20
            Layout.rightMargin: 20
            spacing: 10
            Text {
                Layout.fillWidth: true
                text: drawer.addedIds.length ? "이번에 <b>" + drawer.addedIds.length + "곡</b> 담았어요" : "곡을 누르면 콘티 끝에 담아요"
                textFormat: Text.StyledText
                color: Theme.text2
                font.family: Theme.font
                font.pixelSize: 13
                elide: Text.ElideRight
            }
            AppButton {
                id: doneButton
                objectName: "drawerDoneButton"
                text: "편집으로"
                variant: "primary"
                onClicked: drawer.closeRequested()
                AppToolTip { visible: doneButton.hovered; delay: 600; text: "서랍을 닫고 담은 곡을 편집해요 (Esc)" }
            }
        }
    }
}
