import Data
import Domain
import SwiftUI
import UIKit

/**
 Inviting people to a group — ported from the invite modal in
 `apps/web/app/groups/[id]/page.tsx`.

 **This was the single biggest thing a native user could not do.** Neither
 platform could add anyone to a group who was not already a connection, so a
 native user could create a group and then not fill it. Every other split
 feature sits downstream of having members.

 Two paths, both web's:

  * **Pick people.** Search existing connections, or type an address that is not
    one yet; each becomes a chip. Inviting loops one call per chip, because the
    Edge Function takes a single address — and a bounce on one address still
    adds the other three.
  * **Share a link.** No recipient at all. The server returns the URL; this app
    does NOT build one from the token, because unlike a browser it has no origin
    to build it from, and inventing a host would produce a link that silently
    goes nowhere.

 Which one you get for a typed address is the server's call, not this screen's:
 a registered user is added outright, anyone else produces a link. The summary
 line says which happened, because they are different news.

 Mirrors Android's InviteSheet.kt.
 */
struct InviteSheet: View {
    let groupName: String
    @Bindable var viewModel: GroupDetailViewModel
    let onClose: () -> Void

    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SanvyaH2(S.Groups.inviteTo(name: groupName))
            SanvyaMuted(S.Groups.inviteBody, style: SanvyaType.body.resized(13))

            if !viewModel.selected.isEmpty {
                chips
            }

            SanvyaInput(text: $viewModel.inviteQuery, placeholder: S.Groups.invitePlaceholder)

            let suggestions = viewModel.suggestions
            if !suggestions.suggestions.isEmpty || suggestions.canAddTypedEmail {
                suggestionCard(suggestions)
            }

            HStack(spacing: 8) {
                SanvyaButton(action: { viewModel.inviteSelected() }) {
                    Text(inviteLabel)
                }
                .disabled(viewModel.inviting || viewModel.selected.isEmpty)
                SanvyaChip(S.Groups.orShareLink, isActive: false) { viewModel.createShareLink() }
                Spacer(minLength: 0)
            }

            if let outcome = viewModel.inviteOutcome, !outcome.isEmpty {
                SanvyaCard(padding: 10, background: Color.surface2) {
                    Text(outcomeText(outcome))
                        .sanvyaStyle(SanvyaType.body.resized(13))
                        .foregroundStyle(Color.text)
                }
            }

            if let error = viewModel.inviteError {
                Text(S.Groups.error(msg: error))
                    .sanvyaStyle(SanvyaType.body.resized(13))
                    .foregroundStyle(Color.negative)
            }

            if let link = viewModel.inviteLink {
                linkPanel(link)
            }
        }
        // Web clears the panel every time the modal opens, so a previous run's
        // link and summary are never mistaken for this one's.
        .onAppear { viewModel.resetInvite() }
        .onChange(of: viewModel.inviteLink) { _, _ in copied = false }
    }

    private var inviteLabel: String {
        viewModel.selected.isEmpty
            ? S.Groups.invite
            : S.Groups.inviteCount(count: viewModel.selected.count)
    }

    /// The picked invitees, with web's inline remove button.
    private var chips: some View {
        FlowLayoutRows(items: viewModel.selected, perRow: 2) { invitee in
            HStack(spacing: 6) {
                Text(invitee.name.isEmpty ? invitee.email : invitee.name)
                    .sanvyaStyle(SanvyaType.body.resized(13))
                    .foregroundStyle(Color.text)
                    .lineLimit(1)
                Button { viewModel.removeInvitee(key: inviteeKey(invitee)) } label: {
                    Text(verbatim: "×")
                        .sanvyaStyle(SanvyaType.body.resized(13))
                        .foregroundStyle(Color.text2)
                        .frame(width: 18, height: 18)
                        .background(Color.surface2)
                        .clipShape(Circle())
                }
                .accessibilityLabel(S.Groups.remove)
            }
            .padding(.leading, 10)
            .padding(.trailing, 6)
            .padding(.vertical, 3)
            .background(Color.accentGhost)
            .clipShape(Capsule())
        }
    }

    @ViewBuilder
    private func suggestionCard(_ suggestions: InviteSuggestions) -> some View {
        SanvyaCard(padding: 4) {
            VStack(spacing: 0) {
                ForEach(suggestions.suggestions, id: \.self) { candidate in
                    Button { viewModel.addInvitee(candidate) } label: {
                        HStack(spacing: 8) {
                            Text(candidate.name)
                                .sanvyaStyle(SanvyaType.body.weighted(500))
                                .foregroundStyle(Color.text)
                            Spacer(minLength: 8)
                            Text(candidate.email)
                                .sanvyaStyle(SanvyaType.body.resized(12))
                                .foregroundStyle(Color.text2)
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                        .contentShape(Rectangle())
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                    }
                    .buttonStyle(SanvyaPressStyle())
                }
                if suggestions.canAddTypedEmail {
                    let typed = viewModel.inviteQuery.trimmingCharacters(in: .whitespacesAndNewlines)
                    Button {
                        // The typed address becomes BOTH the name and the
                        // address, as web does — there is nothing else to call
                        // someone who is not a user yet.
                        viewModel.addInvitee(Invitee(id: nil, name: typed, email: typed))
                    } label: {
                        Text(S.Groups.inviteAddEmail(email: typed))
                            .sanvyaStyle(SanvyaType.body)
                            .foregroundStyle(Color.accent)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                    }
                    .buttonStyle(SanvyaPressStyle())
                }
                if suggestions.moreMatches > 0 {
                    SanvyaMuted(
                        S.Groups.inviteNarrow(count: suggestions.moreMatches),
                        style: SanvyaType.body.resized(12)
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                }
            }
        }
    }

    @ViewBuilder
    private func linkPanel(_ link: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            // Read-only: the link is the server's and there is nothing to edit
            // in it. Selectable so it can be copied by hand as well.
            Text(link)
                .sanvyaStyle(SanvyaType.body.resized(13))
                .foregroundStyle(Color.text2)
                .textSelection(.enabled)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .background(Color.surface)
                .clipShape(RoundedRectangle(cornerRadius: SanvyaRadius.radiusSm, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: SanvyaRadius.radiusSm, style: .continuous)
                        .strokeBorder(Color.border, lineWidth: 1)
                }
            HStack {
                Spacer(minLength: 0)
                SanvyaButton(action: {
                    UIPasteboard.general.string = link
                    copied = true
                }) {
                    Text(copied ? S.Groups.copied : S.Groups.copyLink)
                }
            }
        }
    }

    /**
     Web's summary line: the three counts, joined by " · ", omitting the zeroes.

     The split is what the user needs: "added" means they are in the group now,
     "invite link created" means an address that is not a Sanvya account yet and
     somebody has to send the link on.
     */
    private func outcomeText(_ outcome: InviteOutcome) -> String {
        var parts: [String] = []
        if outcome.added > 0 { parts.append(S.Groups.invitedAdded(count: outcome.added)) }
        if outcome.links > 0 { parts.append(S.Groups.invitedLinks(count: outcome.links)) }
        if !outcome.failed.isEmpty {
            parts.append(S.Groups.invitedFailed(names: outcome.failed.joined(separator: ", ")))
        }
        return parts.joined(separator: " · ")
    }
}

/**
 A fixed-per-row wrap.

 `Layout` would measure properly; this does not, on purpose. A self-measuring
 flow re-runs on every keystroke in the box above it, and a predictable two-up
 row is legible at every Dynamic Type size — which a measured one is not, since
 it silently becomes one-up at the largest sizes anyway.
 */
private struct FlowLayoutRows<Item: Hashable, Content: View>: View {
    let items: [Item]
    let perRow: Int
    @ViewBuilder let content: (Item) -> Content

    var body: some View {
        let rows = stride(from: 0, to: items.count, by: perRow).map {
            Array(items[$0..<min($0 + perRow, items.count)])
        }
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 6) {
                    ForEach(row, id: \.self) { content($0) }
                    Spacer(minLength: 0)
                }
            }
        }
    }
}
