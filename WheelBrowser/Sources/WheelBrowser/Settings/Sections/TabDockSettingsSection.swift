import SwiftUI

struct TabDockSettingsSection: View {
    @AppStorage(AppSettings.hiddenTabScaleKey)
    private var hiddenTabScale = AppSettings.defaultHiddenTabScale

    @AppStorage(AppSettings.shownTabScaleKey)
    private var shownTabScale = AppSettings.defaultShownTabScale

    var body: some View {
        Section("Tab Dock") {
            scaleSlider(
                title: "Hidden Tab Size",
                value: $hiddenTabScale,
                range: AppSettings.hiddenTabScaleRange
            )

            scaleSlider(
                title: "Shown Tab Size",
                value: $shownTabScale,
                range: AppSettings.shownTabScaleRange
            )

            Text("Adjust the size of the collapsed binder tabs and expanded thumbnail previews in the left tab dock.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func scaleSlider(
        title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                Spacer()
                Text("\(Int((value.wrappedValue * 100).rounded()))%")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            Slider(
                value: value,
                in: range,
                step: AppSettings.tabScaleStep
            )
        }
    }
}
