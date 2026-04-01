import AppKit

class AppWatcher: ObservableObject {
    @Published var activeMeetingApp: String? = nil

    weak var runner: TranscribeeRunner?
    private var observers: [NSObjectProtocol] = []

    private let watched: [String: String] = [
        "us.zoom.xos":          "Zoom",
        "com.microsoft.teams2": "Teams",
        "com.microsoft.teams":  "Teams",
        "com.loom.desktop":     "Loom",
    ]

    init() {
        setupObservers()
        checkRunningApps()
    }

    func setRunner(_ runner: TranscribeeRunner) {
        self.runner = runner
    }

    private func setupObservers() {
        let nc = NSWorkspace.shared.notificationCenter

        observers.append(nc.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification,
            object: nil, queue: .main
        ) { [weak self] note in
            guard let self,
                  let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  let bundleID = app.bundleIdentifier,
                  let name = self.watched[bundleID] else { return }
            self.activeMeetingApp = name
        })

        observers.append(nc.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil, queue: .main
        ) { [weak self] note in
            guard let self,
                  let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  let bundleID = app.bundleIdentifier,
                  self.watched[bundleID] != nil else { return }
            self.activeMeetingApp = nil
            // Auto-stop recording when meeting app quits
            if let runner = self.runner, case .recording = runner.state {
                runner.stop()
            }
        })
    }

    private func checkRunningApps() {
        for app in NSWorkspace.shared.runningApplications {
            guard let bundleID = app.bundleIdentifier,
                  let name = watched[bundleID] else { continue }
            activeMeetingApp = name
            break
        }
    }
}
