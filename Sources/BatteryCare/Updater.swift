import AppKit
import Observation

/// Checks GitHub Releases for a newer version and can replace the running app in place.
@Observable
final class Updater {
    static let shared = Updater()
    static let repo = "245678000000/BatteryCare"

    struct Release: Decodable {
        struct Asset: Decodable { let name: String; let browser_download_url: URL }
        let tag_name: String
        let name: String?
        let body: String?
        let html_url: URL
        let assets: [Asset]
        var version: String { tag_name.trimmingCharacters(in: CharacterSet(charactersIn: "vV")) }
        var zip: URL? { assets.first { $0.name.hasSuffix(".zip") }?.browser_download_url }
    }

    enum Phase: Equatable { case idle, checking, upToDate, available, downloading, installing, failed(String) }

    var phase: Phase = .idle
    var latest: Release?
    var showSheet = false
    var lastCheck: Date? = UserDefaults.standard.object(forKey: "update.lastCheck") as? Date
    var autoCheck: Bool = UserDefaults.standard.object(forKey: "update.auto") as? Bool ?? true {
        didSet { UserDefaults.standard.set(autoCheck, forKey: "update.auto") }
    }

    static var currentVersion: String { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0" }
    var updateAvailable: Bool { latest.map { Self.isNewer($0.version, than: Self.currentVersion) } ?? false }

    static func isNewer(_ a: String, than b: String) -> Bool {
        let pa = a.split(separator: ".").map { Int($0.prefix { $0.isNumber }) ?? 0 }
        let pb = b.split(separator: ".").map { Int($0.prefix { $0.isNumber }) ?? 0 }
        for i in 0..<max(pa.count, pb.count) {
            let x = i < pa.count ? pa[i] : 0, y = i < pb.count ? pb[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    /// Called from the app's tick; checks at most once a day when auto-check is on.
    func autoCheckIfNeeded() {
        guard autoCheck, phase == .idle || phase == .upToDate else { return }
        if let last = lastCheck, Date().timeIntervalSince(last) < 24 * 3600 { return }
        check(userInitiated: false)
    }

    func check(userInitiated: Bool) {
        guard phase != .checking && phase != .downloading && phase != .installing else { return }
        phase = .checking
        var req = URLRequest(url: URL(string: "https://api.github.com/repos/\(Self.repo)/releases/latest")!)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("BatteryCare-Updater", forHTTPHeaderField: "User-Agent")
        req.timeoutInterval = 20
        URLSession.shared.dataTask(with: req) { data, resp, err in
            DispatchQueue.main.async {
                self.lastCheck = Date(); UserDefaults.standard.set(self.lastCheck, forKey: "update.lastCheck")
                guard let data, (resp as? HTTPURLResponse)?.statusCode == 200,
                      let r = try? JSONDecoder().decode(Release.self, from: data) else {
                    self.phase = userInitiated ? .failed(err?.localizedDescription ?? "无法获取版本信息") : .idle
                    return
                }
                self.latest = r
                if self.updateAvailable {
                    self.phase = .available
                    self.showSheet = true
                } else {
                    self.phase = .upToDate
                }
            }
        }.resume()
    }

    func openReleasePage() { NSWorkspace.shared.open(latest?.html_url ?? URL(string: "https://github.com/\(Self.repo)/releases")!) }

    func downloadAndInstall() {
        guard let url = latest?.zip else { openReleasePage(); return }
        let dest = Bundle.main.bundleURL
        guard FileManager.default.isWritableFile(atPath: dest.deletingLastPathComponent().path) else {
            phase = .failed("没有权限写入 \(dest.deletingLastPathComponent().path)，请手动下载安装。"); return
        }
        phase = .downloading
        URLSession.shared.downloadTask(with: url) { tmp, resp, err in
            guard let tmp, (resp as? HTTPURLResponse)?.statusCode == 200 else {
                DispatchQueue.main.async { self.phase = .failed(err?.localizedDescription ?? "下载失败") }; return
            }
            do {
                let work = FileManager.default.temporaryDirectory.appendingPathComponent("BatteryCareUpdate-\(UUID().uuidString)")
                try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
                let zip = work.appendingPathComponent("update.zip")
                try FileManager.default.moveItem(at: tmp, to: zip)
                try self.run("/usr/bin/ditto", ["-x", "-k", zip.path, work.path])
                guard let app = try FileManager.default.contentsOfDirectory(at: work, includingPropertiesForKeys: nil)
                        .first(where: { $0.pathExtension == "app" }),
                      Bundle(url: app)?.bundleIdentifier == Bundle.main.bundleIdentifier else {
                    throw NSError(domain: "Updater", code: 1, userInfo: [NSLocalizedDescriptionKey: "更新包无效"])
                }
                DispatchQueue.main.async { self.phase = .installing; self.relaunch(replacing: dest, with: app) }
            } catch {
                DispatchQueue.main.async { self.phase = .failed(error.localizedDescription) }
            }
        }.resume()
    }

    private func run(_ path: String, _ args: [String]) throws {
        let p = Process(); p.executableURL = URL(fileURLWithPath: path); p.arguments = args
        try p.run(); p.waitUntilExit()
        if p.terminationStatus != 0 { throw NSError(domain: "Updater", code: Int(p.terminationStatus), userInfo: [NSLocalizedDescriptionKey: "解压失败"]) }
    }

    /// Waits for this process to exit, swaps the bundle, then reopens the new app.
    private func relaunch(replacing dest: URL, with app: URL) {
        let script = """
        while kill -0 "$1" 2>/dev/null; do sleep 0.2; done
        rm -rf "$3.old" && mv "$3" "$3.old" && mv "$2" "$3" && rm -rf "$3.old" || { [ -d "$3.old" ] && [ ! -d "$3" ] && mv "$3.old" "$3"; }
        xattr -dr com.apple.quarantine "$3" 2>/dev/null
        open "$3"
        """
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/bash")
        p.arguments = ["-c", script, "bash", "\(ProcessInfo.processInfo.processIdentifier)", app.path, dest.path]
        do { try p.run() } catch { phase = .failed(error.localizedDescription); return }
        // Close the sheet first (a modal sheet can block terminate), then quit; force-exit as a fallback.
        showSheet = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            NSApp.windows.forEach { w in w.sheets.forEach { w.endSheet($0) } }
            NSApp.terminate(nil)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            AppModel.shared.willTerminate()
            exit(0)
        }
    }
}
