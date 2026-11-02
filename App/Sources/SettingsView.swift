import FloTileCore
import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        Form {
            Toggle("Open at Login", isOn: Binding(
                get: { model.openAtLogin },
                set: { model.setOpenAtLogin($0) }
            ))
            if let message = model.errorMessage {
                Text(message).font(.footnote).foregroundStyle(.red)
            }
        }
        .formStyle(.grouped)
        .frame(width: 320)
        .padding()
        .onAppear { model.refresh() }
    }
}
