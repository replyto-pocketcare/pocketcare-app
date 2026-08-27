package com.sanvya.app.data.repository

import com.powersync.PowerSyncDatabase
import com.sanvya.app.domain.feedback.FEEDBACK_APP_VERSION
import com.sanvya.app.domain.feedback.FEEDBACK_DIAGNOSTICS_CAP
import com.sanvya.app.domain.feedback.FEEDBACK_USER_AGENT_CAP

/**
 * What the user typed, plus what the app knows without asking.
 *
 * Ported from `apps/web/src/ui/BugReport.tsx`'s `submit()` + `captureContext()`.
 * The split matters: everything above [diagnostics] is the user's, everything
 * below is captured, and web's own copy promises exactly that list and nothing
 * else ("Automatically included: app version, current page, device, and
 * connection status").
 */
data class BugReportDraft(
    /** "bug" | "suggestion". */
    val kind: String,
    /** One of `FEEDBACK_SEVERITIES`, or null for a suggestion. */
    val severity: String?,
    /** One of `FEEDBACK_AREAS`, or null. Stored in English -- see Feedback.kt. */
    val area: String?,
    val title: String?,
    val description: String,
    /** The redacted diagnostics log, or null when the box was cleared. */
    val diagnostics: String?,
    /** Web sends its pathname. The native equivalent is the route/tab id. */
    val route: String,
    /** "Android" | "iOS". Web sniffs the user agent for the same two names. */
    val platform: String,
    /** Device and OS, capped. Web stores `navigator.userAgent`. */
    val userAgent: String,
    /** "WIDTHxHEIGHT". Web stores `innerWidth x innerHeight`. */
    val viewport: String,
    val online: Boolean,
)

/**
 * Filing a bug report or a suggestion.
 *
 * One insert, into a table the native schema has carried since it was
 * generated. There is no read side: `bug_reports` is a queue somebody else
 * works, and web has no list view for it either.
 *
 * Mirrors iOS's FeedbackRepository.
 */
class FeedbackRepository(private val db: PowerSyncDatabase) {

    /**
     * Write the report.
     *
     * Offline is fine and is the normal case for the reports that matter most:
     * PowerSync queues the insert and it uploads when the connection comes
     * back. Web's version has the same property and says so in its own comment
     * on `insertRow`.
     */
    suspend fun submit(userId: String, draft: BugReportDraft): String = insertRow(
        db = db,
        table = "bug_reports",
        userId = userId,
        values = mapOf(
            "kind" to draft.kind,
            // Web writes `severity: isBug ? severity : null` -- a suggestion has
            // no severity, and storing "medium" for one would put it in the
            // wrong bucket of a queue sorted by how urgent things are.
            "severity" to draft.severity,
            "area" to draft.area?.takeIf { it.isNotEmpty() },
            "title" to draft.title?.trim()?.takeIf { it.isNotEmpty() },
            "description" to draft.description.trim(),
            "status" to "open",
            "diagnostics" to draft.diagnostics?.take(FEEDBACK_DIAGNOSTICS_CAP),
            "app_version" to FEEDBACK_APP_VERSION,
            "route" to draft.route,
            "platform" to draft.platform,
            "user_agent" to draft.userAgent.take(FEEDBACK_USER_AGENT_CAP),
            "viewport" to draft.viewport,
            "online" to if (draft.online) 1L else 0L,
        ),
    )
}
