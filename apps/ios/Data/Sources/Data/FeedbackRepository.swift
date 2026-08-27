import Domain
import Foundation
import PowerSync

/**
 What the user typed, plus what the app knows without asking.

 Ported from `apps/web/src/ui/BugReport.tsx`'s `submit()` + `captureContext()`.
 The split matters: everything above `diagnostics` is the user's, everything
 below is captured, and web's own copy promises exactly that list and nothing
 else ("Automatically included: app version, current page, device, and
 connection status").
 */
public struct BugReportDraft: Sendable {
    /// "bug" | "suggestion".
    public let kind: String
    /// One of `feedbackSeverities`, or nil for a suggestion.
    public let severity: String?
    /// One of `feedbackAreas`, or nil. Stored in English — see Feedback.swift.
    public let area: String?
    public let title: String?
    public let description: String
    /// The redacted diagnostics log, or nil when the toggle was cleared.
    public let diagnostics: String?
    /// Web sends its pathname. The native equivalent is the route/tab id.
    public let route: String
    /// "iOS" | "Android". Web sniffs the user agent for the same two names.
    public let platform: String
    /// Device and OS, capped. Web stores `navigator.userAgent`.
    public let userAgent: String
    /// "WIDTHxHEIGHT". Web stores `innerWidth x innerHeight`.
    public let viewport: String
    public let online: Bool

    public init(
        kind: String,
        severity: String?,
        area: String?,
        title: String?,
        description: String,
        diagnostics: String?,
        route: String,
        platform: String,
        userAgent: String,
        viewport: String,
        online: Bool
    ) {
        self.kind = kind
        self.severity = severity
        self.area = area
        self.title = title
        self.description = description
        self.diagnostics = diagnostics
        self.route = route
        self.platform = platform
        self.userAgent = userAgent
        self.viewport = viewport
        self.online = online
    }
}

/**
 Filing a bug report or a suggestion.

 One insert, into a table the native schema has carried since it was generated.
 There is no read side: `bug_reports` is a queue somebody else works, and web
 has no list view for it either.

 Mirrors Android's FeedbackRepository.
 */
public final class FeedbackRepository: @unchecked Sendable {
    private let db: PowerSyncDatabaseProtocol

    public init(db: PowerSyncDatabaseProtocol) {
        self.db = db
    }

    /**
     Write the report.

     Offline is fine and is the normal case for the reports that matter most:
     PowerSync queues the insert and it uploads when the connection comes back.
     Web's version has the same property.
     */
    @discardableResult
    public func submit(userId: String, draft: BugReportDraft) async throws -> String {
        let title = draft.title?.trimmingCharacters(in: .whitespacesAndNewlines)
        return try await insertRow(
            db: db,
            table: "bug_reports",
            userId: userId,
            values: [
                "kind": draft.kind,
                // Web writes `severity: isBug ? severity : null` — a suggestion
                // has no severity, and storing "medium" for one would put it in
                // the wrong bucket of a queue sorted by how urgent things are.
                "severity": draft.severity,
                "area": (draft.area?.isEmpty ?? true) ? nil : draft.area,
                "title": (title?.isEmpty ?? true) ? nil : title,
                "description": draft.description.trimmingCharacters(in: .whitespacesAndNewlines),
                "status": "open",
                "diagnostics": draft.diagnostics.map { String($0.prefix(feedbackDiagnosticsCap)) },
                "app_version": feedbackAppVersion,
                "route": draft.route,
                "platform": draft.platform,
                "user_agent": String(draft.userAgent.prefix(feedbackUserAgentCap)),
                "viewport": draft.viewport,
                "online": draft.online ? 1 : 0,
            ]
        )
    }
}
