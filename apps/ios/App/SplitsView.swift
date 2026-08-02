import SwiftUI
import Domain

struct SplitsView: View {
    @Binding var isDrawerOpen: Bool
    @State private var selectedTab = 0 // 0: Groups & Trips, 1: Friends
    @State private var viewModel = SplitsViewModel()
    @State private var selectedSettleFriend: SplitsViewModel.FriendEdgeUiModel? = nil
    @State private var showingCreateSheet = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 14) {
                Picker("Section", selection: $selectedTab) {
                    Text("Groups & Trips").tag(0)
                    Text("Friends").tag(1)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)

                ScrollView {
                    if selectedTab == 0 {
                        VStack(spacing: 14) {
                            ForEach(viewModel.groups) { grp in
                                PocketCard {
                                    VStack(alignment: .leading, spacing: 10) {
                                        HStack {
                                            Text(grp.name)
                                                .font(.headline)
                                                .fontWeight(.bold)
                                                .foregroundColor(Color.text)

                                            Text(grp.kind.capitalized)
                                                .font(.caption2)
                                                .fontWeight(.medium)
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 2)
                                                .background(Color.surface2)
                                                .cornerRadius(6)

                                            Spacer()

                                            Text("\(grp.memberCount) members")
                                                .font(.caption)
                                                .foregroundColor(Color.text2)
                                        }

                                        if let dates = grp.dateRange {
                                            Text(dates)
                                                .font(.caption)
                                                .foregroundColor(Color.text2)
                                        }

                                        Text(grp.netBalanceFormatted)
                                            .font(.subheadline)
                                            .fontWeight(.bold)
                                            .foregroundColor(grp.isOwed ? Color.positive : Color.accent)
                                    }
                                }
                            }
                        }
                        .padding(16)
                    } else {
                        VStack(spacing: 12) {
                            ForEach(viewModel.friends) { friend in
                                RowTile(
                                    title: friend.name,
                                    subtitle: friend.balanceFormatted,
                                    trailing: {
                                        if !friend.isOwed {
                                            PrimaryButton("Settle Up") {
                                                selectedSettleFriend = friend
                                            }
                                            .frame(width: 90)
                                        }
                                    }
                                )
                            }
                        }
                        .padding(16)
                    }
                }
            }
            .background(Color.bg.ignoresSafeArea())
            .navigationTitle("Splits")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        withAnimation(.spring()) {
                            isDrawerOpen.toggle()
                        }
                    } label: {
                        Image(systemName: "line.3.horizontal")
                            .imageScale(.large)
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button(action: { showingCreateSheet = true }) {
                        Image(systemName: "plus")
                            .font(.headline)
                            .foregroundColor(Color.accent)
                    }
                }
            }

            .sheet(isPresented: $showingCreateSheet) {
                CreateGroupView()
            }
            .sheet(item: $selectedSettleFriend) { friend in
                PayViaUpiSheet(counterpartyName: friend.name, vpa: friend.vpa ?? "payee@upi", amountMinor: 120000)
            }
        }
    }
}



#Preview {
    SplitsView(isDrawerOpen: .constant(false))
}
