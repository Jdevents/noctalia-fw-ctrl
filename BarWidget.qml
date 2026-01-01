import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Widgets

Rectangle {
    id: root

    // Injected by Noctalia
    property var pluginApi: null

    // Required properties for bar widgets
    property ShellScreen screen
    property string widgetId: ""
    property string section: ""

    // Settings (loaded from plugin settings + manifest defaults)
    property int pollMs: 2000
    property bool useEctool: false
    property bool showRpmInBar: true
    property string tempSensor: "cpu@4c"

    property bool _inited: false

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

    function _init() {
        if (_inited || !pluginApi) return
        pollMs = _getSetting("pollMs", 2000)
        useEctool = _getSetting("useEctool", false)
        showRpmInBar = _getSetting("showRpmInBar", true)
        tempSensor = _getSetting("tempSensor", "cpu@4c")
        _inited = true

        // Kick an immediate poll so the widget populates quickly
        Qt.callLater(function() {
            fwPrintProc.running = true
            if (useEctool) {
                ectoolRpmProc.command = ["sudo", "-n", "ectool", "pwmgetfanrpm", "all"]
                ectoolRpmProc.running = true
                ectoolTempProc.command = ["sudo", "-n", "ectool", "temps", "all"]
                ectoolTempProc.running = true
            }
        })
    }

    onPluginApiChanged: _init()
    Component.onCompleted: _init()

    // Live values
    property string profile: "?"
    property int fanPct: -1
    property real tempC: NaN
    property int fan0Rpm: -1
    property int fan1Rpm: -1
    property string lastError: ""

    implicitWidth: row.implicitWidth + Style.marginM * 2
    implicitHeight: Style.barHeight
    radius: Style.capsuleRadius
    color: Style.capsuleColor
    border.color: Style.capsuleBorderColor
    border.width: Style.capsuleBorderWidth

    function parseFwPrint(text) {
        var t = (text || "").trim()

        var mProfile = t.match(/Strategy:\s*'([^']+)'/)
        if (mProfile) profile = mProfile[1]

        var mSpeed = t.match(/Speed:\s*([0-9]+)%/)
        if (mSpeed) fanPct = parseInt(mSpeed[1])

        var mTemp = t.match(/Temp:\s*([0-9.]+)\s*°C/)
        if (mTemp) tempC = parseFloat(mTemp[1])
    }

    function parseEctoolRpm(text) {
        var lines = (text || "").split("\n")
        var r0 = -1, r1 = -1
        for (var i = 0; i < lines.length; i++) {
            var m = lines[i].match(/Fan\s+(\d+)\s+RPM:\s+(\d+)/)
            if (!m) continue
            var idx = parseInt(m[1])
            var rpm = parseInt(m[2])
            if (idx === 0) r0 = rpm
            if (idx === 1) r1 = rpm
        }
        fan0Rpm = r0
        fan1Rpm = r1
    }

    function parseEctoolTemps(text) {
        var lines = (text || "").split("\n")
        for (var i = 0; i < lines.length; i++) {
            if (!lines[i].startsWith(tempSensor)) continue
            var m = lines[i].match(/\(=\s*([0-9]+)\s*C\)/)
            if (m) tempC = parseFloat(m[1])
            return
        }
    }

    Process {
        id: fwPrintProc
        command: ["fw-fanctrl", "print"]

        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: root.parseFwPrint(this.text)
        }
        stderr: StdioCollector {
            waitForEnd: true
            onStreamFinished: root.lastError = (this.text || "").trim()
        }
        onExited: running = false
    }

    Process {
        id: ectoolRpmProc
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: root.parseEctoolRpm(this.text)
        }
        stderr: StdioCollector { waitForEnd: true }
        onExited: running = false
    }

    Process {
        id: ectoolTempProc
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: root.parseEctoolTemps(this.text)
        }
        stderr: StdioCollector { waitForEnd: true }
        onExited: running = false
    }

    Timer {
        interval: pollMs
        running: true
        repeat: true
        onTriggered: {
            fwPrintProc.running = true
            if (useEctool) {
                ectoolRpmProc.command = ["sudo", "-n", "ectool", "pwmgetfanrpm", "all"]
                ectoolRpmProc.running = true
                ectoolTempProc.command = ["sudo", "-n", "ectool", "temps", "all"]
                ectoolTempProc.running = true
            }
        }
    }

    RowLayout {
        id: row
        anchors.centerIn: parent
        spacing: Style.marginS

        NIcon {
            icon: "fan"
            Layout.preferredWidth: 16
            Layout.preferredHeight: 16
            opacity: 0.9
            color: Color.mPrimary
        }

        NText {
            text: profile + " • " + (isNaN(tempC) ? "—°" : (tempC.toFixed(0) + "°")) + " • " + (fanPct < 0 ? "—%" : (fanPct + "%"))
            pointSize: Style.fontSizes.s
            opacity: 0.95
        }

        NText {
            visible: showRpmInBar && useEctool && fan0Rpm > 0
            text: "• " + fan0Rpm + "/" + (fan1Rpm > 0 ? fan1Rpm : "—") + " rpm"
            pointSize: Style.fontSizes.s
            opacity: 0.85
        }
    }

    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor

        onEntered: root.color = Qt.lighter(Style.capsuleColor, 1.08)
        onExited: root.color = Style.capsuleColor

        onClicked: {
            if (!pluginApi) return
            pluginApi.openPanel(screen)
        }
    }
}
