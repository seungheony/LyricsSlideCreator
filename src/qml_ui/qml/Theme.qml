pragma Singleton
import QtQuick

// 디자인 토큰. 시스템 다크 모드를 따라간다.
QtObject {
    readonly property bool dark: Qt.styleHints.colorScheme === Qt.ColorScheme.Dark

    readonly property color primary: "#00CD3C"
    readonly property color primarySoft: Qt.rgba(0, 0.804, 0.235, dark ? 0.16 : 0.12)
    readonly property color primarySoftHover: Qt.rgba(0, 0.804, 0.235, dark ? 0.24 : 0.2)
    // 연한 초록 바탕(primarySoft) 위 글자색. 라이트 모드에서는 읽히도록 조금 진하게
    readonly property color primaryText: dark ? primary : "#00782A"
    // 입력칸 포커스 테두리: 쨍하지 않게 한 톤 낮춘 초록
    readonly property color focusBorder: Qt.rgba(0, 0.804, 0.235, 0.5)
    readonly property color bg: dark ? "#101215" : "#F6F7F9"
    readonly property color surface: dark ? "#1A1D21" : "#FFFFFF"
    // surface와 같은 색의 완전 투명. 'transparent'(투명한 검정)와 보간하면 중간에 회색으로 번쩍인다
    readonly property color surfaceClear: Qt.rgba(surface.r, surface.g, surface.b, 0)
    readonly property color surface2Clear: Qt.rgba(surface2.r, surface2.g, surface2.b, 0)
    readonly property color surface2: dark ? "#23272C" : "#F1F3F5"
    // 로딩 자리 표시(스켈레톤). 라이트 모드에서 surface2는 흰 바탕에 거의 안 보인다
    readonly property color skeleton: dark ? "#23272C" : "#E5E8EB"
    readonly property color border: dark ? "#2C3137" : "#E5E8EB"
    readonly property color text: dark ? "#F2F4F6" : "#191F28"
    readonly property color text2: dark ? "#B0B8C1" : "#4E5968"
    readonly property color text3: dark ? "#8B95A1" : "#68727F"
    readonly property color danger: "#F04452"
    // 주의 (PPT 줄바꿈 경고 등)
    readonly property color warning: dark ? "#FFB547" : "#9A5B00"
    readonly property color warningSoft: Qt.rgba(1, 0.65, 0, dark ? 0.16 : 0.14)
    readonly property color slideWarning: "#FFB547"    // 슬라이드 카드(항상 어두운 바탕) 위
    readonly property color slideBg: dark ? "#0A0B0D" : "#14171C"
    // 다크 모드에서 슬라이드 카드와 바탕이 구분되도록 옅은 테두리
    readonly property color slideBorder: dark ? Qt.rgba(1, 1, 1, 0.08) : "transparent"
    readonly property color toastBg: "#191F28"

    readonly property int radius: 14
    readonly property int radiusSm: 10
    readonly property string font: "Pretendard"
    // 단축키 표기: macOS는 ⌘, 그 외는 Ctrl+
    readonly property string mod: Qt.platform.os === "osx" ? "⌘" : "Ctrl+"
    readonly property string undoKey: Qt.platform.os === "osx" ? "⌘Z" : "Ctrl+Z"
    readonly property string redoKey: Qt.platform.os === "osx" ? "⇧⌘Z" : "Ctrl+Y"

    readonly property int fast: 150
    readonly property int normal: 280
}
