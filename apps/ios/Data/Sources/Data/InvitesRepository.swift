import Foundation
import Supabase

/**
 Split-group invites.

 Its own type rather than a method on `SplitsRepository`, because
 SplitsRepository's own header says invites are out of its scope and it is
 right: everything there reads and writes the local PowerSync database, while
 this is one HTTPS call to an Edge Function.

 Ported from `acceptInvite` + `edgeFnMessage` in `apps/web/src/splits/write.ts`.
 Mirrors Android's InvitesRepository.kt.
 */
public struct InviteError: Error, Sendable {
    public let message: String
    public init(message: String) { self.message = message }
}

private struct AcceptInviteResponse: Decodable {
    let group_id: String?
    let error: String?
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

public final class InvitesRepository: @unchecked Sendable {
    private let client: SupabaseClient

    public init(client: SupabaseClient) {
        self.client = client
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
