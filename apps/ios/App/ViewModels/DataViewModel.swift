import Foundation
import Observation
import Factory
import Data
import Domain

/// Import & export — ported from apps/web/app/data/page.tsx.
///
/// The CSV itself is Domain's (vector-tested) and the two database halves are
/// `LedgerRepository.exportTransactionsCsv` / `importTransactions`. What is here
/// is the screen's state machine: parse a picked file, preview it, import it.
///
/// **File picking is NOT here.** Choosing where a file goes has no shared shape
/// across a browser anchor, a UIDocumentPicker and Android's SAF, so the view
/// hands this model the TEXT it read and takes back the text to write.
///
/// Mirrors apps/android/.../ui/data/DataViewModel.kt.
@Observable
@MainActor
final class DataViewModel {
    @ObservationIgnored
    @Injected(\.ledgerRepository) private var ledgerRepository
    @ObservationIgnored
    @Injected(\.prefsRepository) private var prefsRepository
    @ObservationIgnored
    @Injected(\.authRepository) private var authRepository

    // Export
    private(set) var exporting = false
    private(set) var exportMessage: String?
    /// Set when a CSV is ready; the view turns it into a file.
    var pendingExport: ExportPayload?

    // Import
    var adapterId = importAdapters[0].id { didSet { clearParse() } }
    var skipDuplicates = true
    private(set) var fileName: String?
    private(set) var parsedRows: [CanonRow]?
    private(set) var parseError: String?
    private(set) var importing = false
    private(set) var result: LedgerRepository.ImportResult?

    /// Web blocks import during the free trial and shows the upgrade note.
    /// Unknown-until-loaded, so the screen shows neither the form nor the
    /// upsell before the entitlement has been read — the same "keep the gate
    /// closed, but say nothing yet" rule the Statements screen uses.
    private(set) var isPaidUser = false
    private(set) var entitlementLoaded = false

    private var task: Task<Void, Never>?

    struct ExportPayload: Identifiable, Sendable {
        let id = UUID()
        let csv: String
        let suggestedName: String
    }

    func start() {
        guard task == nil else { return }
        task = Task { [weak self] in
            guard let self else { return }
            do {
                for try await row in try self.prefsRepository.watchEntitlement() {
                    self.isPaidUser = Domain.isPaid(
                        tier: row?.tier,
                        premiumTrialStartDate: row?.premiumTrialStartDate,
                        compTier: row?.compTier,
                        compUntil: row?.compUntil,
                        now: Date()
                    )
                    self.entitlementLoaded = true
                }
            } catch {
                // Offline or unreadable: the gate stays closed and the screen
                // stays quiet rather than showing an upsell it cannot justify.
                print("Error watching entitlement: \(error)")
            }
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
    }

    // MARK: - Export

    func exportCsv() {
        guard !exporting else { return }
        exporting = true
        exportMessage = nil
        Task { [weak self] in
            guard let self else { return }
            defer { self.exporting = false }
            do {
                let out = try await self.ledgerRepository.exportTransactionsCsv()
                if out.count == 0 {
                    self.exportMessage = S.Data.noExport
                    return
                }
                self.pendingExport = ExportPayload(
                    csv: out.csv,
                    suggestedName: "sanvya-transactions-\(String(isoToday().prefix(10))).csv"
                )
                self.exportMessage = S.Data.exported(count: out.count)
            } catch {
                self.exportMessage = S.Data.exportFailed(msg: String(describing: error))
            }
        }
    }

    // MARK: - Import

    /// The view read a file; parse it with the selected adapter.
    func parse(fileName: String, text: String) {
        self.fileName = fileName
        result = nil
        parseError = nil
        parsedRows = nil
        let rows = parseWithAdapter(adapterId, text, nowIso: nowIso())
        if rows.isEmpty {
            parseError = S.Data.noRows
            return
        }
        parsedRows = rows
    }

    func failedToRead(_ message: String) {
        clearParse()
        parseError = S.Data.readFail(msg: message)
    }

    func runImport() {
        guard let rows = parsedRows, !importing else { return }
        importing = true
        result = nil
        Task { [weak self] in
            guard let self else { return }
            defer { self.importing = false }
            guard let userId = await self.resolveUserId() else { return }
            do {
                let out = try await self.ledgerRepository.importTransactions(
                    userId: userId,
                    rows: rows,
                    baseCurrency: baseCurrencyNow(),
                    nowIso: nowIso(),
                    skipDuplicates: self.skipDuplicates
                )
                self.result = out
                self.parsedRows = nil
                self.fileName = nil
            } catch {
                self.result = LedgerRepository.ImportResult(
                    created: 0, skipped: 0, failed: rows.count,
                    errors: [String(describing: error)]
                )
            }
        }
    }

    private func clearParse() {
        parsedRows = nil
        parseError = nil
        result = nil
    }

    /// Spelled out rather than `currentUserId ?? (try? await ensureUser())`:
    /// `??`'s right-hand side is `@autoclosure` and cannot hold an `await`.
    private func resolveUserId() async -> String? {
        if let existing = authRepository.currentUserId { return existing }
        return try? await authRepository.ensureUser()
    }
}
