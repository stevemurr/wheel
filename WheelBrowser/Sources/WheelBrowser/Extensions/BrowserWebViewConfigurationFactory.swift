import Foundation
import WebKit

enum BrowserWebViewSurface {
    case overlay
    case tab
}

final class BrowserWebViewConfigurationFactory {
    static let shared = BrowserWebViewConfigurationFactory()

    private let registry: ExtensionRegistry

    init(registry: ExtensionRegistry = .shared) {
        self.registry = registry
    }

    func makeConfiguration(surface: BrowserWebViewSurface) -> WKWebViewConfiguration {
        let configuration = WKWebViewConfiguration()
        configuration.preferences.isElementFullscreenEnabled = true
        configuration.preferences.setValue(true, forKey: "allowsPictureInPictureMediaPlayback")

        let contentController = configuration.userContentController
        addBuiltInScripts(to: contentController, surface: surface)

        if AppSettings.shared.extensionsEnabled {
            let snapshot = registry.activeSnapshot()
            for script in snapshot.userScripts {
                contentController.addUserScript(
                    WKUserScript(
                        source: script.source,
                        injectionTime: script.injectionTime,
                        forMainFrameOnly: script.forMainFrameOnly
                    )
                )
            }

            for ruleList in snapshot.contentRuleLists {
                contentController.add(ruleList)
            }
        }

        return configuration
    }

    private func addBuiltInScripts(to contentController: WKUserContentController, surface: BrowserWebViewSurface) {
        if HeadlessConfig.current.enabled {
            contentController.addUserScript(AntiDetectionScripts.createUserScript())
        }

        if surface == .tab {
            contentController.addUserScript(LinkHoverScripts.createUserScript())
        }
    }
}
