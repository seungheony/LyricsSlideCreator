import QtQuick
import QtQuick.Controls.impl

// assets/icons/<glyph>.svg 를 원하는 색으로 칠해서 표시
IconImage {
    property string glyph
    property int size: 18
    source: glyph ? assetsUrl + "/icons/" + glyph + ".svg" : ""
    sourceSize: Qt.size(size, size)
    width: size
    height: size
}
