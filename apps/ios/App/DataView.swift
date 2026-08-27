import SwiftUI
import UniformTypeIdentifiers
import Data
import Domain

/// Import & export — ported from apps/web/app/data/page.tsx.
///
/// **The file halves are `.fileExporter` and `.fileImporter`**, SwiftUI's own
/// document-picker wrappers, where web uses an anchor download and an
/// `<input type="file">`. There is no shared shape to port here; what IS shared
/// is everything either side of the picker, which is Domain's and the
/// repository's.
struct DataView: View {
    @State private var viewModel = DataViewModel()
    @State private var showExporter = false
    @State private var showImporter = false

    var body: some View {
        @Bindable var vm = viewModel
        ScrollView {
            SanvyaPage(S.Data.title) {
                Text(S.Data.introPre)
                    .sanvyaStyle(SanvyaType.statLabel)
                    .foregroundStyle(Color.text2)

                exportCard
                importCard(vm: vm)
            }
            .padding(16)
        }
        .background(Color.bg.ignoresSafeArea())
        .onAppear { viewModel.start() }
        .onDisappear { viewModel.cancel() }
        .onChange(of: viewModel.pendingExport?.id) { _, newValue in
            showExporter = newValue != nil
        }
        .fileExporter(
            isPresented: $showExporter,
            document: viewModel.pendingExport.map { CsvDocument(text: $0.csv) },
            contentType: .commaSeparatedText,
            defaultFilename: viewModel.pendingExport?.suggestedName
        ) { _ in
            viewModel.pendingExport = nil
        }
        .fileImporter(
            isPresented: $showImporter,
            // `.plainText` alongside `.commaSeparatedText`: plenty of banks
            // hand out a .csv the system types as plain text, and a picker that
            // greys out the file the user came to import is a dead end.
            allowedContentTypes: [.commaSeparatedText, .plainText, .text],
            allowsMultipleSelection: false
        ) { outcome in
            handlePickedFile(outcome)
        }
    }

    private var exportCard: some View {
        SanvyaCard(padding: 20) {
            VStack(alignment: .leading, spacing: 10) {
                Text(S.Data.export)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color.text)
                Text(S.Data.exportNote)
                    .sanvyaStyle(SanvyaType.statLabel)
                    .foregroundStyle(Color.text2)
                SanvyaButton(action: { viewModel.exportCsv() }) {
                    Text(viewModel.exporting ? S.Data.preparing : S.Data.exportBtn)
                }
                .disabled(viewModel.exporting)
                if let message = viewModel.exportMessage {
                    Text(message)
                        .sanvyaStyle(SanvyaType.statLabel)
                        .foregroundStyle(Color.text2)
                }
            }
        }
    }

    @ViewBuilder
    private func importCard(vm: Bindable<DataViewModel>) -> some View {
        SanvyaCard(padding: 20) {
            VStack(alignment: .leading, spacing: 12) {
                Text(S.Data.`import`)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color.text)

                if !viewModel.entitlementLoaded {
                    // Nothing: the gate is closed but unexplained until the
                    // entitlement has actually been read.
                    EmptyView()
                } else if !viewModel.isPaidUser {
                    Text(S.Data.trialNote)
                        .sanvyaStyle(SanvyaType.statLabel)
                        .foregroundStyle(Color.text)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.accentGhost, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                } else {
                    importForm
                }
            }
        }
    }

    @ViewBuilder
    private var importForm: some View {
        VStack(alignment: .leading, spacing: 12) {
            labelled(S.Data.fileFormat) {
                // Chips, not a wheel — the same choice every other one-of-a-few
                // control in this app makes.
                FlowLayout(spacing: 8) {
                    ForEach(importAdapters) { adapter in
                        SanvyaChip(adapter.label, isActive: viewModel.adapterId == adapter.id) {
                            viewModel.adapterId = adapter.id
                        }
                    }
                }
            }

            labelled(S.Data.csvFile) {
                SanvyaButton(ghost: true, action: { showImporter = true }) {
                    Text(viewModel.fileName ?? S.Data.csvFile)
                }
            }

            Toggle(isOn: Binding(
                get: { viewModel.skipDuplicates },
                set: { viewModel.skipDuplicates = $0 }
            )) {
                Text(S.Data.skipDup)
                    .sanvyaStyle(SanvyaType.statLabel)
                    .foregroundStyle(Color.text)
            }
            .tint(Color.accent)

            if let error = viewModel.parseError {
                Text(error)
                    .sanvyaStyle(SanvyaType.statLabel)
                    .foregroundStyle(Color.negative)
            }

            if let rows = viewModel.parsedRows {
                preview(rows)
            }

            if let result = viewModel.result {
                VStack(alignment: .leading, spacing: 4) {
                    Text(S.Data.resultLine(
                        created: result.created,
                        skipped: result.skipped,
                        failed: result.failed
                    ))
                    .sanvyaStyle(SanvyaType.statLabel)
                    .foregroundStyle(Color.text)
                    if !result.errors.isEmpty {
                        Text(S.Data.firstIssues(issues: result.errors.prefix(3).joined(separator: "; ")))
                            .font(.system(size: 12))
                            .foregroundStyle(Color.text2)
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.surface2, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }

            Text(S.Data.footerNote)
                .font(.system(size: 12))
                .foregroundStyle(Color.text2)
        }
    }

    @ViewBuilder
    private func preview(_ rows: [CanonRow]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(S.Data.foundPreview(count: rows.count, file: viewModel.fileName ?? ""))
                .sanvyaStyle(SanvyaType.statLabel)
                .foregroundStyle(Color.text)

            // Six rows, as web previews — enough to see the columns landed in
            // the right places without pretending this is the ledger.
            VStack(spacing: 6) {
                ForEach(Array(rows.prefix(6).enumerated()), id: \.offset) { _, row in
                    HStack(spacing: 8) {
                        Text(isoLabel(row.date, "d MMM y"))
                            .frame(width: 92, alignment: .leading)
                        Text(row.type)
                            .frame(width: 68, alignment: .leading)
                        Text("\(row.currency) \(row.amount, format: .number)")
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text(row.account)
                            .lineLimit(1)
                    }
                    .font(.system(size: 12))
                    .foregroundStyle(Color.text2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            SanvyaButton(action: { viewModel.runImport() }) {
                Text(viewModel.importing ? S.Data.importing : S.Data.importBtn(count: rows.count))
            }
            .disabled(viewModel.importing)
        }
    }

    @ViewBuilder
    private func labelled<Content: View>(
        _ label: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .sanvyaStyle(SanvyaType.statLabel)
                .foregroundStyle(Color.text2)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func handlePickedFile(_ outcome: Result<[URL], Error>) {
        switch outcome {
        case .success(let urls):
            guard let url = urls.first else { return }
            // A picked file arrives security-scoped; without the accessor the
            // read fails with a permission error that reads like a missing file.
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            do {
                let text = try String(contentsOf: url, encoding: .utf8)
                viewModel.parse(fileName: url.lastPathComponent, text: text)
            } catch {
                viewModel.failedToRead(String(describing: error))
            }
        case .failure(let error):
            viewModel.failedToRead(String(describing: error))
        }
    }
}

/// The document `.fileExporter` writes. A `FileDocument` rather than a raw
/// `Data` write because the exporter owns the destination — the user picks it,
/// including iCloud Drive, where the app has no path of its own.
private struct CsvDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.commaSeparatedText] }

    let text: String

    init(text: String) { self.text = text }

    init(configuration: ReadConfiguration) throws {
        // Export-only; the importer reads through `.fileImporter` instead.
        text = ""
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Foundation.Data(text.utf8))
    }
}

#Preview {
    DataView()
}
