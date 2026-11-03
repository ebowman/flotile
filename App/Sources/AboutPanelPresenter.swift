import AppKit

/// Shows the standard About panel. AppKit renders the icon and the bundle's
/// NSHumanReadableCopyright itself, so neither is passed here.
@MainActor
enum AboutPanelPresenter {
    static func options(bundle: Bundle = .main) -> [NSApplication.AboutPanelOptionKey: Any] {
        let short = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
        // AppKit prints "Version <applicationVersion> (<version>)", so pass the parts.
        return [
            .applicationName: AboutCopy.appName,
            .applicationVersion: short,
            .version: build,
            .credits: credits()
        ]
    }

    static func credits() -> NSAttributedString {
        let text = AboutCopy.credits() as NSString
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let result = NSMutableAttributedString(string: text as String, attributes: [
            .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
            .paragraphStyle: paragraph,
            .foregroundColor: NSColor.labelColor
        ])
        let urlString = AboutCopy.repositoryURL.absoluteString
        let range = text.range(of: urlString, options: .backwards)
        if range.location != NSNotFound {
            result.addAttribute(.link, value: AboutCopy.repositoryURL, range: range)
        }
        return result
    }

    static func show(bundle: Bundle = .main) {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(options: options(bundle: bundle))
    }
}
