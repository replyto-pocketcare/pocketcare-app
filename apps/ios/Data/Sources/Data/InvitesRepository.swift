import Foundation
import Supabase

/**
 Split-group invites.

 Its own type rather than a method on `SplitsRepository`, because
 SplitsRepository's own header says invites are out of its scope and it is
 right: everything there reads and writes the local PowerSync database, while
 this is one HTTPS call to an Edge Function.

 Ported from `createInvite` + `acceptInvite` + `edgeFnMessage` in
 `apps/web/src/splits/write.ts`. Mirrors Android's InvitesRepository.kt.
 */
public struct InviteError: Error, Sendable {
    public let message: String
    public init(message: String) { self.message = message }
}

private struct AcceptInviteResponse: Decodable {
    let group_id: String?
    let error: String?
}

private struct CreateInviteResponse: Decodable {
    let added: Bool?
    let already: Bool?
    let name: String?
    let link: String?
    let error: String?
}

/**
 What `split-invite` answered.

 Exactly one side is set: `added` with an optional `name`, or a `link`.
 `already` means they were in the group before this call — web reports that
 separately because "added" and "was already there" are different news.
 */
public struct InviteResult: Equatable, Sendable {
    public let added: Bool
    public let already: Bool
    public let name: String?
    public let link: String?

    public init(added: Bool, already: Bool = false, name: String? = nil, link: String? = nil) {
        self.added = added
        self.already = already
        self.name = name
        self.link = link
    }
}

/**
 Web's status-code fallbacks, kept for the case its own comment describes: a
 non-2xx whose body is not the JSON we expect. The Edge Function always sends
 `{ error }`, so in practice these never fire — they exist because the day one
 of them does, "Edge Function returned a non-2xx status code" is a dead end for
 the user AND for whoever reads the bug report.
 */
private func inviteStatusMessage(_ status: Int) -> String? {
    switch status {
    case 401: return "Please sign in to accept this invite."
    case 404: return "This invite link is invalid or has been removed."
    case 410: return "This invite has expired or was already used."
    default: return nil
    }
}

let inviteGenericFailure = "Could not accept the invite."
let inviteCreateFailure = "Could not create the invite."

public final class InvitesRepository: @unchecked Sendable {
    private let client: SupabaseClient

    public init(client: SupabaseClient) {
        self.client = client
    }

    /**
     Invite someone to a group.

     Web's own summary, which is the whole contract: "If `email` belongs to a
     registered Sanvya user they're added to the group directly; otherwise a
     shareable invite link is returned. With no email, always returns a link."

     The two outcomes are genuinely different things to tell the user, which is
     why `InviteResult` keeps them apart rather than returning a string: "added"
     means they are in the group now, "link" means somebody has to send it on.
     */
    public func createInvite(groupId: String, email: String? = nil) async throws -> InviteResult {
        // Web sends `email: undefined` for a general share link, which
        // JSON.stringify DROPS. An explicit null is a different request, so the
        // key is omitted rather than nulled.
        var body: [String: String] = ["group_id": groupId]
        if let email, !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            body["email"] = email.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        do {
            let res: CreateInviteResponse = try await client.functions.invoke(
                "split-invite",
                options: FunctionInvokeOptions(body: body)
            )
            if let err = res.error { throw InviteError(message: err) }
            if res.added == true {
                return InviteResult(added: true, already: res.already ?? false, name: res.name)
            }
            // Web falls back to building the link from the token and its own
            // origin. A phone has no origin, so the SERVER's link is required —
            // and if it is missing that is a real failure, not something to
            // paper over with a URL this app invented.
            guard let link = res.link else { throw InviteError(message: inviteCreateFailure) }
            return InviteResult(added: false, link: link)
        } catch let error as InviteError {
            throw error
        } catch let error as FunctionsError {
            if case let .httpError(code, data) = error {
                if let parsed = try? JSONDecoder().decode(CreateInviteResponse.self, from: data),
                   let err = parsed.error {
                    throw InviteError(message: err)
                }
                throw InviteError(message: inviteStatusMessage(code) ?? inviteCreateFailure)
            }
            throw InviteError(message: error.localizedDescription)
        } catch {
            throw InviteError(message: error.localizedDescription)
        }
    }

    /// Accept an invite by token. Returns the joined group's id.
    public func acceptInvite(token: String) async throws -> String {
        do {
            let res: AcceptInviteResponse = try await client.functions.invoke(
                "split-invite-accept",
                options: FunctionInvokeOptions(body: ["token": token])
            )
            if let err = res.error { throw InviteError(message: err) }
            guard let id = res.group_id else { throw InviteError(message: inviteGenericFailure) }
            return id
        } catch let error as InviteError {
            throw error
        } catch let error as FunctionsError {
            if case let .httpError(code, data) = error {
                if let parsed = try? JSONDecoder().decode(AcceptInviteResponse.self, from: data),
                   let err = parsed.error {
                    throw InviteError(message: err)
                }
                throw InviteError(message: inviteStatusMessage(code) ?? inviteGenericFailure)
            }
            throw InviteError(message: error.localizedDescription)
        } catch {
            throw InviteError(message: error.localizedDescription)
        }
    }
}
