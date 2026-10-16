import QtQuick

// 곡 찾기 서랍의 행(멜론 검색 결과·저장한 곡의 프리셋)을 콘티로 끌어다 놓는 영역.
// 누르고 8px 넘게 움직이면 끌기로 보고 dragHost(EditorPage)에 알린다. 끌지 않고 떼면 tapped()(평소의 누르기).
// 목록이 끌기를 스크롤로 가로채지 않게 preventStealing (스크롤은 휠·스크롤바로).
MouseArea {
    id: area
    property var dragHost: null       // beginSongDrag / moveSongDrag / endSongDrag / cancelSongDrag
    property var payload: null        // { kind: "song", song } | { kind: "preset", song, preset }. null이면 끌 수 없다
    property string dragLabel: ""
    property bool dragging: false
    property point pressPos: Qt.point(0, 0)

    signal tapped()

    hoverEnabled: true
    preventStealing: true
    cursorShape: dragging ? Qt.ClosedHandCursor : Qt.PointingHandCursor

    onPressed: (mouse) => { pressPos = Qt.point(mouse.x, mouse.y); dragging = false }
    onPositionChanged: (mouse) => {
        if (!pressed || !dragHost || !payload) return
        const p = mapToItem(null, mouse.x, mouse.y)
        if (dragging) dragHost.moveSongDrag(p.x, p.y)
        else if (Math.hypot(mouse.x - pressPos.x, mouse.y - pressPos.y) > 8) {
            dragging = true
            dragHost.beginSongDrag(payload, dragLabel, p.x, p.y)
        }
    }
    onReleased: (mouse) => {
        if (!dragging) { tapped(); return }
        dragging = false
        const p = mapToItem(null, mouse.x, mouse.y)
        dragHost.endSongDrag(p.x, p.y)
    }
    onCanceled: {
        if (!dragging) return
        dragging = false
        dragHost.cancelSongDrag()
    }
}
