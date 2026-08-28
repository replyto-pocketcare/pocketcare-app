import SwiftUI
import Domain

/// Real port of apps/web/app/friends/page.tsx's hub (task #30). See
/// docs/mobile/screen-specs/splits.md. Replaces the previous version's
/// hardcoded `PayViaUpiSheet(..., amountMinor: 120000)` bug (every
/// settle-up used to show ₹1200 no matter the real balance) --
/// settle-up now lives on GroupDetailView, fed by real balances.
struct SplitsView: View {
    /// A group to open on arrival — set by an accepted invite, cleared here once
    /// consumed. Defaults to a constant so the ordinary tab switch passes
    /// nothing and this stays a one-way channel for deep links.
    @Binding var openGroupId: String?

    @State private var selectedTab = 0 // 0: Groups & Trips, 1: Friends
    @State private var viewModel = SplitsViewModel()
    @State private var showingCreateSheet = false
    @State private var selectedGroupId: String?
    @State private var person: SplitsViewModel.FriendEdgeUiModel?

    init(openGroupId: Binding<String?> = .constant(nil)) {
        self._openGroupId = openGroupId
    }

    var body: some View {
        SanvyaPage(selectedGroupId != nil ? "" : S.Splits.eyebrow) {
            Button(action: { showingCreateSheet = true }) {
                Image(systemName: "plus").font(.headline).foregroundColor(Color.accent)
            }
        } content: {
            Group {
                if let selectedGroupId {
                    GroupDetailView(groupId: selectedGroupId, onBack: { self.selectedGroupId = nil })
                } else {
                    hub
                }
            }
            .registerBack(selectedGroupId != nil) { selectedGroupId = nil }
            // Both hooks: `task` catches a group set before this view existed
            // (the invite is accepted on a cover, above the shell), `onChange`
            // catches one that arrives while the Splits tab is already open.
            .task { consumeOpenGroup() }
        .sanvyaFormPresentation(item: $person) { p in
            PersonSheet(
                person: p,
                viewModel: viewModel,
                onSettleUp: {
                    person = nil
                    Task {
                        if let id = await viewModel.openOrCreateDirectGroup(otherUserId: p.id, currency: baseCurrencyNow()) {
                            selectedGroupId = id
                        }
                    }
                },
                onDismiss: { person = nil; viewModel.clearPersonLedger() }
            )
        }
            .onChange(of: openGroupId) { _, _ in consumeOpenGroup() }
            .sanvyaFormPresentation(isPresented: $showingCreateSheet) {
                CreateGroupView(viewModel: viewModel, onCreated: { id in
                    showingCreateSheet = false
                    selectedGroupId = id
                })
            }
        }
    }

    private func consumeOpenGroup() {
        guard let id = openGroupId, !id.isEmpty else { return }
        selectedGroupId = id
        openGroupId = nil
    }

    @ViewBuilder
    private var hub: some View {
        VStack(spacing: 14) {
            // Web renders this ABOVE everything else on /friends: a payment
            // waiting on your confirmation is not a groups-or-friends
            // question, it is a thing to answer before anything else on the
            // screen means what it says. It draws nothing when there is
            // nothing pending.
            PendingSettlementsCard(viewModel: viewModel)

            if let ov = viewModel.overview {
                PocketCard {
                    VStack(spacing: 8) {
                        HStack {
                            Text("Your net position").font(.caption).foregroundColor(.text2)
                            Spacer()
                            Text(ov.netPositionFormatted).font(.title2).fontWeight(.bold).foregroundColor(ov.netPositive ? .positive : .negative)
                        }
                        HStack {
                            Text("Owed to you: \(ov.owedFormatted)").font(.caption2).foregroundColor(.text2)
                            Spacer()
                            Text("You owe: \(ov.oweFormatted)").font(.caption2).foregroundColor(.text2)
                        }
                    }
                }
                .padding(.horizontal, 16)
            }

            Picker("Section", selection: $selectedTab) {
                Text(S.Splits.groupsAndTrips).tag(0)
                Text(S.Splits.sectionsFriends).tag(1)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)

            ScrollView {
                if !viewModel.loaded {
                    ProgressView().padding(.top, 40)
                } else if selectedTab == 0 {
                    if viewModel.groups.isEmpty {
                        emptyState(title: "No groups yet", body: "Create a group to start splitting expenses with friends or on a trip.")
                    } else {
                        VStack(spacing: 14) {
                            ForEach(viewModel.groups) { grp in
                                Button(action: { selectedGroupId = grp.id }) {
                                    groupTile(grp)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(16)
                    }
                } else {
                    if viewModel.friends.isEmpty {
                        emptyState(title: "No balances yet", body: "Once you split an expense with someone, they'll show up here.")
                    } else {
                        VStack(spacing: 12) {
                            ForEach(viewModel.friends) { friend in
                                RowTile(
                                    title: friend.name,
                                    subtitle: friend.isOwed ? S.Splits.sectionsOwesYou : S.Splits.sectionsYouOwe,
                                    // Web opens a PERSON sheet here, not the
                                    // direct group. The balance is a
                                    // cross-group figure, so the group is the
                                    // wrong container for it — and jumping
                                    // straight into one group hid every other
                                    // group's share of the same debt, which is
                                    // the bug this replaces.
                                    action: { person = friend },
                                    trailing: {
                                        Text(friend.balanceFormatted)
                                            .font(.subheadline).fontWeight(.bold)
                                            .foregroundColor(friend.isOwed ? .positive : .negative)
                                    }
                                )
                            }
                        }
                        .padding(16)
                    }
                }
            }
        }
    }

    private func groupTile(_ grp: SplitsViewModel.SplitGroupUiModel) -> some View {
        PocketCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(grp.name).font(.headline).fontWeight(.bold).foregroundColor(Color.text)
                    Text(grp.kind.capitalized)
                        .font(.caption2).fontWeight(.medium)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Color.surface2).cornerRadius(6)
                    Spacer()
                    Text("\(grp.memberCount) members").font(.caption).foregroundColor(Color.text2)
                }
                Text(grp.netBalanceFormatted)
                    .font(.subheadline).fontWeight(.bold)
                    .foregroundColor(grp.net == 0 ? .text2 : (grp.isOwed ? .positive : .negative))
            }
        }
    }

    private func emptyState(title: String, body: String) -> some View {
        VStack(spacing: 8) {
            Text(title).font(.headline).fontWeight(.bold)
            Text(body).font(.caption).foregroundColor(.text2).multilineTextAlignment(.center)
        }
        .padding(32)
    }
}

#Preview {
    SplitsView()
}

/**
 One person's balance with you, and the transactions behind it.

 Ported from the person Modal in `apps/web/app/friends/page.tsx`. Two things
 about its shape are deliberate and were copied rather than improved on:

 The total is at the TOP and large. The sheet's job is "how much, and settle it"
 — everything else is supporting evidence.

 The itemised lines are BEHIND A BUTTON, not shown by default. Web's own comment
 says why: a wall of line items pushed the two actions below the fold and made
 the sheet read as a statement. They are one tap away when you want to check,
 which is exactly how often you want them.

 The lines come from `personLedger()`, which existed on both repositories with
 no caller — so until now the app could tell you THAT you owed someone and not
 one line of WHY.

 Mirrors Android's PersonSheet in SplitsScreen.kt.
 */
private struct PersonSheet: View {
    let person: SplitsViewModel.FriendEdgeUiModel
    let viewModel: SplitsViewModel
    let onSettleUp: () -> Void
    let onDismiss: () -> Void

    @State private var showAllLines = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(person.name).font(.title2).fontWeight(.bold).foregroundStyle(Color.text)
                        if person.net != 0 {
                            Text(person.net > 0 ? S.Splits.owesYouInline : S.Splits.youOweInline)
                                .font(.subheadline)
                                .foregroundStyle(person.net > 0 ? Color.positive : Color.negative)
                        }
                    }

                    HStack(alignment: .lastTextBaseline) {
                        Text(person.net > 0 ? S.Splits.totalOwedToYou : S.Splits.totalYouOwe)
                            .font(.system(size: 12.5))
                            .foregroundStyle(Color.text2)
                        Spacer(minLength: 10)
                        Text(person.balanceFormatted)
                            .font(.system(size: 30, weight: .bold))
                            .foregroundStyle(person.net > 0 ? Color.positive : Color.negative)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .frame(maxWidth: .infinity)
                    .background(Color.surface2)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                    if !viewModel.personLines.isEmpty && !showAllLines {
                        Button(S.Splits.viewLines(count: viewModel.personLines.count)) { showAllLines = true }
                            .buttonStyle(.bordered)
                            .frame(maxWidth: .infinity)
                    }

                    if !viewModel.personLines.isEmpty && showAllLines {
                        VStack(spacing: 8) {
                            ForEach(viewModel.personLines, id: \.id) { line in
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(line.description).font(.subheadline).lineLimit(1)
                                        if !line.date.isEmpty {
                                            Text(dayMonthLabel(line.date)
                                                 + (line.kind == "settlement" ? " · \(S.Splits.settlementTag)" : ""))
                                                .font(.system(size: 11.5))
                                                .foregroundStyle(Color.text2)
                                        }
                                    }
                                    Spacer(minLength: 10)
                                    Text((line.net > 0 ? "+" : "−") + formatMoney(abs(line.net), baseCurrencyNow()))
                                        .font(.subheadline).fontWeight(.semibold)
                                        .foregroundStyle(line.net > 0 ? Color.positive : Color.negative)
                                }
                            }
                            Button(S.Splits.hideLines) { showAllLines = false }
                                .font(.caption)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }

                    Button(S.Splits.settleUp, action: onSettleUp)
                        .buttonStyle(.borderedProminent)
                        .frame(maxWidth: .infinity)
                }
                .padding(16)
            }
            .background(Color.bg.ignoresSafeArea())
            .navigationTitle(person.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(S.Translation.commonClose, action: onDismiss).foregroundColor(Color.text2)
                }
            }
        }
        .task { viewModel.loadPersonLedger(person.id) }
    }
}
