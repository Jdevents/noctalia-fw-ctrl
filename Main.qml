import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Services.UI

Item {
    id: root

    // Injected by Noctalia
    property var pluginApi: null

    Process {
        id: fwUseProc
        stdout: StdioCollector { waitForEnd: true }
        stderr: StdioCollector { waitForEnd: true }
        onExited: running = false
    }

    function applyProfile(profile) {
        if (!profile) return
        var p = String(profile).trim()
        if (p.length === 0) {
            ToastService.showError("Please specify a valid fan profile.")
            return
        }
        if (fwUseProc.running) {
            ToastService.showNotice("Fan change already running…")
            return
        }
        Logger.i("FWControl", "Setting profile:", p)
        fwUseProc.command = ["fw-fanctrl", "use", p]
        fwUseProc.running = true
        ToastService.showNotice("Fan profile: " + p)
    }

    function openPanelOn(screen) {
        if (!pluginApi) return
        pluginApi.openPanel(screen)
    }

    IpcHandler {
        // Must match manifest.json "id"
        target: "plugin:fw-control"

        function setProfile(profile: string): void { root.applyProfile(profile) }
        function openPanel(): void {
            if (!pluginApi || Quickshell.screens.length === 0) return
            root.openPanelOn(Quickshell.screens[0])
        }
    }
}
