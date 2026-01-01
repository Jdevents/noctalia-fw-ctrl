import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Widgets

Rectangle {
    id: root
    property var pluginApi: null
    property string widgetId: ""
    property string section: ""

    implicitWidth: row.implicitWidth + Style.marginM * 2
    implicitHeight: Style.barHeight

    color: Style.capsuleColor
    radius: Style.radiusM

    RowLayout {
        id: row
        anchors.centerIn: parent
        spacing: Style.marginS

        NIcon {
            icon: "heart"
            color: Color.mPrimary
        }

        NText {
            text: "My First"
            color: Color.mOnSurface
            pointSize: Style.fontSizeS
        }
    }

}