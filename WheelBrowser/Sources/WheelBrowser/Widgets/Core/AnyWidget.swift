import SwiftUI
import Combine

/// Type-erased wrapper for widgets
@MainActor
final class AnyWidget: Identifiable, ObservableObject {
    let id: UUID
    let typeIdentifier: String

    private let _displayName: () -> String
    private let _iconName: () -> String
    private let _supportedSizes: () -> [WidgetSize]
    private let _getCurrentSize: () -> WidgetSize
    private let _setCurrentSize: (WidgetSize) -> Void
    private let _makeContent: () -> AnyView
    private let _refresh: () async -> Void
    private let _encodeConfiguration: () -> [String: Any]
    private let _decodeConfiguration: ([String: Any]) -> Void

    private var cancellables = Set<AnyCancellable>()

    var displayName: String { _displayName() }
    var iconName: String { _iconName() }
    var supportedSizes: [WidgetSize] { _supportedSizes() }

    var currentSize: WidgetSize {
        get { _getCurrentSize() }
        set {
            objectWillChange.send()
            _setCurrentSize(newValue)
        }
    }

    init<W: Widget>(_ widget: W) {
        self.id = widget.id
        self.typeIdentifier = W.typeIdentifier

        self._displayName = { W.displayName }
        self._iconName = { W.iconName }
        self._supportedSizes = { widget.supportedSizes }
        self._getCurrentSize = { widget.currentSize }
        self._setCurrentSize = { widget.currentSize = $0 }
        self._makeContent = { AnyView(widget.makeContent()) }
        self._refresh = { await widget.refresh() }
        self._encodeConfiguration = { widget.encodeConfiguration() }
        self._decodeConfiguration = { widget.decodeConfiguration($0) }

        // Forward objectWillChange
        widget.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
    }

    func makeContent() -> AnyView {
        _makeContent()
    }

    func refresh() async {
        await _refresh()
    }

    func encodeConfiguration() -> [String: Any] {
        _encodeConfiguration()
    }

    func decodeConfiguration(_ data: [String: Any]) {
        _decodeConfiguration(data)
    }
}
