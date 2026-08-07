import SwiftUI
import Domain

/// Real port of apps/web/app/friends/page.tsx's hub (task #30). See
/// docs/mobile/screen-specs/splits.md. Replaces the previous version's
/// hardcoded `PayViaUpiSheet(..., amountMinor: 120000)` bug (every
/// settle-up used to show ₹1200 no matter the real balance) --
/// settle-up now lives on GroupDetailView, fed by real balances.
struct SplitsView: View {
    @Binding var isDrawerOpen: Bool
    @State private var selectedTab = 0 // 0: Groups & Trips, 1: Friends
    @State private var viewModel = SplitsViewModel()
    @State private var showingCreateSheet = false
    @State private var selectedGroupId: String?

    var body: some View {
        NavigationStack {
            Group {
                if let selectedGroupId {
                    GroupDetailView(groupId: selectedGroupId, onBack: { self.selectedGroupId = nil })
                } else {
                    hub
                }
            }
            .background(Color.bg.ignoresSafeArea())
            .navigationTitle(selectedGroupId != nil ? "" : "Splits")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // Same leading button toggles hamburger/back depending on
                // selection state -- matches LoansView's established
                // list/detail convention, not a new pattern.
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        if selectedGroupId != nil {
                            selectedGroupId = nil
                        } else {
                            withAnimation(.spring()) { isDrawerOpen.toggle() }
                        }
                    } label: {
                        Image(systemName: selectedGroupId != nil ? "chevron.left" : "line.3.horizontal")
                            .imageScale(.large)
                    }
                }
                if selectedGroupId == nil {
                    ToolbarItem(placement: .primaryAction) {
                        Button(action: { showingCreateSheet = true }) {
                            Image(systemName: "plus").font(.headline).foregroundColor(Color.accent)
                        }
                    }
                }
            }
            .sheet(isPresented: $showingCreateSheet) {
                CreateGroupView(viewModel: viewModel, onCreated: { id in
                    showingCreateSheet = false
                    selectedGroupId = id
                })
            }
        }
    }

    @ViewBuilder
    private var hub: some View {
        VStack(spacing: 14) {
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
                Text("Groups & Trips").tag(0)
                Text("Friends").tag(1)
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
                                    subtitle: friend.isOwed ? "Owes you" : "You owe",
                                    action: {
                                        Task {
                                            if let id = await viewModel.openOrCreateDirectGroup(otherUserId: friend.id, currency: "INR") {
                                                selectedGroupId = id
                                            }
                                        }
                                    },
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
    SplitsView(isDrawerOpen: .constant(false))
}
