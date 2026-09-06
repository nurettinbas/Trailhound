import SwiftUI
import UniformTypeIdentifiers

/// Trailhound has no analytics or crash reporting (the app is fully offline), so
/// this is the only way to see what happened on a user's device — e.g. exact
/// Bluetooth connect/disconnect timing around a false-stop report. Only shown
/// once Developer Mode is enabled (tap the version number 5 times in Settings).
struct DevLogView: View {
    @State private var lines: [String] = []
    @State private var filter: DevLogCategory?
    @State private var refreshTask: Task<Void, Never>?
    @Bindable private var settings = AppSettings.shared

    private var filteredLines: [String] {
        guard let filter else { return lines }
        let tag = "[\(filter.rawValue)]"
        return lines.filter { $0.contains(tag) }
    }

    var body: some View {
        List {
            Section {
                Picker(L10n.string("dev.glass.engine"), selection: $settings.glassEngineOverride) {
                    Text(L10n.string("dev.glass.engine.auto")).tag(GlassEngineOverride.auto)
                    Text(L10n.string("dev.glass.engine.material")).tag(GlassEngineOverride.material)
                    Text(L10n.string("dev.glass.engine.native")).tag(GlassEngineOverride.native)
                }
                .glassSegmentedStyle()
                .labelsHidden()
                .glassListRow()
            } header: {
                Text(L10n.string("dev.glass.engine"))
            } footer: {
                Text(L10n.string("dev.glass.engine.hint"))
            }

            Section {
                if filteredLines.isEmpty {
                    Text(L10n.string("Henüz kayıt yok. Aracına Bluetooth ile bağlanıp sürmeye başlayınca burada akış görünecek."))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(Array(filteredLines.enumerated()), id: \.offset) { _, line in
                        Text(line)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(tint(for: line))
                            .textSelection(.enabled)
                    }
                }
            } header: {
                categoryFilterChips
            } footer: {
                Text(L10n.string("Günlük yaklaşık son 2 MB'ı tutar; dışa aktarınca tüm dosyayı gönderirsin."))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .listStyle(.plain)
        .glassListChrome()
        .navigationTitle(L10n.string("Geliştirici Günlüğü"))
        .toolbar {
            // Its own toolbar item, not a Menu row: a ShareLink nested in a Menu presents an
            // empty sheet on some iOS versions, which is why one device could export the log and
            // another showed a black screen.
            ToolbarItem(placement: .navigationBarTrailing) {
                ShareLink(
                    item: DevLogExportItem(),
                    preview: SharePreview(
                        DevLogExportItem.fileName,
                        image: Image(systemName: "doc.text")
                    )
                ) {
                    Image(systemName: "square.and.arrow.up")
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button {
                        copyLogToClipboard()
                    } label: {
                        Label(L10n.string("Panoya Kopyala"), systemImage: "doc.on.clipboard")
                    }
                    Button {
                        reload()
                    } label: {
                        Label(L10n.string("Yenile"), systemImage: "arrow.clockwise")
                    }
                    Button(role: .destructive) {
                        DeleteConfirmPresenter.shared.confirm(.generic) {
                            DevLog.shared.clear()
                            lines = []
                        }
                    } label: {
                        Label(L10n.string("Günlüğü Temizle"), systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .onAppear {
            reload()
            startAutoRefresh()
        }
        .onDisappear {
            refreshTask?.cancel()
            refreshTask = nil
        }
    }

    private var categoryFilterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                filterChip(title: L10n.string("Tümü"), isSelected: filter == nil) {
                    filter = nil
                }
                ForEach(DevLogCategory.allCases, id: \.self) { category in
                    filterChip(title: category.rawValue, isSelected: filter == category) {
                        filter = category
                    }
                }
            }
            .padding(.vertical, 4)
        }
        .textCase(nil)
    }

    private func filterChip(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.caption)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(isSelected ? TrailhoundBrandColors.brandBottom : Color.secondary.opacity(0.15))
                .foregroundStyle(isSelected ? Color.white : Color.primary)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func reload() {
        lines = DevLog.shared.recentLines(maxCount: 500)
    }

    /// The escape hatch for when the share sheet will not cooperate: paste the log straight into
    /// a message. Nothing to present, nothing to go wrong.
    private func copyLogToClipboard() {
        let text = DevLog.shared.readAllText()
        UIPasteboard.general.string = text
        DevLog.shared.log(.general, "log copied to clipboard bytes=\(text.utf8.count)")
    }

    private func startAutoRefresh() {
        refreshTask?.cancel()
        refreshTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled else { return }
                reload()
            }
        }
    }

    private func tint(for line: String) -> Color {
        if line.contains("[ERR]") { return .red }
        if line.contains("[WARN]") { return .orange }
        return .primary
    }
}

/// Writes the file only when the system actually requests the share payload, so opening the
/// screen stays cheap and the export is never stale.
private struct DevLogExportItem: Transferable {
    /// `.txt`, not `.log`: the payload is declared as `.plainText`, whose extension is `txt`, and
    /// some share targets refuse to build a preview when the two disagree.
    static let fileName = "trailhound-debug.txt"

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .plainText) { _ in
            let text = DevLog.shared.readAllText()
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
            do {
                try text.write(to: url, atomically: true, encoding: .utf8)
            } catch {
                // A throwing representation shows an empty sheet with no explanation, so leave a
                // trail in the log the user can still copy out by hand.
                DevLog.shared.error(.general, "log export failed: \(error.localizedDescription)")
                throw error
            }
            DevLog.shared.log(.general, "log exported bytes=\(text.utf8.count)")
            return SentTransferredFile(url)
        }
    }
}

#Preview {
    NavigationStack { DevLogView() }
}
