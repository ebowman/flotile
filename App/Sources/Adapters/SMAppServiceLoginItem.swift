import Foundation
import FloTileCore
import ServiceManagement

/// `LoginItemService` backed by `SMAppService.mainApp`.
///
/// The state is deliberately never cached: the user can add or remove the login item in
/// System Settings > General > Login Items behind our back, so every read asks the system.
struct SMAppServiceLoginItem: LoginItemService {
    var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    func setEnabled(_ enabled: Bool) throws {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            let ns = error as NSError
            throw LoginItemError(message: LoginItemError.userMessage(
                domain: ns.domain, code: ns.code, whileEnabling: enabled, appName: "FlöTile"))
        }
    }
}
