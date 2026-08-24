import SwiftUI

/// Accounts list — ported from apps/web/app/accounts/page.tsx per
/// docs/mobile/screen-specs/accounts.md. Rewritten 2026-08-05: previously a
/// flat name/balance list with no color bar, archived toggle, per-account
/// net-worth checkbox, or edit navigation -- none of which existed. New
/// account still opens as a sheet (existing pattern); edit opens as a sheet
/// too, keyed by account id (no separate push-navigation infra here yet).
struct AccountsView: View {
    @State private var showingCreateSheet = false
    @State private var editingAccount: EditingAccountId?
    @State private var viewModel = AccountsViewModel()

    /// Local Identifiable wrapper for `.sheet(item:)` -- kept file-scoped
    /// rather than a global `extension String: Identifiable` so this doesn't
    /// leak a module-wide conformance for one screen's convenience.
    struct EditingAccountId: Identifiable {
        let id: String
    }

    private let columns = [GridItem(.adaptive(minimum: 260), spacing: 12)]

    var body: some View {
        SanvyaPage(S.Accounts.title) {
            if viewModel.archivedCount > 0 {
                Button(viewModel.showArchived ? S.Accounts.hideArchived : "Show archived (\(viewModel.archivedCount))") {
                    viewModel.toggleShowArchived()
                }
                .font(.caption)
            }
            Button(action: { showingCreateSheet = true }) {
                Image(systemName: "plus")
                    .font(.headline)
                    .foregroundColor(Color.accent)
            }
        } content: {
            ScrollView {
                if viewModel.visible.isEmpty {
                    Text(S.Accounts.noAccounts)
                        .foregroundColor(Color.text2)
                        .padding(.top, 48)
                } else {
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(viewModel.visible) { acct in
                            AccountCardView(
                                acct: acct,
                                onToggleIncludeInNetWorth: {
                                    viewModel.toggleIncludeInNetWorth(id: acct.id, current: acct.includeInNetWorth)
                                },
                                onUnarchive: { viewModel.setArchived(id: acct.id, archived: false) },
                                onEdit: { editingAccount = EditingAccountId(id: acct.id) }
                            )
                        }
                    }
                    .padding(16)
                }
            }
            .sheet(isPresented: $showingCreateSheet) {
                CreateAccountView()
            }
            .sheet(item: $editingAccount) { entry in
                EditAccountView(accountId: entry.id)
            }
        }
    }
}

private struct AccountCardView: View {
    let acct: AccountsViewModel.AccountUiModel
    let onToggleIncludeInNetWorth: () -> Void
    let onUnarchive: () -> Void
    let onEdit: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            Rectangle()
                .fill(accountColor(explicit: acct.color, id: acct.id))
                .frame(width: 6)
            VStack(alignment: .leading, spacing: 4) {
                Text("\(acct.type.replacingOccurrences(of: "_", with: " ")) · \(acct.currency)" + (acct.isArchived ? " · Archived" : ""))
                    .font(.system(size: 12))
                    .foregroundColor(Color.text2)
                Text(acct.name)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(Color.text)
                Text(acct.balanceFormatted)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(Color.text)
                HStack {
                    if acct.isArchived {
                        Button(S.Accounts.unarchive, action: onUnarchive)
                            .font(.system(size: 12))
                    } else {
                        Button(action: onToggleIncludeInNetWorth) {
                            HStack(spacing: 4) {
                                Image(systemName: acct.includeInNetWorth ? "checkmark.square.fill" : "square")
                                Text(S.Accounts.inNetWorth)
                            }
                            .font(.system(size: 12))
                            .foregroundColor(Color.text2)
                        }
                    }
                    Spacer()
                    Button(S.Accounts.edit, action: onEdit)
                        .font(.system(size: 12))
                }
                .padding(.top, 4)
            }
            .padding(18)
        }
        .background(Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: SanvyaRadius.radiusLg, style: .continuous))
        .opacity(acct.isArchived ? 0.6 : 1)
    }
}

#Preview {
    AccountsView()
}
