import Foundation
import Observation
import Factory
import Data
import Domain

/// Manage categories — ported from apps/web/app/settings/categories/page.tsx.
///
/// The tree itself is `Domain.categoryTree`, vector-tested. What is here is the
/// live query, the draft state for the add row, and the three writes.
///
/// **Not ported: the Auto-categorize card.** It drives
/// `apps/web/src/categorize/` — a 905-line on-device merchant-matching engine
/// with its own seed taxonomy, normaliser and semantic matcher. That is its own
/// port, not a corner of this screen, and it is the same engine
/// `transactions/new` defers. Tracked in PARITY_AUDIT.
@Observable
@MainActor
final class CategoriesViewModel {
    @ObservationIgnored
    @Injected(\.ledgerRepository) private var ledgerRepository
    @ObservationIgnored
    @Injected(\.authRepository) private var authRepository

    var search = "" { didSet { rebuild() } }
    var newName = ""
    var newKind = "expense" { didSet { rebuild() } }
    var newParentId = ""

    private(set) var nodes: [CategoryTreeNode] = []
    /// The add row's parent options: top-level categories of the kind being
    /// added. Web recomputes this from `newKind`, so switching kind changes the
    /// list — and can leave `newParentId` pointing at a category of the other
    /// kind, which `rebuild` clears.
    private(set) var parentOptions: [TaxonomyCategory] = []

    private var expanded: Set<String> = []
    private var all: [TaxonomyCategory] = []
    private var task: Task<Void, Never>?

    func isExpanded(_ id: String) -> Bool { expanded.contains(id) }

    func toggle(_ id: String) {
        if expanded.contains(id) { expanded.remove(id) } else { expanded.insert(id) }
        rebuild()
    }

    func start() {
        guard task == nil else { return }
        task = Task { [weak self] in
            guard let self else { return }
            do {
                for try await rows in try self.ledgerRepository.watchCategories() {
                    // Sorted here rather than in the repository: every other
                    // reader of watchCategories() wants name order, and this
                    // screen is the only one that groups by kind first, which is
                    // what web's `ORDER BY kind, name` does.
                    self.all = rows
                        .map { TaxonomyCategory(id: $0.id, name: $0.name, kind: $0.kind, parentId: $0.parentId) }
                        .sorted { ($0.kind, $0.name) < ($1.kind, $1.name) }
                    self.rebuild()
                }
            } catch { print("Error watching categories: \(error)") }
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
    }

    private func rebuild() {
        nodes = categoryTree(all, search: search, expanded: expanded)
        parentOptions = all.filter { $0.parentId == nil && $0.kind == newKind }
        if !newParentId.isEmpty && !parentOptions.contains(where: { $0.id == newParentId }) {
            newParentId = ""
        }
    }

    var canAdd: Bool { !newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    func add() {
        let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        let kind = newKind
        let parentId = newParentId.isEmpty ? nil : newParentId
        newName = ""
        newParentId = ""
        Task { [weak self] in
            guard let self, let userId = await self.resolveUserId() else { return }
            _ = try? await self.ledgerRepository.createCategory(
                userId: userId, name: name, kind: kind, parentId: parentId
            )
        }
    }

    func rename(_ id: String, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        Task { [weak self] in
            try? await self?.ledgerRepository.renameCategory(id: id, name: trimmed)
        }
    }

    func delete(_ id: String) {
        Task { [weak self] in
            try? await self?.ledgerRepository.deleteCategory(id: id)
        }
    }

    /// Spelled out rather than `currentUserId ?? (try? await ensureUser())`:
    /// `??`'s right-hand side is `@autoclosure` and cannot hold an `await`.
    private func resolveUserId() async -> String? {
        if let existing = authRepository.currentUserId { return existing }
        return try? await authRepository.ensureUser()
    }
}

/// Manage labels — ported from apps/web/app/settings/labels/page.tsx.
@Observable
@MainActor
final class LabelsViewModel {
    @ObservationIgnored
    @Injected(\.ledgerRepository) private var ledgerRepository
    @ObservationIgnored
    @Injected(\.authRepository) private var authRepository

    /// Web's default swatch for a new label and its fallback for one saved
    /// without a colour. The value is web's; it is a literal there too.
    static let defaultColor = "#b06a4f"

    var search = "" { didSet { rebuild() } }
    var newName = ""
    var newColor = LabelsViewModel.defaultColor

    private(set) var labels: [LabelRow] = []
    private var all: [LabelRow] = []
    private var task: Task<Void, Never>?

    var canAdd: Bool { !newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    func start() {
        guard task == nil else { return }
        task = Task { [weak self] in
            guard let self else { return }
            do {
                for try await rows in try self.ledgerRepository.watchLabels() {
                    self.all = rows
                    self.rebuild()
                }
            } catch { print("Error watching labels: \(error)") }
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
    }

    private func rebuild() {
        // Web tests `!search`, so only the empty string turns filtering off —
        // a single space really does filter. Copied, not corrected, so the two
        // platforms and the browser agree.
        guard !search.isEmpty else {
            labels = all
            return
        }
        let needle = search.lowercased()
        labels = all.filter { $0.name.lowercased().contains(needle) }
    }

    func add() {
        let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        let color = newColor
        newName = ""
        Task { [weak self] in
            guard let self, let userId = await self.resolveUserId() else { return }
            _ = try? await self.ledgerRepository.createLabel(userId: userId, name: name, color: color)
        }
    }

    func save(_ id: String, name: String, color: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        Task { [weak self] in
            try? await self?.ledgerRepository.updateLabel(id: id, name: trimmed, color: color)
        }
    }

    func delete(_ id: String) {
        Task { [weak self] in
            try? await self?.ledgerRepository.deleteLabel(id: id)
        }
    }

    private func resolveUserId() async -> String? {
        if let existing = authRepository.currentUserId { return existing }
        return try? await authRepository.ensureUser()
    }
}
