import SwiftUI

struct AccountsView: View {
    @Binding var isDrawerOpen: Bool
    @State private var showingCreateSheet = false
    @State private var viewModel = AccountsViewModel()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    if viewModel.accounts.isEmpty {
                        Text("No accounts found.")
                            .foregroundColor(Color.text2)
                            .padding()
                    } else {
                        ForEach(viewModel.accounts) { acct in
                            RowTile(
                                title: acct.name,
                                subtitle: acct.typeLabel,
                                trailing: {
                                    Text(acct.balanceFormatted)
                                        .font(.title3)
                                        .fontWeight(.bold)
                                        .foregroundColor(acct.isNegative ? Color.accent : Color.positive)
                                }
                            )
                        }
                    }
                }
                .padding(16)
            }
            .background(Color.bg.ignoresSafeArea())
            .navigationTitle("Accounts")
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
                CreateAccountView()
            }
        }
    }
}

#Preview {
    AccountsView(isDrawerOpen: .constant(false))
}
