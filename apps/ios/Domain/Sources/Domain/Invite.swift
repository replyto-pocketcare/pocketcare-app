import Foundation

/**
 Choosing who to invite to a group.

 Ported from the multi-select block in `apps/web/app/groups/[id]/page.tsx`. It
 is small, it is entirely rules, and every one of those rules is a place two
 platforms drift: which connections are offered, in what order, how many, when a
 typed address becomes an option, and what makes two invitees the same person.
 None of that is visible in a screenshot, which is exactly why it is here and
 vector-pinned rather than written twice.

 Mirrors Android's Invite.kt.
 */

/// Someone who can be invited: an existing connection, or a typed address.
public struct Invitee: Equatable, Sendable, Hashable {
    /// The connection's user id. Nil for an address typed into the box.
    public let id: String?
    public let name: String
    public let email: String

    public init(id: String?, name: String, email: String) {
        self.id = id
        self.name = name
        self.email = email
    }
}

/**
 What makes two invitees the same person.

 Web's `i.id ?? i.email.toLowerCase()`. The lowercasing is load-bearing: a typed
 `Ravi@x.com` and a typed `ravi@x.com` are one invitation, and sending two would
 produce two links and two rows.
 */
public func inviteeKey(_ invitee: Invitee) -> String {
    invitee.id ?? invitee.email.lowercased()
}

/**
 Web's `looksLikeEmail`, character for character.

 Deliberately not a real address validator. Its whole job is to decide whether
 to OFFER "invite this address"; the edge function is what actually accepts or
 rejects it, and a stricter regex here would refuse valid addresses the server
 would have taken.
 */
public func looksLikeEmail(_ text: String) -> Bool {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.range(of: "^[^\\s@]+@[^\\s@]+\\.[^\\s@]+$", options: .regularExpression) != nil
}

/**
 Web caps the suggestion list at six and renders it in full.

 Its own comment says why the cap exists rather than a scroller: the list is an
 inline card inside the modal, and giving it its own scroll area would trap a
 swipe that belongs to the modal. Narrowing is done by typing instead.
 */
public let inviteSuggestMax = 6

/// What the invite box should show for the current query and selection.
public struct InviteSuggestions: Equatable, Sendable {
    /// At most `inviteSuggestMax`, in the order connections arrived.
    public let suggestions: [Invitee]
    /// How many further matches were cut. Web renders "+N more".
    public let moreMatches: Int
    /// Whether to offer the typed text as a brand-new invitee.
    public let canAddTypedEmail: Bool

    public init(suggestions: [Invitee], moreMatches: Int, canAddTypedEmail: Bool) {
        self.suggestions = suggestions
        self.moreMatches = moreMatches
        self.canAddTypedEmail = canAddTypedEmail
    }
}

/**
 Filter the connection list for the invite box.

 A connection is offered when it has an email at all, is not already in the
 group, is not already picked, and matches the query on name OR email. The "has
 an email" test is first for a reason: a connection without one cannot be
 invited by this route, and offering it would produce a row nobody can act on.

 `connections` is taken in its query order, not re-sorted — web renders whatever
 `useConnections()` returns and a native re-sort would silently give the two
 clients different first six.
 */
public func inviteSuggestions(
    connections: [Invitee],
    memberIds: [String],
    selected: [Invitee],
    query: String
) -> InviteSuggestions {
    let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
    let needle = trimmed.lowercased()
    let pickedKeys = Set(selected.map(inviteeKey))
    let members = Set(memberIds)

    let matches = connections.filter { c in
        guard !c.email.isEmpty else { return false }
        if let id = c.id, members.contains(id) { return false }
        if pickedKeys.contains(inviteeKey(c)) { return false }
        if needle.isEmpty { return true }
        return c.name.lowercased().contains(needle) || c.email.lowercased().contains(needle)
    }

    let shown = Array(matches.prefix(inviteSuggestMax))
    return InviteSuggestions(
        suggestions: shown,
        moreMatches: matches.count - shown.count,
        // Offered only when the typed address is not one we already know: web
        // checks the FULL connection list, not just the matches, so typing a
        // connection's address in full offers their row and not a duplicate.
        canAddTypedEmail: looksLikeEmail(trimmed)
            && !connections.contains { $0.email.lowercased() == needle }
            && !selected.contains { $0.email.lowercased() == needle }
    )
}

/**
 The outcome of inviting everyone in the chips.

 Web loops one call per invitee and counts three buckets. The split matters to
 the user: "added" means they are in the group now, "links" means an address
 that is not a Sanvya account yet and somebody has to send the link on.
 */
public struct InviteOutcome: Equatable, Sendable {
    public let added: Int
    public let links: Int
    /// Display names (or addresses) of the ones that threw.
    public let failed: [String]

    public init(added: Int, links: Int, failed: [String]) {
        self.added = added
        self.links = links
        self.failed = failed
    }

    public var isEmpty: Bool { added == 0 && links == 0 && failed.isEmpty }
}

/// The label a failed invitee is reported under — name if it has one.
public func inviteeLabel(_ invitee: Invitee) -> String {
    invitee.name.isEmpty ? invitee.email : invitee.name
}
