import AppKit
import FloTileCore
import os

@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private static let logger = Logger(subsystem: "ie.boboco.FloTile", category: "app")
    private static var delegate: AppDelegate?

    private var statusItemController: StatusItemController?
    private var permissionFlow: AccessibilityPermissionFlow?
    private var settingsModel: SettingsModel?
    private var session: TileSession?
    private var terminationObserver: NSObjectProtocol?

    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        Self.delegate = delegate
        app.delegate = delegate
        app.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        Self.logger.info("FloTile launched")

        #if DEBUG
        if CommandLine.arguments.contains("--self-test-tile") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { Self.runSelfTest() }
            return
        }
        if CommandLine.arguments.contains("--self-test-tile-undo") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { Self.runUndoSelfTest() }
            return
        }
        #endif

        settingsModel = SettingsModel(loginItems: SMAppServiceLoginItem())
        let windowSystem = AXWindowSystem()
        let coordinator = TileCoordinator(windowSystem: windowSystem)
        let session = TileSession(coordinator: coordinator, windowSystem: windowSystem)
        self.session = session
        permissionFlow = AccessibilityPermissionFlow(requestTrust: { windowSystem.requestTrust() })
        let presenter = TileOutcomePresenter(
            log: { message in Self.logger.error("\(message, privacy: .public)") },
            onAccessibilityNotGranted: { [weak self] in
                self?.handleAccessibilityNotGranted()
            }
        )
        // Resolved lazily so the controller closures can read the status button.
        weak var controllerRef: StatusItemController?
        let controller = StatusItemController(
            onTile: { screen in
                let outcome = session.handleClick(on: screen)
                let context: TileOutcomePresenter.Context = session.lastDecision == .restore ? .restoring : .tiling
                presenter.present(outcome, context: context)
            },
            canUndo: {
                guard let screen = AppKitScreenProvider.targetScreen(forStatusButton: controllerRef?.statusButton) else {
                    return false
                }
                return session.canUndo(frontmostPID: windowSystem.frontmostApplicationPID(), on: screen)
            },
            onUndo: {
                guard let screen = AppKitScreenProvider.targetScreen(forStatusButton: controllerRef?.statusButton) else {
                    return
                }
                presenter.present(session.undo(on: screen), context: .restoring)
            },
            onOpenSettings: { [weak self] in self?.openSettings() },
            onCheckForUpdates: {
                let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
                UpdateChecker.checkForUpdates(currentVersion: version)
            },
            onQuit: { NSApp.terminate(nil) }
        )
        controllerRef = controller
        statusItemController = controller
        terminationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil,
            queue: .main
        ) { note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            let pid = app.processIdentifier
            MainActor.assumeIsolated {
                session.forget(pid: pid)
                windowSystem.forgetApplication(pid: pid)
            }
        }
        if !controller.install() {
            Self.logger.warning("Could not install status item")
        }
    }

    #if DEBUG
    /// Bundle id the self-test must find frontmost (`--self-test-expect-bundle <id>`), if given.
    private static func expectedSelfTestBundle() -> String? {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--self-test-expect-bundle"), i + 1 < args.count else { return nil }
        return args[i + 1]
    }

    private static func frontmostSelfTestApp() -> (pid: pid_t, bundle: String)? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        return (app.processIdentifier, app.bundleIdentifier ?? "unknown")
    }

    /// Fails closed: the frontmost app, or exits 1 with an error JSON when none
    /// exists or it is not the expected bundle. Called before anything is tiled.
    private static func requireSelfTestApp(_ finish: (String, Int32) -> Never) -> (pid: pid_t, bundle: String) {
        guard let front = frontmostSelfTestApp() else {
            finish(SelfTestReport.errorJSON("no frontmost application"), 1)
        }
        if let expected = expectedSelfTestBundle(), expected != front.bundle {
            finish(SelfTestReport.errorJSON(
                "frontmost app is \(front.bundle) (pid \(front.pid)), expected \(expected); nothing was tiled"), 1)
        }
        return front
    }

    /// Live Accessibility self-test (see scripts/live-ax-test.sh): tiles the
    /// frontmost app on the screen under the mouse, re-reads the windows and
    /// prints one JSON line, then exits.
    private static func runSelfTest() {
        func finish(_ line: String, code: Int32) -> Never {
            print(line)
            fflush(stdout)
            exit(code)
        }
        guard let screen = AppKitScreenProvider.targetScreen(forStatusButton: nil) else {
            finish(SelfTestReport.errorJSON("no screen available"), code: 1)
        }
        let windowSystem = AXWindowSystem()
        let coordinator = TileCoordinator(windowSystem: windowSystem)
        // Guard and capture the frontmost app BEFORE tiling; the re-read reuses its pid.
        let front = requireSelfTestApp { finish($0, code: $1) }
        let pid = front.pid
        let outcome = coordinator.tile(on: screen)
        var frames: [CGRect] = []
        var ignored: [CGRect] = []
        do {
            (frames, ignored) = try rereadWindows(windowSystem, pid: pid, on: screen)
        } catch {
            finish(SelfTestReport.errorJSON(String(describing: error)), code: 1)
        }
        finish(SelfTestReport.json(app: front.bundle, outcome: outcome.selfTestLabel, screen: screen.visibleFrame,
                                   frames: frames, ignored: ignored), code: 0)
    }

    /// Eligible window frames (reading order) and ignored window frames of `pid`.
    private static func rereadWindows(_ windowSystem: AXWindowSystem, pid: pid_t,
                                      on screen: ScreenInfo) throws -> (frames: [CGRect], ignored: [CGRect]) {
        let all = try windowSystem.windows(forApplication: pid)
        let eligible = WindowSelector.eligibleWindows(all, on: screen)
        let eligibleIDs = Set(eligible.map(\.id))
        return (WindowSelector.readingOrder(eligible).map(\.frame),
                all.filter { !eligibleIDs.contains($0.id) }.map(\.frame))
    }

    /// Live undo self-test: click, wait 1 s, click again; prints one JSON line.
    private static func runUndoSelfTest() {
        func finish(_ line: String, code: Int32) -> Never {
            print(line)
            fflush(stdout)
            exit(code)
        }
        guard let screen = AppKitScreenProvider.targetScreen(forStatusButton: nil) else {
            finish(SelfTestReport.errorJSON("no screen available"), code: 1)
        }
        let windowSystem = AXWindowSystem()
        let coordinator = TileCoordinator(windowSystem: windowSystem)
        let session = TileSession(coordinator: coordinator, windowSystem: windowSystem)
        let front = requireSelfTestApp { finish($0, code: $1) }
        let pid = front.pid
        let outcome1 = session.handleClick(on: screen)
        let frames1: [CGRect]
        do { frames1 = try rereadWindows(windowSystem, pid: pid, on: screen).frames } catch {
            finish(SelfTestReport.errorJSON(String(describing: error)), code: 1)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            let outcome2 = session.handleClick(on: screen)
            let frames2: [CGRect]
            do { frames2 = try rereadWindows(windowSystem, pid: pid, on: screen).frames } catch {
                finish(SelfTestReport.errorJSON(String(describing: error)), code: 1)
            }
            finish(SelfTestReport.undoJSON(first: (outcome1.selfTestLabel, frames1),
                                           second: (outcome2.selfTestLabel, frames2),
                                           screen: screen.visibleFrame, app: front.bundle), code: 0)
        }
    }
    #endif

    private func handleAccessibilityNotGranted() {
        Self.logger.info("Accessibility not granted")
        permissionFlow?.present()
    }

    private func openSettings() {
        Self.logger.info("Settings requested")
        if let settingsModel { SettingsWindowController.showShared(model: settingsModel) }
    }
}
