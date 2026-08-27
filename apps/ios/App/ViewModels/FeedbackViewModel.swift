import Data
import Domain
import Factory
import Foundation

/**
 Sending feedback — ported from `apps/web/src/ui/BugReport.tsx`.

 Mirrors Android's FeedbackViewModel.
 */
@Observable
@MainActor
final class FeedbackViewModel {
    @ObservationIgnored
    @Injected(\.feedbackRepository) private var feedbackRepository
    @ObservationIgnored
    @Injected(\.authRepository) private var authRepository

    /// "bug" | "suggestion".
    var kind = "bug"
    var severity = "medium"
    var area = ""
    var title = ""
    var descriptionText = ""
    /**
     Default ON.

     Web's comment: "the whole point is that the diagnosis arrives without the
     user having to do anything. It's redacted, and the checkbox says so."
     */
    var includeLog = true

    private(set) var busy = false
    private(set) var done = false
    /// An i18n KEY, resolved by the sheet. Nil when there is nothing wrong.
    private(set) var errorKey: String?

    var isBug: Bool { kind == "bug" }
    var canSubmit: Bool {
        !busy && !descriptionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Web's `reset()` — back to a blank form, staying on the sheet.
    func reset() {
        kind = "bug"
        severity = "medium"
        area = ""
        title = ""
        descriptionText = ""
        includeLog = true
        busy = false
        done = false
        errorKey = nil
    }

    func clearError() { errorKey = nil }

    /**
     File it.

     `route` is the shell's current tab, standing in for web's `pathname`; the
     rest of the captured context is the platform's and is gathered by the
     sheet, which is the only layer that can see a window.
     */
    func submit(route: String, userAgent: String, viewport: String, online: Bool) {
        guard !busy else { return }
        let text = descriptionText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            errorKey = isBug ? "errNeedBug" : "errNeedSuggestion"
            return
        }
        busy = true
        errorKey = nil

        let draft = BugReportDraft(
            kind: kind,
            // Web writes `severity: isBug ? severity : null` — a suggestion has
            // no severity, and storing "medium" for one would put it in the
            // wrong bucket of a queue sorted by how urgent things are.
            severity: isBug ? severity : nil,
            area: area,
            title: title,
            description: text,
            diagnostics: includeLog
                ? diagnosticsReport(context: [("version", feedbackAppVersion), ("route", route)])
                : nil,
            route: route,
            platform: "iOS",
            userAgent: userAgent,
            viewport: viewport,
            online: online
        )

        Task { [weak self] in
            guard let self else { return }
            guard let userId = await self.resolveUserId() else {
                self.busy = false
                self.errorKey = "errSubmit"
                return
            }
            do {
                _ = try await self.feedbackRepository.submit(userId: userId, draft: draft)
                self.busy = false
                self.done = true
            } catch {
                self.busy = false
                self.errorKey = "errSubmit"
            }
        }
    }

    /// See GoalsViewModel.swift's identical helper — `??`'s RHS is an
    /// `@autoclosure`, so `currentUserId ?? (try? await ensureUser())` is
    /// invalid Swift; use an explicit if/else instead.
    private func resolveUserId() async -> String? {
        if let existing = authRepository.currentUserId { return existing }
        return try? await authRepository.ensureUser()
    }
}
