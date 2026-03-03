import SwiftUI

/// Renders a `RenderInput.table` as a sortable data grid.
struct TableWidgetView: View {
    let columns: [TableColumn]
    let rows: [[String: Any]]

    @State private var sortColumn: String?
    @State private var sortAscending = true

    private var sortedRows: [[String: Any]] {
        guard let sortCol = sortColumn else { return rows }

        return rows.sorted { a, b in
            let va = a[sortCol]
            let vb = b[sortCol]

            let result: Bool
            if let da = va as? Double, let db = vb as? Double {
                result = da < db
            } else if let ia = va as? Int, let ib = vb as? Int {
                result = ia < ib
            } else {
                let sa = "\(va ?? "")"
                let sb = "\(vb ?? "")"
                result = sa.localizedCaseInsensitiveCompare(sb) == .orderedAscending
            }

            return sortAscending ? result : !result
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 0) {
                ForEach(columns, id: \.key) { col in
                    headerCell(col)
                }
            }
            .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            // Rows
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(sortedRows.enumerated()), id: \.offset) { idx, row in
                        HStack(spacing: 0) {
                            ForEach(columns, id: \.key) { col in
                                dataCell(row[col.key], format: col.format)
                            }
                        }
                        .background(idx % 2 == 0 ? Color.clear : Color(nsColor: .controlBackgroundColor).opacity(0.5))
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func headerCell(_ col: TableColumn) -> some View {
        if col.sortable {
            Button(action: {
                if sortColumn == col.key {
                    sortAscending.toggle()
                } else {
                    sortColumn = col.key
                    sortAscending = true
                }
            }) {
                headerCellContent(col)
            }
            .buttonStyle(.plain)
        } else {
            headerCellContent(col)
        }
    }

    private func headerCellContent(_ col: TableColumn) -> some View {
        HStack(spacing: 4) {
            Text(col.label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)

            if sortColumn == col.key {
                Image(systemName: sortAscending ? "chevron.up" : "chevron.down")
                    .font(.system(size: 8))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }

    private func dataCell(_ value: Any?, format: ValueFormat) -> some View {
        Text(formatCellValue(value, format: format))
            .font(.system(size: 12))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
    }

    private func formatCellValue(_ value: Any?, format: ValueFormat) -> String {
        guard let value else { return "—" }
        switch format {
        case .currency:
            if let d = value as? Double { return String(format: "$%.2f", d) }
        case .percent:
            if let d = value as? Double { return String(format: "%.1f%%", d) }
        case .number:
            if let d = value as? Double { return String(format: "%.0f", d) }
        case .temperature:
            if let d = value as? Double { return String(format: "%.0f°", d) }
        case .plain:
            break
        }
        return "\(value)"
    }
}
