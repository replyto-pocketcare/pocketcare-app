import SwiftUI

/// Accounts list — ported from apps/web/app/accounts/page.tsx per
/// docs/mobile/screen-specs/accounts.md. The spec deferred web's
/// MultiCurrencyCard; it is built now (`AcrossCurrenciesCard`), so a user
/// holding two currencies sees the same share bar, native amounts and
/// base-converted amounts web shows. Rewritten 2026-08-05: previously a
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
                Button(viewModel.showArchived ? S.Accounts.hideArchived : S.Accounts.showArchived(count: String(viewModel.archivedCount))) {
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
                    // An explicit VStack, not two siblings in the ScrollView's
                    // ViewBuilder: a scroll view's content is one view, and
                    // relying on an implicit stack for it is how a section ends
                    // up overlapping the list under it.
                    VStack(spacing: 0) {
                        // Web renders <MultiCurrencyCard /> above the grid.
                        if let breakdown = viewModel.breakdown {
                            AcrossCurrenciesCard(breakdown: breakdown)
                                .padding(.horizontal, 16)
                                .padding(.top, 16)
                        }
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
                Text(accountTypeName(acct.type) + " · " + acct.currency + (acct.isArchived ? " · " + S.Accounts.archivedTag : ""))
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

/// The localised name of an account type.
///
/// Web is ``t(`type.${account.type}`, account.type.replace("_", " "))`` -- a
/// lookup with the raw type as its fallback, so a type added to the schema
/// before its string still renders as something readable. The `default` branch
/// is that fallback, not a shrug.
///
/// Deliberately NOT `accountTypeLabel` from AccountFormComponents.swift: that
/// one is `type.replacingOccurrences(of: "_", with: " ").capitalized`, i.e.
/// English, and it belongs to the create/edit chip rows.
private func accountTypeName(_ type: String) -> String {
    switch type {
    case "savings": return S.Accounts.typeSavings
    case "current": return S.Accounts.typeCurrent
    case "credit_card": return S.Accounts.typeCreditCard
    case "cash": return S.Accounts.typeCash
    case "mutual_funds": return S.Accounts.typeMutualFunds
    case "stocks": return S.Accounts.typeStocks
    case "demat": return S.Accounts.typeDemat
    default: return type.replacingOccurrences(of: "_", with: " ")
    }
}

/// "Across currencies" — where the money is held, converted to base.
///
/// Port of web's `MultiCurrencyCard` (accounts/page.tsx): a stacked share bar
/// over one row per currency, each showing the native amount and — for anything
/// that is not the base currency — its converted value. Mirrors Android's
/// `AcrossCurrenciesCard`.
private struct AcrossCurrenciesCard: View {
    let breakdown: AccountsViewModel.CurrencyBreakdownUiModel

    /// Web's CCY_COLORS, in order. A palette, not theming: the bar segments
    /// only have to be distinguishable from each other.
    /// `sanvyaTeal`, not `teal`: SwiftUI declares `Color.teal` itself, and ours
    /// lives in an extension, so the plain name is shadowed rather than
    /// replaced. The generator emits an unambiguous twin for exactly the tokens
    /// that collide -- the failure this avoids is not a build error but Apple's
    /// teal rendering silently in place of the brand one.
    private let palette: [Color] = [
        Color.accent, Color.sanvyaTeal, Color.forest, Color.warning, Color.positive, Color.accentSoft,
    ]

    var body: some View {
        SanvyaCard(padding: 20) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .lastTextBaseline) {
                    Text(S.Accounts.acrossCurrencies)
                        .font(.system(size: 17, weight: .bold))
                        .foregroundColor(Color.text)
                    Spacer()
                    Text(S.Accounts.totalCurrencies(
                        total: breakdown.totalFormatted,
                        count: String(breakdown.slices.count)
                    ))
                    .font(.footnote)
                    .foregroundColor(Color.text2)
                }

                // Stacked share bar. A GeometryReader because SwiftUI has no
                // percentage width and the card is adaptive; a zero-share slice
                // contributes nothing rather than a hairline.
                GeometryReader { geo in
                    HStack(spacing: 0) {
                        ForEach(Array(breakdown.slices.enumerated()), id: \.element.currency) { i, slice in
                            if slice.barSharePct > 0 {
                                Rectangle()
                                    .fill(palette[i % palette.count])
                                    .frame(width: geo.size.width * slice.barSharePct / 100)
                            }
                        }
                    }
                }
                .frame(height: 12)
                .background(Color.surface2)
                .clipShape(Capsule())

                VStack(spacing: 6) {
                    ForEach(Array(breakdown.slices.enumerated()), id: \.element.currency) { i, slice in
                        HStack(spacing: 8) {
                            Circle().fill(palette[i % palette.count]).frame(width: 9, height: 9)
                            Text(slice.currency).font(.footnote).fontWeight(.bold).foregroundColor(Color.text)
                            Text(slice.nativeFormatted).font(.footnote).foregroundColor(Color.text2)
                            Spacer()
                            Text(shareLabel(slice)).font(.footnote).foregroundColor(Color.text2)
                        }
                    }
                }

                Text(S.Accounts.convertedNote(base: breakdown.base))
                    .font(.system(size: 11.5))
                    .foregroundColor(Color.text2)
            }
        }
    }

    private func shareLabel(_ slice: AccountsViewModel.CurrencySliceUiModel) -> String {
        // The base currency shows no "≈ base" line -- it would restate the
        // amount already on the row.
        let prefix = slice.isBase ? "" : S.Accounts.approx(amount: slice.baseFormatted)
        return prefix + "\(slice.sharePct)%"
    }
}

#Preview {
    AccountsView()
}
