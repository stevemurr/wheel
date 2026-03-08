import SwiftUI

struct NotesStrip: View {
    var noteStore: NoteStore
    let onOpenNote: (NoteRecord) -> Void
    let onOpenToday: () -> Void
    let onCreateNote: () -> Void

    @AppStorage(AppSettings.hiddenTabScaleKey)
    private var hiddenTabScale = AppSettings.defaultHiddenTabScale

    @AppStorage(AppSettings.shownTabScaleKey)
    private var shownTabScale = AppSettings.defaultShownTabScale

    @State private var isExpanded = false
    @State private var collapseWork: DispatchWorkItem?

    private let collapseDelay: TimeInterval = 0.42
    private let minimumHotZoneHeight: CGFloat = 240
    private let hotZoneVerticalForgiveness: CGFloat = 80
    private let expandedHotZoneLeadingPadding: CGFloat = 28

    private var revealHotZoneWidth: CGFloat {
        max(24, collapsedPeekMaxWidth + 14)
    }

    private var expandedHotZoneWidth: CGFloat {
        expandedDockWidth + expandedHotZoneLeadingPadding
    }

    private var activeHotZoneWidth: CGFloat {
        isExpanded ? expandedHotZoneWidth : revealHotZoneWidth
    }

    private var expandedDockWidth: CGFloat {
        226 * shownScale
    }

    private var shownScale: CGFloat {
        CGFloat(clamp(shownTabScale, to: AppSettings.shownTabScaleRange))
    }

    private var hiddenScale: CGFloat {
        CGFloat(clamp(hiddenTabScale, to: AppSettings.hiddenTabScaleRange))
    }

    private var expandedCardHeight: CGFloat {
        86 * max(0.9, shownScale)
    }

    private var expandedSpacing: CGFloat {
        10 * max(0.9, shownScale)
    }

    private var collapsedPeekMaxWidth: CGFloat {
        14 * hiddenScale
    }

    private var collapsedPeekHeight: CGFloat {
        32 * hiddenScale
    }

    private var collapsedSpacing: CGFloat {
        4 * max(0.85, hiddenScale)
    }

    private var expandedStackHeight: CGFloat {
        stackHeight(itemHeight: expandedCardHeight, spacing: expandedSpacing, verticalPadding: 86)
    }

    private var collapsedStackHeight: CGFloat {
        stackHeight(itemHeight: collapsedPeekHeight, spacing: collapsedSpacing, verticalPadding: 0)
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .trailing) {
                Color.clear
                    .frame(
                        width: activeHotZoneWidth,
                        height: activeHotZoneHeight(in: geometry.size.height)
                    )
                    .contentShape(Rectangle())
                    .frame(maxHeight: .infinity, alignment: .center)
                    .onHover(perform: handleHotZoneHover)

                if isExpanded {
                    expandedContent(containerHeight: geometry.size.height)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                } else {
                    collapsedContent
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .frame(width: activeHotZoneWidth, alignment: .trailing)
            .frame(maxHeight: .infinity, alignment: .trailing)
        }
        .frame(width: activeHotZoneWidth)
    }

    private func expandedContent(containerHeight: CGFloat) -> some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 14 * shownScale) {
                actionRow

                LazyVStack(spacing: expandedSpacing) {
                    ForEach(noteStore.orderedNotes) { note in
                        NotePreviewCard(note: note, sizeScale: shownScale) {
                            onOpenNote(note)
                        }
                    }
                }
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 8)
            .frame(minHeight: containerHeight, alignment: .top)
        }
        .frame(width: expandedDockWidth)
    }

    private var actionRow: some View {
        HStack(spacing: 10) {
            Button(action: onOpenToday) {
                Label("Today", systemImage: "calendar")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(NotesStripActionButtonStyle(isPrimary: true))

            Button(action: onCreateNote) {
                Label("New", systemImage: "square.and.pencil")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(NotesStripActionButtonStyle(isPrimary: false))
        }
        .frame(maxWidth: .infinity)
    }

    private var collapsedContent: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)

            VStack(spacing: collapsedSpacing) {
                if noteStore.orderedNotes.isEmpty {
                    EmptyNotesPeek(sizeScale: hiddenScale, onSelect: onOpenToday)
                } else {
                    ForEach(noteStore.orderedNotes) { note in
                        NotePeek(
                            note: note,
                            sizeScale: hiddenScale,
                            onSelect: { onOpenNote(note) }
                        )
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .frame(width: revealHotZoneWidth, alignment: .trailing)
        .frame(maxHeight: .infinity)
    }

    private func handleHotZoneHover(_ hovering: Bool) {
        if hovering {
            collapseWork?.cancel()
            collapseWork = nil
            withAnimation(AppAnimation.panelSpring) {
                isExpanded = true
            }
        } else {
            let work = DispatchWorkItem { [self] in
                withAnimation(AppAnimation.panelSpring) {
                    isExpanded = false
                }
            }
            collapseWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + collapseDelay, execute: work)
        }
    }

    private func activeHotZoneHeight(in containerHeight: CGFloat) -> CGFloat {
        let naturalHeight = isExpanded ? expandedStackHeight : collapsedStackHeight
        let targetHeight = max(minimumHotZoneHeight, naturalHeight + hotZoneVerticalForgiveness)
        return min(containerHeight, targetHeight)
    }

    private func stackHeight(itemHeight: CGFloat, spacing: CGFloat, verticalPadding: CGFloat) -> CGFloat {
        let count = CGFloat(max(noteStore.notes.count, 1))
        let gaps = max(0, count - 1)
        return count * itemHeight + gaps * spacing + verticalPadding
    }
}

private struct NotePreviewCard: View {
    let note: NoteRecord
    let sizeScale: CGFloat
    let onSelect: () -> Void

    @State private var isHovered = false

    private var cornerRadius: CGFloat { 16 * sizeScale }

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 10 * sizeScale) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(accentColor)
                        .frame(width: 10 * sizeScale, height: 10 * sizeScale)

                    Text(note.kind == .daily ? "Daily Note" : "Ad Hoc")
                        .font(.system(size: 10 * sizeScale, weight: .semibold))
                        .foregroundStyle(accentColor)

                    Spacer()

                    Text(note.shortUpdatedText)
                        .font(.system(size: 10 * sizeScale, weight: .medium))
                        .foregroundStyle(.secondary)
                }

                Text(note.displayTitle)
                    .font(.system(size: 14 * sizeScale, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                Text(note.excerpt.isEmpty ? emptyStateText : note.excerpt)
                    .font(.system(size: 11 * sizeScale))
                    .foregroundStyle(note.excerpt.isEmpty ? .tertiary : .secondary)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(14 * sizeScale)
            .frame(maxWidth: .infinity, minHeight: 84 * sizeScale, alignment: .leading)
            .background(cardBackground)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(accentColor.opacity(isHovered ? 0.35 : 0.14), lineWidth: isHovered ? 1.2 : 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .shadow(color: Color.black.opacity(isHovered ? 0.18 : 0.10), radius: isHovered ? 16 : 10, y: 6)
            .scaleEffect(isHovered ? 1.02 : 1)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(AppAnimation.hoverSpring) {
                isHovered = hovering
            }
        }
    }

    private var accentColor: Color {
        note.kind == .daily ? .accentColor : .orange
    }

    private var cardBackground: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor).opacity(0.92))
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            accentColor.opacity(isHovered ? 0.14 : 0.08),
                            Color(nsColor: .windowBackgroundColor).opacity(0.0),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        }
    }

    private var emptyStateText: String {
        note.kind == .daily ? "Open today’s thread of thought." : "Start capturing ideas, references, and snippets."
    }
}

private struct NotePeek: View {
    let note: NoteRecord
    let sizeScale: CGFloat
    let onSelect: () -> Void

    @State private var isHovered = false

    private var peekWidth: CGFloat {
        let baseWidth = note.kind == .daily ? 14.0 : 10.0
        return (isHovered ? baseWidth + 4 : baseWidth) * sizeScale
    }

    private var peekHeight: CGFloat { 32 * sizeScale }
    private var cornerRadius: CGFloat { 5 * sizeScale }

    var body: some View {
        UnevenRoundedRectangle(
            cornerRadii: .init(
                topLeading: cornerRadius,
                bottomLeading: cornerRadius,
                bottomTrailing: 0,
                topTrailing: 0
            ),
            style: .continuous
        )
        .fill(note.kind == .daily ? Color.accentColor : Color.orange)
        .frame(width: peekWidth, height: peekHeight)
        .overlay(alignment: .leading) {
            UnevenRoundedRectangle(
                cornerRadii: .init(
                    topLeading: cornerRadius,
                    bottomLeading: cornerRadius,
                    bottomTrailing: 0,
                    topTrailing: 0
                ),
                style: .continuous
            )
            .strokeBorder(Color.white.opacity(isHovered ? 0.65 : 0.35), lineWidth: max(1, 1.3 * sizeScale))
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .onHover { hovering in
            withAnimation(AppAnimation.quick) {
                isHovered = hovering
            }
        }
        .help(note.displayTitle)
    }
}

private struct EmptyNotesPeek: View {
    let sizeScale: CGFloat
    let onSelect: () -> Void

    @State private var isHovered = false

    private var peekWidth: CGFloat {
        (isHovered ? 24.0 : 20.0) * sizeScale
    }

    private var peekHeight: CGFloat {
        62 * sizeScale
    }

    private var cornerRadius: CGFloat {
        8 * sizeScale
    }

    var body: some View {
        UnevenRoundedRectangle(
            cornerRadii: .init(
                topLeading: cornerRadius,
                bottomLeading: cornerRadius,
                bottomTrailing: 0,
                topTrailing: 0
            ),
            style: .continuous
        )
        .fill(
            LinearGradient(
                colors: [
                    Color.accentColor.opacity(0.96),
                    Color.orange.opacity(0.92),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .frame(width: peekWidth, height: peekHeight)
        .overlay {
            VStack(spacing: 6 * sizeScale) {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 10 * sizeScale, weight: .semibold))
                Capsule(style: .continuous)
                    .fill(Color.white.opacity(0.75))
                    .frame(width: 10 * sizeScale, height: 2 * sizeScale)
                Capsule(style: .continuous)
                    .fill(Color.white.opacity(0.55))
                    .frame(width: 7 * sizeScale, height: 2 * sizeScale)
            }
            .foregroundStyle(Color.white.opacity(0.96))
        }
        .overlay(alignment: .leading) {
            UnevenRoundedRectangle(
                cornerRadii: .init(
                    topLeading: cornerRadius,
                    bottomLeading: cornerRadius,
                    bottomTrailing: 0,
                    topTrailing: 0
                ),
                style: .continuous
            )
            .strokeBorder(Color.white.opacity(isHovered ? 0.7 : 0.4), lineWidth: max(1, 1.3 * sizeScale))
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .onHover { hovering in
            withAnimation(AppAnimation.quick) {
                isHovered = hovering
            }
        }
        .help("Open Today's Note")
    }
}

private struct NotesStripActionButtonStyle: ButtonStyle {
    let isPrimary: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(isPrimary ? Color.white.opacity(configuration.isPressed ? 0.92 : 1) : Color.primary.opacity(configuration.isPressed ? 0.7 : 0.9))
            .padding(.horizontal, 12)
            .frame(height: 34)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(
                        isPrimary
                            ? Color.accentColor.opacity(configuration.isPressed ? 0.82 : 0.96)
                            : Color.primary.opacity(configuration.isPressed ? 0.07 : 0.05)
                    )
            )
            .overlay {
                if !isPrimary {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.primary.opacity(configuration.isPressed ? 0.10 : 0.06), lineWidth: 1)
                }
            }
    }
}

private func clamp(_ value: Double, to range: ClosedRange<Double>) -> Double {
    min(max(value, range.lowerBound), range.upperBound)
}
