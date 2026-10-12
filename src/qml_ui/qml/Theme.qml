pragma Singleton
import QtQuick

// 디자인 토큰. 시스템 다크 모드를 따라간다.
QtObject {
    readonly property bool dark: Qt.styleHints.colorScheme === Qt.ColorScheme.Dark

    readonly property color primary: "#00CD3C"
    readonly property color primarySoft: Qt.rgba(0, 0.804, 0.235, dark ? 0.16 : 0.12)
    readonly property color primarySoftHover: Qt.rgba(0, 0.804, 0.235, dark ? 0.24 : 0.2)
    // 연한 초록 바탕(primarySoft) 위 글자색. 라이트 모드에서는 읽히도록 조금 진하게
    readonly property color primaryText: dark ? primary : "#00912C"
    // 입력칸 포커스 테두리: 쨍하지 않게 한 톤 낮춘 초록
    readonly property color focusBorder: Qt.rgba(0, 0.804, 0.235, 0.5)
    readonly property color bg: dark ? "#101215" : "#F6F7F9"
    readonly property color surface: dark ? "#1A1D21" : "#FFFFFF"
    readonly property color surface2: dark ? "#23272C" : "#F1F3F5"
    readonly property color border: dark ? "#2C3137" : "#E5E8EB"
    readonly property color text: dark ? "#F2F4F6" : "#191F28"
    readonly property color text2: dark ? "#B0B8C1" : "#4E5968"
    readonly property color text3: dark ? "#6B7684" : "#8B95A1"
    readonly property color danger: "#F04452"
    // 주의 (PPT 줄바꿈 경고 등)
    readonly property color warning: dark ? "#FFB547" : "#9A5B00"
    readonly property color warningSoft: Qt.rgba(1, 0.65, 0, dark ? 0.16 : 0.14)
    readonly property color slideWarning: "#FFB547"    // 슬라이드 카드(항상 어두운 바탕) 위
    readonly property color slideBg: dark ? "#0A0B0D" : "#14171C"
    readonly property color toastBg: "#191F28"

    readonly property int radius: 14
    readonly property int radiusSm: 10
    readonly property string font: "Pretendard"
    // 단축키 표기: macOS는 ⌘, 그 외는 Ctrl+
    readonly property string mod: Qt.platform.os === "osx" ? "⌘" : "Ctrl+"

    readonly property int fast: 150
    readonly property int normal: 280
}
