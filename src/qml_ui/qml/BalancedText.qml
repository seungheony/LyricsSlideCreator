import QtQuick

// 여러 줄로 감기는 안내 글 (툴팁·알림·확인창 등). 글은 text 대신 source에 넣는다.
// - 한 줄에 다 들어가면 그대로 (폭 = 글 폭)
// - 넘치면 문장 끝('. ' '? ' '! ')과 구분점(' · ')에서 먼저 줄을 바꾼다 (breakSentences)
// - 그래도 여러 줄이면 줄 수는 그대로 두고 가장 좁은 폭을 찾아 줄 길이를 고르게 한다
//   (마지막 줄에 한두 단어만 남지 않게). 레이아웃 안에서는 Layout.preferredWidth: fitWidth로 쓴다
Text {
    id: t
    property string source: ""
    property real maxWidth: 300
    property bool breakSentences: true
    readonly property real fitWidth: _fit
    property real _fit: maxWidth
    property string _shown: source

    text: _shown
    width: _fit
    wrapMode: Text.Wrap

    Text {
        id: probe
        visible: false
        font: t.font
        textFormat: t.textFormat
        wrapMode: t.wrapMode
        lineHeight: t.lineHeight
        lineHeightMode: t.lineHeightMode
    }

    function linesAt(w) { probe.width = w; return probe.lineCount }

    function refit() {
        if (maxWidth <= 0) return
        let str = source
        probe.text = str
        probe.width = 100000
        if (probe.implicitWidth <= maxWidth) {
            _shown = str
            _fit = Math.ceil(probe.implicitWidth)
            return
        }
        if (breakSentences) {
            const nl = textFormat === Text.StyledText || textFormat === Text.RichText ? "<br>" : "\n"
            str = str.replace(/([.?!]) (?=\S)/g, "$1" + nl).replace(/ · /g, nl)
            probe.text = str
        }
        const n = linesAt(maxWidth)
        let lo = Math.floor(maxWidth * 0.4), hi = maxWidth
        while (hi - lo > 2) {
            const mid = (lo + hi) / 2
            if (linesAt(mid) > n) lo = mid
            else hi = mid
        }
        _shown = str
        _fit = Math.ceil(hi)
    }

    onSourceChanged: refit()
    onMaxWidthChanged: refit()
    onFontChanged: refit()
    Component.onCompleted: refit()
}
