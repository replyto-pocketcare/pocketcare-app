package com.sanvya.app.domain.splits

/**
 * Choosing who to invite to a group.
 *
 * Ported from the multi-select block in `apps/web/app/groups/[id]/page.tsx`.
 * It is small, it is entirely rules, and every one of those rules is a place
 * two platforms drift: which connections are offered, in what order, how many,
 * when a typed address becomes an option, and what makes two invitees the same
 * person. None of that is visible in a screenshot, which is exactly why it is
 * here and vector-pinned rather than written twice.
 *
 * Mirrors iOS's Invite.swift.
 */

/** Someone who can be invited: an existing connection, or a typed address. */
data class Invitee(
    /** The connection's user id. Null for an address typed into the box. */
    val id: String?,
    val name: String,
    val email: String,
)

/**
 * What makes two invitees the same person.
 *
 * Web's `i.id ?? i.email.toLowerCase()`. The lowercasing is load-bearing: a
 * typed `Ravi@x.com` and a typed `ravi@x.com` are one invitation, and sending
 * two would produce two links and two rows.
 */
fun inviteeKey(invitee: Invitee): String = invitee.id ?: invitee.email.lowercase()

/**
 * Web's `looksLikeEmail`, character for character.
 *
 * Deliberately not a real address validator. Its whole job is to decide
 * whether to OFFER "invite this address"; the edge function is what actually
 * accepts or rejects it, and a stricter regex here would refuse valid
 * addresses the server would have taken.
 */
private val EMAIL_SHAPE = Regex("^[^\\s@]+@[^\\s@]+\\.[^\\s@]+$")

fun looksLikeEmail(text: String): Boolean = EMAIL_SHAPE.matches(text.trim())

/**
 * Web caps the suggestion list at six and renders it in full.
 *
 * Its own comment says why the cap exists rather than a scroller: the list is
 * an inline card inside the modal, and giving it its own scroll area would trap
 * a swipe that belongs to the modal. Narrowing is done by typing instead.
 */
const val INVITE_SUGGEST_MAX = 6

/** What the invite box should show for the current query and selection. */
data class InviteSuggestions(
    /** At most [INVITE_SUGGEST_MAX], in the order connections arrived. */
    val suggestions: List<Invitee>,
    /** How many further matches were cut. Web renders "+N more". */
    val moreMatches: Int,
    /** Whether to offer the typed text as a brand-new invitee. */
    val canAddTypedEmail: Boolean,
)

/**
 * Filter the connection list for the invite box.
 *
 * A connection is offered when it has an email at all, is not already in the
 * group, is not already picked, and matches the query on name OR email. The
 * "has an email" test is first for a reason: a connection without one cannot be
 * invited by this route, and offering it would produce a row nobody can act on.
 *
 * [connections] is taken in its query order, not re-sorted -- web renders
 * whatever `useConnections()` returns and a native re-sort would silently give
 * the two clients different first six.
 */
fun inviteSuggestions(
    connections: List<Invitee>,
    memberIds: List<String>,
    selected: List<Invitee>,
    query: String,
): InviteSuggestions {
    val trimmed = query.trim()
    val needle = trimmed.lowercase()
    val pickedKeys = selected.map(::inviteeKey).toSet()
    val members = memberIds.toSet()

    val matches = connections.filter { c ->
        c.email.isNotEmpty() &&
            c.id !in members &&
            inviteeKey(c) !in pickedKeys &&
            (needle.isEmpty() || c.name.lowercase().contains(needle) || c.email.lowercase().contains(needle))
    }

    val shown = matches.take(INVITE_SUGGEST_MAX)
    return InviteSuggestions(
        suggestions = shown,
        moreMatches = matches.size - shown.size,
        // Offered only when the typed address is not one we already know: web
        // checks the FULL connection list, not just the matches, so typing a
        // connection's address in full offers their row and not a duplicate.
        canAddTypedEmail = looksLikeEmail(trimmed) &&
            connections.none { it.email.lowercase() == needle } &&
            selected.none { it.email.lowercase() == needle },
    )
}

/**
 * The outcome of inviting everyone in the chips.
 *
 * Web loops one call per invitee and counts three buckets. The split matters to
 * the user: "added" means they are in the group now, "links" means an address
 * that is not a Sanvya account yet and somebody has to send the link on.
 */
data class InviteOutcome(
    val added: Int,
    val links: Int,
    /** Display names (or addresses) of the ones that threw. */
    val failed: List<String>,
) {
    val isEmpty: Boolean get() = added == 0 && links == 0 && failed.isEmpty()
}

/** The label a failed invitee is reported under -- name if it has one. */
fun inviteeLabel(invitee: Invitee): String = invitee.name.ifEmpty { invitee.email }
