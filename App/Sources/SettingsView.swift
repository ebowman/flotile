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
            Toggle("Maximize on Second Click", isOn: Binding(
                get: { model.maximizeOnSecondClick },
                set: { model.setMaximizeOnSecondClick($0) }
            ))
            Text("Click once to tile, again to give every window the whole display (stacking order is kept), and a third time to restore the original layout. When off, the second click restores.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let message = model.errorMessage {
                Text(message).font(.footnote).foregroundStyle(.red)
            }
        }
        .padding(20)
        .frame(width: 320)
        .onAppear { model.refresh() }
    }
}
