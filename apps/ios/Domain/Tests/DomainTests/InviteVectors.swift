import Foundation
@testable import Domain

// Wires Invite.swift into FunctionRegistry.
//
// A SPEC, not a capture: the rules live inside a React component in
// `groups/[id]/page.tsx` and cannot be imported, so these expectations were
// written by transcribing that block line by line and running the
// transcription. What they prove is that iOS and Android agree with each other
// and with what was read off web.
//
// The cases that earn their keep are the ones nobody would think to check:
//
//   * a connection with NO email is not offered, because it cannot be invited
//     by this route and offering it produces a row nobody can act on;
//   * a typed address that already belongs to a connection is NOT offered as a
//     new invitee — web tests the whole connection list, not the filtered
//     matches, so their row appears instead of a duplicate;
//   * `Ravi@X.com` typed twice is one invitee, because the identity key
//     lowercases. Two would mean two links and two rows.
//
// Suggestions travel as KEYS rather than whole rows: the fixture pins WHICH
// connections survive and in what order, and echoing the inputs back would
// double the file and test nothing extra.

private func toInvitee(_ any: Any) -> Invitee {
    let d = any as! [String: Any]
    return Invitee(
        id: d["id"] as? String,
        name: d["name"] as! String,
        email: d["email"] as! String
    )
}

private func toInvitees(_ any: Any) -> [Invitee] {
    (any as! [Any]).map(toInvitee)
}

func registerInviteVectors() {
    let domain = "splits-invite"

    FunctionRegistry.register(domain: domain, fn: "inviteSuggestions") { input in
        let d = input as! [String: Any]
        let result = inviteSuggestions(
            connections: toInvitees(d["connections"]!),
            memberIds: (d["memberIds"] as! [Any]).map { $0 as! String },
            selected: toInvitees(d["selected"]!),
            query: d["query"] as! String
        )
        return [
            "suggestions": result.suggestions.map(inviteeKey),
            "moreMatches": result.moreMatches,
            "canAddTypedEmail": result.canAddTypedEmail,
        ] as [String: Any]
    }

    FunctionRegistry.register(domain: domain, fn: "looksLikeEmail") { input in
        let d = input as! [String: Any]
        return looksLikeEmail(d["text"] as! String)
    }

    FunctionRegistry.register(domain: domain, fn: "inviteeKey") { input in
        let d = input as! [String: Any]
        return inviteeKey(toInvitee(d["invitee"]!))
    }

    FunctionRegistry.register(domain: domain, fn: "inviteeLabel") { input in
        let d = input as! [String: Any]
        return inviteeLabel(toInvitee(d["invitee"]!))
    }
}
