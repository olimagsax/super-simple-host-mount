import Cocoa

struct Server: Codable { var name: String; var host: String; var path: String? }

let sshfsPath = "/usr/local/bin/sshfs"
let configPath = NSString(string: "~/.config/ssh-mounts/servers.json").expandingTildeInPath
func mountPoint(_ s: Server) -> String { NSString(string: "~/mnt/\(s.name)").expandingTildeInPath }

final class Ref: NSObject { let s: Server; init(_ s: Server) { self.s = s } }

final class App: NSObject, NSApplicationDelegate, NSMenuDelegate {
    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    let menu = NSMenu()
    var servers: [Server] = []
    var busy = Set<String>()
    var mounted = Set<String>()
    var menuOpen = false

    func applicationDidFinishLaunching(_ n: Notification) {
        menu.delegate = self
        item.menu = menu
        loadConfig(); refresh()
        Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { _ in self.refresh() }
    }

    func loadConfig() {
        if let d = try? Data(contentsOf: URL(fileURLWithPath: configPath)),
           let s = try? JSONDecoder().decode([Server].self, from: d) { servers = s } else { servers = [] }
    }

    func mountedSet() -> Set<String> {
        let (_, out) = run("/sbin/mount", [])
        return Set(servers.filter { s in
            let mp = mountPoint(s)
            return out.contains(" on \(mp) ") || out.contains(" on /private\(mp) ")
        }.map { $0.name })
    }

    func refresh() {
        mounted = mountedSet()
        let any = !mounted.isEmpty
        let img = NSImage(systemSymbolName: any ? "externaldrive.fill.badge.checkmark" : "externaldrive.badge.xmark",
                          accessibilityDescription: "SSH mounts")
        img?.isTemplate = true
        item.button?.image = img
        if !menuOpen { rebuild() }
    }

    func rebuild() {
        menu.removeAllItems()
        if servers.isEmpty {
            menu.addItem(withTitle: "No servers configured", action: nil, keyEquivalent: "")
        }
        for s in servers {
            let isOn = mounted.contains(s.name)
            let title = (busy.contains(s.name) ? "◌ " : (isOn ? "● " : "○ ")) + s.name
            let it = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            let sub = NSMenu()
            let t = NSMenuItem(title: isOn ? "Disconnect" : "Connect", action: #selector(toggle(_:)), keyEquivalent: "")
            t.target = self; t.representedObject = Ref(s); t.isEnabled = !busy.contains(s.name)
            sub.addItem(t)
            let o = NSMenuItem(title: "Open in Finder", action: #selector(openFinder(_:)), keyEquivalent: "")
            o.target = self; o.representedObject = Ref(s); o.isEnabled = isOn
            sub.addItem(o)
            sub.addItem(.separator())
            let k = NSMenuItem(title: "Set up key login… (opens Terminal)", action: #selector(setupKey(_:)), keyEquivalent: "")
            k.target = self; k.representedObject = Ref(s)
            sub.addItem(k)
            it.submenu = sub
            menu.addItem(it)
        }
        menu.addItem(.separator())
        let e = NSMenuItem(title: "Edit servers…", action: #selector(editConfig), keyEquivalent: "")
        e.target = self; menu.addItem(e)
        let r = NSMenuItem(title: "Reload servers", action: #selector(reload), keyEquivalent: "r")
        r.target = self; menu.addItem(r)
        let h = NSMenuItem(title: "Setup help…", action: #selector(showHelp), keyEquivalent: "")
        h.target = self; menu.addItem(h)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    func menuWillOpen(_ m: NSMenu) { if m === menu { menuOpen = true; refresh() } }
    func menuDidClose(_ m: NSMenu) { if m === menu { menuOpen = false; rebuild() } }

    @objc func setupKey(_ sender: NSMenuItem) {
        guard let s = (sender.representedObject as? Ref)?.s else { return }
        let script = """
        #!/bin/zsh
        clear
        echo "Setting up key login for \(s.name)"
        echo
        echo "1/2  Storing your key passphrase in the macOS Keychain (enter the KEY passphrase)"
        ssh-add --apple-use-keychain ~/.ssh/id_rsa
        echo
        echo "2/2  Installing your public key on \(s.host) (enter the SERVER password)"
        ssh-copy-id -i ~/.ssh/id_rsa.pub \(s.host)
        echo
        echo "Checking passwordless login..."
        if ssh -o BatchMode=yes \(s.host) true; then echo "OK - you can now click Connect."; else echo "Still asking for a password - see Setup help."; fi
        echo
        read -k 1 "?Press any key to close"
        """
        let path = NSString(string: "~/.config/ssh-mounts/setup-\(s.name).command").expandingTildeInPath
        try? script.write(toFile: path, atomically: true, encoding: .utf8)
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: path)
        NSWorkspace.shared.open(URL(fileURLWithPath: path))
    }

    @objc func showHelp() {
        let text = """
        ONE-TIME SETUP (per key / per server)

        Easiest: open a server's submenu and click
        "Set up key login… (opens Terminal)". It runs both steps below.

        By hand, in Terminal.app:

        1. Store your key passphrase in the Keychain (once per key):
           ssh-add --apple-use-keychain ~/.ssh/id_rsa

        2. Install your public key on a server (once per server):
           ssh-copy-id -i ~/.ssh/id_rsa.pub user@host

        3. Check that no prompt appears:
           ssh user@host echo ok

        ADDING A SERVER
        Menu > Edit servers…, add a line like
          { "name": "my-vps", "host": "user@1.2.3.4", "path": "/var/www" }
        then Menu > Reload servers. "path" is optional.
        It mounts at ~/mnt/<name>.

        TROUBLESHOOTING
        - Connect fails with "Permission denied": step 1 or 2 not done.
        - Mount goes stale after changing network: Disconnect, then Connect.
        """
        let tv = NSTextView(frame: NSRect(x: 0, y: 0, width: 520, height: 360))
        tv.string = text; tv.isEditable = false; tv.isSelectable = true
        tv.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        let sv = NSScrollView(frame: tv.frame); sv.documentView = tv; sv.hasVerticalScroller = true
        let a = NSAlert(); a.messageText = "SSH Mounts – setup"; a.accessoryView = sv
        NSApp.activate(ignoringOtherApps: true); a.runModal()
    }

    @objc func reload() { loadConfig(); refresh() }
    @objc func editConfig() { NSWorkspace.shared.open(URL(fileURLWithPath: configPath)) }
    @objc func openFinder(_ sender: NSMenuItem) {
        guard let s = (sender.representedObject as? Ref)?.s else { return }
        NSWorkspace.shared.open(URL(fileURLWithPath: mountPoint(s)))
    }

    @objc func toggle(_ sender: NSMenuItem) {
        guard let s = (sender.representedObject as? Ref)?.s else { return }
        let wasMounted = mounted.contains(s.name)
        busy.insert(s.name); refresh()
        DispatchQueue.global().async {
            let err = wasMounted ? self.unmount(s) : self.mount(s)
            DispatchQueue.main.async {
                self.busy.remove(s.name); self.refresh()
                if let err = err, !err.isEmpty {
                    let a = NSAlert(); a.messageText = "\(wasMounted ? "Disconnect" : "Connect") \(s.name) failed"
                    a.informativeText = err; NSApp.activate(ignoringOtherApps: true); a.runModal()
                } else if !wasMounted { NSWorkspace.shared.open(URL(fileURLWithPath: mountPoint(s))) }
            }
        }
    }

    func run(_ exe: String, _ args: [String]) -> (Int32, String) {
        let p = Process(); p.executableURL = URL(fileURLWithPath: exe); p.arguments = args
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = "/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        p.environment = env
        let pipe = Pipe(); p.standardOutput = pipe; p.standardError = pipe
        do { try p.run() } catch { return (1, "\(error)") }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return (p.terminationStatus, String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "")
    }

    func mount(_ s: Server) -> String? {
        let mp = mountPoint(s)
        try? FileManager.default.createDirectory(atPath: mp, withIntermediateDirectories: true)
        let (rc, out) = run(sshfsPath, ["\(s.host):\(s.path ?? "")", mp,
            "-o", "volname=\(s.name),reconnect,ServerAliveInterval=15,BatchMode=yes,ConnectTimeout=5"])
        return rc == 0 ? nil : (out.isEmpty ? "sshfs exited with \(rc)" : out)
    }

    func unmount(_ s: Server) -> String? {
        var (rc, out) = run("/usr/sbin/diskutil", ["unmount", mountPoint(s)])
        if rc != 0 { (rc, out) = run("/usr/sbin/diskutil", ["unmount", "force", mountPoint(s)]) }
        return rc == 0 ? nil : out
    }
}

let app = NSApplication.shared
let delegate = App()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
