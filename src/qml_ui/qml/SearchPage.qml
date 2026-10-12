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
    property string loadingId: ""     // 가사를 불러오는 중인 곡
    property int token: 0             // 오래된 검색 응답 무시용

    signal songClicked(var song)

    function focusSearch() { input.forceActiveFocus() }

    function doSearch() {
        const keyword = input.text.trim()
        if (!keyword) return
        token++
        hasResults = true
        searching = true
        results = []
        emptyText = ""
        backend.search(token, keyword)
    }

    Connections {
        target: backend
        function onSearchFinished(t, json) {
            if (t !== page.token) return
            page.searching = false
            page.results = JSON.parse(json)
            page.emptyText = page.results.length ? "" : "검색 결과가 없습니다"
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
        Rectangle {
            Layout.alignment: Qt.AlignHCenter
            Layout.preferredWidth: page.hasResults ? 0 : 56
            Layout.preferredHeight: page.hasResults ? 0 : 56
            Layout.bottomMargin: page.hasResults ? 0 : 18
            radius: 16
            color: Theme.primary
            opacity: page.hasResults ? 0 : 1
            Behavior on Layout.preferredWidth { NumberAnimation { duration: 450; easing.type: Easing.OutCubic } }
            Behavior on Layout.preferredHeight { NumberAnimation { duration: 450; easing.type: Easing.OutCubic } }
            Behavior on Layout.bottomMargin { NumberAnimation { duration: 450; easing.type: Easing.OutCubic } }
            Behavior on opacity { NumberAnimation { duration: 300 } }
            Icon { anchors.centerIn: parent; glyph: "music"; size: 28; color: "white"; visible: parent.width > 20 }
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
            Layout.fillWidth: true
            Layout.topMargin: page.hasResults ? 14 : 28
            Layout.preferredHeight: 58
            radius: 16
            color: Theme.surface
            border.width: 1.5
            border.color: input.activeFocus ? Theme.primary : Theme.border
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
                    placeholderText: "노래 제목 또는 가수 이름"
                    placeholderTextColor: Theme.text3
                    color: Theme.text
                    font.family: Theme.font
                    font.pixelSize: 16
                    background: null
                    selectByMouse: true
                    focus: true
                    onAccepted: page.doSearch()
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

        // ── 결과 ──
        Item {
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
                        Rectangle { width: 52; height: 52; radius: 8; color: Theme.surface2 }
                        Column {
                            spacing: 8
                            anchors.verticalCenter: parent.verticalCenter
                            Rectangle { width: 180 + (index * 37) % 90; height: 12; radius: 6; color: Theme.surface2 }
                            Rectangle { width: 100 + (index * 23) % 60; height: 12; radius: 6; color: Theme.surface2 }
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
                Text { text: page.emptyText; color: Theme.text3; font.family: Theme.font; font.pixelSize: 14 }
            }

            ListView {
                id: list
                anchors.fill: parent
                visible: !page.searching
                model: page.results
                spacing: 4
                clip: true
                bottomMargin: 40
                boundsBehavior: Flickable.StopAtBounds
                ScrollBar.vertical: ScrollBar {}

                delegate: Rectangle {
                    id: row
                    required property var modelData
                    required property int index
                    readonly property bool loading: page.loadingId === modelData.song_id

                    width: ListView.view.width
                    height: 72
                    radius: Theme.radius
                    color: hover.containsMouse ? Theme.surface : "transparent"
                    Behavior on color { ColorAnimation { duration: Theme.fast } }

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
                            PauseAnimation { duration: row.index * 35 }
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
                            placeholder: Theme.surface2
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 3
                            Text {
                                Layout.fillWidth: true
                                text: row.modelData.title
                                color: Theme.text
                                font.family: Theme.font
                                font.pixelSize: 15
                                font.weight: Font.DemiBold
                                elide: Text.ElideRight
                            }
                            Text {
                                Layout.fillWidth: true
                                text: row.modelData.artist + " · " + row.modelData.album
                                color: Theme.text3
                                font.family: Theme.font
                                font.pixelSize: 13
                                elide: Text.ElideRight
                            }
                        }
                        Icon {
                            glyph: row.loading ? "loader" : "chevron-right"
                            color: Theme.text3
                            opacity: row.loading || hover.containsMouse ? 1 : 0
                            Behavior on opacity { NumberAnimation { duration: Theme.fast } }
                            RotationAnimation on rotation {
                                running: row.loading
                                from: 0; to: 360; duration: 800; loops: Animation.Infinite
                                onStopped: parent.rotation = 0
                            }
                        }
                    }

                    MouseArea {
                        id: hover
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
