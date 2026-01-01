import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Widgets
import qs.Services.UI

Item {
    id: root

    // Plugin API (injected by PluginPanelSlot)
    property var pluginApi: null

    // SmartPanel properties (required for panel behavior)
    readonly property var geometryPlaceholder: panelContainer
    readonly property bool allowAttach: true
    readonly property bool allowPin: true
    readonly property bool allowMove: true
    readonly property bool allowResize: true
    readonly property bool allowDecorations: true

    property real contentPreferredWidth: 680 * Style.uiScaleRatio
    property real contentPreferredHeight: 250 * Style.uiScaleRatio

    // Settings (loaded from plugin settings + manifest defaults)
    property int pollMs: 2000
    property bool useEctool: false
    property string tempSensor: "cpu@4c"
    property int historyPoints: 60
    property string profilesCsv: "lazy"

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
        tempSensor = _getSetting("tempSensor", "cpu@4c")
        historyPoints = _getSetting("historyPoints", 60)
        profilesCsv = _getSetting("profilesCsv", "lazy")
        _inited = true

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

    // History arrays
    property var tempHistory: []
    property var pctHistory: []
    property var rpm0History: []
    property var rpm1History: []

    function pushHistory(arr, val) {
        arr.push(val)
        if (arr.length > historyPoints) arr.shift()
    }

    function profilesList() {
        var out = []
        var parts = (profilesCsv || "").split(",")
        for (var i = 0; i < parts.length; i++) {
            var p = String(parts[i]).trim()
            if (p.length) out.push(p)
        }
        return out
    }

    function parseFwPrint(text) {
        var t = (text || "").trim()

        var mProfile = t.match(/Strategy:\s*'([^']+)'/)
        if (mProfile) profile = mProfile[1]

        var mSpeed = t.match(/Speed:\s*([0-9]+)%/)
        if (mSpeed) fanPct = parseInt(mSpeed[1])

        var mTemp = t.match(/Temp:\s*([0-9.]+)\s*°C/)
        if (mTemp) tempC = parseFloat(mTemp[1])

        if (!isNaN(tempC)) pushHistory(tempHistory, tempC)
        if (fanPct >= 0) pushHistory(pctHistory, fanPct)

        tempGraph.requestPaint()
        pctGraph.requestPaint()
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

        if (r0 > 0) pushHistory(rpm0History, r0)
        if (r1 > 0) pushHistory(rpm1History, r1)

        rpmGraph.requestPaint()
    }

    function parseEctoolTemps(text) {
        var lines = (text || "").split("\n")
        for (var i = 0; i < lines.length; i++) {
            if (!lines[i].startsWith(tempSensor)) continue
            var m = lines[i].match(/\(=\s*([0-9]+)\s*C\)/)
            if (m) {
                tempC = parseFloat(m[1])
                if (!isNaN(tempC)) pushHistory(tempHistory, tempC)
                tempGraph.requestPaint()
            }
            return
        }
    }

    Process {
        id: fwUseProc
        stdout: StdioCollector { waitForEnd: true }
        stderr: StdioCollector { waitForEnd: true }
        onExited: running = false
    }

    function setProfile(p) {
        if (!p || !String(p).trim().length) return
        var prof = String(p).trim()
        fwUseProc.command = ["fw-fanctrl", "use", prof]
        fwUseProc.running = true
        ToastService.showNotice("Fan profile: " + prof)
        fwPrintProc.running = true
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

    // UI
    Rectangle {
        id: panelContainer
        anchors.fill: parent
        color: Color.transparent

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Style.marginM
            spacing: Style.marginM

            RowLayout {
                Layout.fillWidth: true
                spacing: Style.marginS

                NIcon { icon: "fan"; Layout.preferredWidth: 18; Layout.preferredHeight: 18; color: Color.mPrimary }

                NText {
                    Layout.fillWidth: true
                    text: "Profile: " + profile
                    pointSize: Style.fontSizes.m
                    opacity: 0.95
                }

                Rectangle {
                    width: 28; height: 28; radius: Style.radiusS
                    color: Qt.rgba(1, 1, 1, 0.08)
                    border.width: 1
                    border.color: Qt.rgba(1, 1, 1, 0.10)

                    NText { anchors.centerIn: parent; text: "×"; pointSize: Style.fontSizes.m; opacity: 0.9 }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: { if (pluginApi) pluginApi.closePanel(screen) }
                    }
                }
            }

            NText {
                Layout.fillWidth: true
                text: "Temp: " + (isNaN(tempC) ? "—" : tempC.toFixed(0)) + "°C   •   Fan: " + (fanPct < 0 ? "—" : fanPct) + "%"
                      + (useEctool ? ("   •   RPM: " + (fan0Rpm > 0 ? fan0Rpm : "—") + " / " + (fan1Rpm > 0 ? fan1Rpm : "—")) : "")
                pointSize: Style.fontSizes.s
                opacity: 0.85
            }

            // Profile buttons
            ColumnLayout {
                Layout.fillWidth: true
                spacing: Style.marginS

                NText { text: "Profiles"; pointSize: Style.fontSizes.s; opacity: 0.8 }

                Flow {
                    Layout.fillWidth: true
                    spacing: Style.marginS

                    Repeater {
                        model: profilesList()
                        delegate: Rectangle {
                            height: 28
                            radius: Style.radiusS
                            color: (modelData === root.profile) ? Qt.rgba(1, 1, 1, 0.16) : Qt.rgba(1, 1, 1, 0.08)
                            border.width: 1
                            border.color: Qt.rgba(1, 1, 1, 0.10)

                            implicitWidth: label.implicitWidth + 20

                            NText { id: label; anchors.centerIn: parent; text: modelData; pointSize: Style.fontSizes.s; opacity: 0.95 }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.setProfile(modelData)
                            }
                        }
                    }
                }
            }

            // Graphs
            RowLayout {
                Layout.fillWidth: true
                spacing: Style.marginM

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 4
                    NText { text: "Temp (°C)"; pointSize: Style.fontSizes.s; opacity: 0.8 }
                    Canvas {
                        id: tempGraph
                        Layout.fillWidth: true
                        Layout.preferredHeight: 70
                        onPaint: {
                            var ctx = getContext("2d")
                            ctx.clearRect(0, 0, width, height)
                            ctx.globalAlpha = 0.18
                            ctx.fillStyle = "white"
                            ctx.fillRect(0, 0, width, height)
                            ctx.globalAlpha = 1.0

                            var values = root.tempHistory
                            if (!values || values.length < 2) return

                            var minV = values[0], maxV = values[0]
                            for (var i = 1; i < values.length; i++) {
                                minV = Math.min(minV, values[i])
                                maxV = Math.max(maxV, values[i])
                            }
                            if (maxV - minV < 1) maxV = minV + 1

                            ctx.lineWidth = 2
                            ctx.strokeStyle = "white"
                            ctx.globalAlpha = 0.9
                            ctx.beginPath()
                            for (var j = 0; j < values.length; j++) {
                                var x = (j / (values.length - 1)) * (width - 6) + 3
                                var y = height - 3 - ((values[j] - minV) / (maxV - minV)) * (height - 6)
                                if (j === 0) ctx.moveTo(x, y)
                                else ctx.lineTo(x, y)
                            }
                            ctx.stroke()
                            ctx.globalAlpha = 1.0
                        }
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 4
                    NText { text: "Fan (%)"; pointSize: Style.fontSizes.s; opacity: 0.8 }
                    Canvas {
                        id: pctGraph
                        Layout.fillWidth: true
                        Layout.preferredHeight: 70
                        onPaint: {
                            var ctx = getContext("2d")
                            ctx.clearRect(0, 0, width, height)
                            ctx.globalAlpha = 0.18
                            ctx.fillStyle = "white"
                            ctx.fillRect(0, 0, width, height)
                            ctx.globalAlpha = 1.0

                            var values = root.pctHistory
                            if (!values || values.length < 2) return

                            var minV = 0
                            var maxV = 100

                            ctx.lineWidth = 2
                            ctx.strokeStyle = "white"
                            ctx.globalAlpha = 0.9
                            ctx.beginPath()
                            for (var j = 0; j < values.length; j++) {
                                var x = (j / (values.length - 1)) * (width - 6) + 3
                                var y = height - 3 - ((values[j] - minV) / (maxV - minV)) * (height - 6)
                                if (j === 0) ctx.moveTo(x, y)
                                else ctx.lineTo(x, y)
                            }
                            ctx.stroke()
                            ctx.globalAlpha = 1.0
                        }
                    }
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 4
                visible: useEctool

                NText { text: "RPM (Fan0 / Fan1)"; pointSize: Style.fontSizes.s; opacity: 0.8 }

                Canvas {
                    id: rpmGraph
                    Layout.fillWidth: true
                    Layout.preferredHeight: 70
                    onPaint: {
                        var ctx = getContext("2d")
                        ctx.clearRect(0, 0, width, height)
                        ctx.globalAlpha = 0.18
                        ctx.fillStyle = "white"
                        ctx.fillRect(0, 0, width, height)
                        ctx.globalAlpha = 1.0

                        var a = root.rpm0History
                        var b = root.rpm1History
                        if (!a || a.length < 2) return

                        var minV = a[0], maxV = a[0]
                        for (var i = 0; i < a.length; i++) {
                            minV = Math.min(minV, a[i])
                            maxV = Math.max(maxV, a[i])
                            if (b && b[i] !== undefined) {
                                minV = Math.min(minV, b[i])
                                maxV = Math.max(maxV, b[i])
                            }
                        }
                        if (maxV - minV < 100) maxV = minV + 100

                        function draw(values, alpha) {
                            if (!values || values.length < 2) return
                            ctx.lineWidth = 2
                            ctx.strokeStyle = "white"
                            ctx.globalAlpha = alpha
                            ctx.beginPath()
                            for (var j = 0; j < values.length; j++) {
                                var x = (j / (values.length - 1)) * (width - 6) + 3
                                var y = height - 3 - ((values[j] - minV) / (maxV - minV)) * (height - 6)
                                if (j === 0) ctx.moveTo(x, y)
                                else ctx.lineTo(x, y)
                            }
                            ctx.stroke()
                        }

                        draw(a, 0.95)
                        draw(b, 0.55)
                        ctx.globalAlpha = 1.0
                    }
                }

                NText {
                    Layout.fillWidth: true
                    opacity: 0.75
                    pointSize: Style.fontSizes.xs
                    text: "Note: ectool usually requires privileges. This plugin uses: sudo -n ectool … (no password prompts)."
                    wrapMode: Text.Wrap
                }
            }

            NText {
                Layout.fillWidth: true
                visible: lastError.length > 0
                text: "Error: " + lastError
                pointSize: Style.fontSizes.xs
                opacity: 0.8
                wrapMode: Text.Wrap
            }

            Item { Layout.fillHeight: true }
        }
    }
}
