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
                if viewModel.visible.isEmpty && viewModel.showSkeleton {
                    // Web's `CardsSkeleton count={4} minWidth={260}` — the same
                    // four cards in the same adaptive grid, so the screen does
                    // not resize when the real accounts land.
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(0..<accountSkeletonCards, id: \.self) { _ in
                            VStack(alignment: .leading, spacing: 10) {
                                SkeletonBar(height: 12, fraction: 0.4)
                                SkeletonBar(height: 24, fraction: 0.7)
                            }
                            .padding(16)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.surface)
                            .clipShape(RoundedRectangle(cornerRadius: SanvyaRadius.radiusLg, style: .continuous))
                        }
                    }
                    .padding(16)
                } else if viewModel.visible.isEmpty {
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
            .sanvyaFormPresentation(isPresented: $showingCreateSheet) {
                CreateAccountView()
            }
            .sanvyaFormPresentation(item: $editingAccount) { entry in
                EditAccountView(accountId: entry.id)
            }
        }
    }
}

/// A skeleton bar occupying a fraction of its card's width — web's
/// `<Skeleton w="40%">`.
///
/// A `GeometryReader` because SwiftUI has no percentage frame and the cards are
/// adaptive: a fixed width would read as 40% on a phone and as a stub on an
/// iPad. The outer `.frame(height:)` is what stops the reader claiming all the
/// vertical space it is offered.
private struct SkeletonBar: View {
    let height: CGFloat
    let fraction: CGFloat

    var body: some View {
        GeometryReader { geo in
            SanvyaSkeleton(height: height).frame(width: geo.size.width * fraction)
        }
        .frame(height: height)
    }
}

/// Placeholder cards drawn while the first sync lands.
///
/// Web's `CardsSkeleton count={4}`; kept identical so the two clients settle at
/// the same visual weight while they wait.
private let accountSkeletonCards = 4

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
