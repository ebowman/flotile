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
            Toggle("Check for Updates Automatically", isOn: Binding(
                get: { model.automaticUpdateChecks },
                set: { model.setAutomaticUpdateChecks($0) }
            ))
            HStack {
                Text("Check at")
                DatePicker("", selection: Binding(
                    get: { CheckTimeBinding.date(fromMinute: model.automaticUpdateCheckMinute) },
                    set: { model.setAutomaticUpdateCheckMinute(CheckTimeBinding.minute(from: $0)) }
                ), displayedComponents: .hourAndMinute)
                    .labelsHidden()
            }
            .disabled(!model.automaticUpdateChecks)
            Text("Each day at this time FlöTile looks for a new version and only tells you when one is available. Nothing is installed without your OK, and you can skip a version you don't want.")
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

enum CheckTimeBinding {
    static func date(fromMinute minute: Int, calendar: Calendar = .current, reference: Date = Date()) -> Date {
        calendar.date(bySettingHour: minute / 60, minute: minute % 60, second: 0, of: reference) ?? reference
    }

    static func minute(from date: Date, calendar: Calendar = .current) -> Int {
        let c = calendar.dateComponents([.hour, .minute], from: date)
        return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }
}
