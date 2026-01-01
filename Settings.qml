import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Widgets

ColumnLayout {
    id: root
    property var pluginApi: null

    anchors.fill: parent
    anchors.margins: Style.marginM
    spacing: Style.marginM

    function _defaults() {
        if (!pluginApi) return {}
        if (!pluginApi.manifest) return {}
        if (!pluginApi.manifest.metadata) return {}
        return pluginApi.manifest.metadata.defaultSettings || {}
    }

    function _getSetting(key, fallback) {
        if (pluginApi && pluginApi.pluginSettings && pluginApi.pluginSettings[key] !== undefined && pluginApi.pluginSettings[key] !== null)
            return pluginApi.pluginSettings[key]
        var d = _defaults()
        if (d && d[key] !== undefined && d[key] !== null)
            return d[key]
        return fallback
    }

    // Local editable state
    property int editPollMs: 2000
    property string editProfilesCsv: "lazy"
    property bool editUseEctool: false
    property string editTempSensor: "cpu@4c"
    property bool editShowRpmInBar: true
    property int editHistoryPoints: 60

    property bool _inited: false

    function _init() {
        if (_inited || !pluginApi) return
        editPollMs = _getSetting("pollMs", 2000)
        editProfilesCsv = _getSetting("profilesCsv", "lazy")
        editUseEctool = _getSetting("useEctool", false)
        editTempSensor = _getSetting("tempSensor", "cpu@4c")
        editShowRpmInBar = _getSetting("showRpmInBar", true)
        editHistoryPoints = _getSetting("historyPoints", 60)
        _inited = true
    }

    onPluginApiChanged: _init()
    Component.onCompleted: _init()

    NText {
        text: "Framework Fan Control"
        pointSize: Style.fontSizes.l
        opacity: 0.95
    }

    NText {
        text: "Controls profiles via: fw-fanctrl use <profile>\nReads status via: fw-fanctrl print\nOptional RPM/sensors via: sudo -n ectool ..."
        pointSize: Style.fontSizes.s
        opacity: 0.75
        wrapMode: Text.Wrap
    }

    NDivider { Layout.fillWidth: true }

    NTextInput {
        Layout.fillWidth: true
        label: "Profiles (comma separated)"
        description: "These become buttons in the panel."
        placeholderText: "lazy, balanced, performance"
        text: root.editProfilesCsv
        onTextChanged: root.editProfilesCsv = text
    }

    NSpinBox {
        Layout.fillWidth: true
        label: "Poll interval (ms)"
        description: "How often to refresh the readings."
        from: 500
        to: 10000
        stepSize: 250
        value: root.editPollMs
        onValueChanged: root.editPollMs = value
    }

    NSpinBox {
        Layout.fillWidth: true
        label: "Graph history points"
        description: "How many samples to keep for the graphs."
        from: 10
        to: 300
        stepSize: 5
        value: root.editHistoryPoints
        onValueChanged: root.editHistoryPoints = value
    }

    NToggle {
        Layout.fillWidth: true
        label: "Use ectool for RPM + sensor temp"
        description: "Requires privileges. Plugin runs: sudo -n ectool …"
        checked: root.editUseEctool
        onCheckedChanged: root.editUseEctool = checked
    }

    NTextInput {
        Layout.fillWidth: true
        enabled: root.editUseEctool
        label: "Temp sensor name (ectool temps all)"
        description: "Example: cpu@4c or apu_f75303@4d"
        placeholderText: "cpu@4c"
        text: root.editTempSensor
        onTextChanged: root.editTempSensor = text
    }

    NToggle {
        Layout.fillWidth: true
        label: "Show RPM in bar widget"
        description: "Only applies when ectool is enabled and working."
        checked: root.editShowRpmInBar
        onCheckedChanged: root.editShowRpmInBar = checked
    }

    Item { Layout.fillHeight: true }

    // Called by Noctalia settings Apply button
    function saveSettings() {
        if (!pluginApi) return
        pluginApi.pluginSettings.pollMs = root.editPollMs
        pluginApi.pluginSettings.profilesCsv = root.editProfilesCsv
        pluginApi.pluginSettings.useEctool = root.editUseEctool
        pluginApi.pluginSettings.tempSensor = root.editTempSensor
        pluginApi.pluginSettings.showRpmInBar = root.editShowRpmInBar
        pluginApi.pluginSettings.historyPoints = root.editHistoryPoints
        pluginApi.saveSettings()
    }
}
