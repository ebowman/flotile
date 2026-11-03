import FloTileCore
import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("Open at Login", isOn: Binding(
                get: { model.openAtLogin },
                set: { model.setOpenAtLogin($0) }
            ))
            if let message = model.errorMessage {
                Text(message).font(.footnote).foregroundStyle(.red)
            }
        }
        .padding(20)
        .frame(width: 320)
        .onAppear { model.refresh() }
    }
}
