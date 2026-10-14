import QtQuick
import QtQuick.Controls.Basic
import "."

// 입력칸 오른쪽 클릭 메뉴 (한국어, Theme를 따름). Qt 기본 메뉴는 영어이고 Undo가 앱의 되돌리기 기록과 따로 동작한다.
// 사용: ContextMenu.menu: AppTextMenu { editor: 입력칸 }
// useHistory: true면 되돌리기·다시 실행을 입력칸 자체가 아니라 앱의 히스토리(canUndo·canRedo·undo()·redo())로 처리한다 (가사 칸)
// beforePaste: 붙여넣기 직전에 부를 함수 (붙여 넣은 내용을 히스토리의 한 단계로 남기려는 준비)
Menu {
    id: menu

    required property Item editor
    property bool useHistory: false
    property bool canUndo: false
    property bool canRedo: false
    property var undo: null
    property var redo: null
    property var beforePaste: null

    readonly property bool editable: !editor.readOnly
    readonly property bool hasSelection: editor.selectedText !== ""

    popupType: Popup.Item
    margins: 8
    padding: 6
    implicitWidth: 180

    background: Rectangle {
        radius: 10
        color: Theme.surface
        border.width: 1
        border.color: Theme.border
    }

    component Entry: MenuItem {
        id: entry
        implicitHeight: 32
        leftPadding: 12
        rightPadding: 12
        contentItem: Text {
            text: entry.text
            font.family: Theme.font
            font.pixelSize: 13
            color: entry.enabled ? Theme.text : Theme.text3
            verticalAlignment: Text.AlignVCenter
        }
        background: Rectangle {
            radius: 6
            color: entry.highlighted ? Theme.surface2 : "transparent"
        }
    }

    component Divider: MenuSeparator {
        contentItem: Rectangle { implicitHeight: 1; color: Theme.border }
        topPadding: 4
        bottomPadding: 4
    }

    Entry {
        visible: menu.editable
        height: visible ? implicitHeight : 0
        text: "되돌리기"
        enabled: menu.useHistory ? menu.canUndo : menu.editor.canUndo
        onTriggered: menu.useHistory ? menu.undo() : menu.editor.undo()
    }
    Entry {
        visible: menu.editable
        height: visible ? implicitHeight : 0
        text: "다시 실행"
        enabled: menu.useHistory ? menu.canRedo : menu.editor.canRedo
        onTriggered: menu.useHistory ? menu.redo() : menu.editor.redo()
    }
    Divider { visible: menu.editable; height: visible ? implicitHeight : 0 }
    Entry {
        visible: menu.editable
        height: visible ? implicitHeight : 0
        text: "잘라내기"
        enabled: menu.hasSelection
        onTriggered: menu.editor.cut()
    }
    Entry {
        text: "복사"
        enabled: menu.hasSelection
        onTriggered: menu.editor.copy()
    }
    Entry {
        visible: menu.editable
        height: visible ? implicitHeight : 0
        text: "붙여넣기"
        enabled: menu.editor.canPaste
        onTriggered: {
            if (menu.beforePaste) menu.beforePaste()
            menu.editor.paste()
        }
    }
    Entry {
        visible: menu.editable
        height: visible ? implicitHeight : 0
        text: "삭제"
        enabled: menu.hasSelection
        onTriggered: menu.editor.remove(menu.editor.selectionStart, menu.editor.selectionEnd)
    }
    Divider {}
    Entry {
        text: "모두 선택"
        enabled: menu.editor.length > 0
        onTriggered: menu.editor.selectAll()
    }
}
