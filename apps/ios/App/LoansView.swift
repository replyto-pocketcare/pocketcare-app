import SwiftUI


struct LoansView: View {
    @Binding var isDrawerOpen: Bool
    
    @State private var showMarkPaidDialog = false
    @State private var selectedLoan: LoansViewModel.LoanUiModel? = nil
    
    @State private var viewModel = LoansViewModel()
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    ForEach(viewModel.loans) { loan in
                        LoanCard(loan: loan) {
                            selectedLoan = loan
                            showMarkPaidDialog = true
                        }
                    }
                }
                .padding(16)
            }
            .background(Color.bg.ignoresSafeArea())
            .navigationTitle("Loans & Recurring")
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
            .navigationBarTitleDisplayMode(.inline)

            .alert("Mark EMI Paid", isPresented: $showMarkPaidDialog, presenting: selectedLoan) { loan in
                Button("Confirm") {
                    // TODO: Handle confirm
                }
                Button("Cancel", role: .cancel) {}
            } message: { loan in
                Text("Confirm payment of \(loan.emiAmount) for \(loan.name)? This will record an expense and update the schedule.")
            }
        }
    }
}

struct LoanCard: View {
    let loan: LoansViewModel.LoanUiModel
    let onMarkPaid: () -> Void
    
    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Text(loan.name)
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundColor(Color.text)
                Spacer()
                Text(loan.status)
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(Color.positive)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.positive.opacity(0.2))
                    .cornerRadius(8)
            }
            
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Total Amount").font(.caption).foregroundColor(Color.text2)
                    Text(loan.totalAmount).font(.subheadline).fontWeight(.semibold).foregroundColor(Color.text)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("EMI Amount").font(.caption).foregroundColor(Color.text2)
                    Text(loan.emiAmount).font(.subheadline).fontWeight(.semibold).foregroundColor(Color.accent)
                }
            }
            
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Remaining EMIs").font(.caption).foregroundColor(Color.text2)
                    Text("\(loan.remainingEmis) / \(loan.totalEmis)").font(.subheadline).fontWeight(.medium).foregroundColor(Color.text)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Next Due").font(.caption).foregroundColor(Color.text2)
                    Text(loan.nextDueDate).font(.subheadline).fontWeight(.medium).foregroundColor(Color.text)
                }
            }
            
            Divider().background(Color.bg)
            
            Button(action: onMarkPaid) {
                Text("Mark Next EMI Paid")
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.surface2)
                    .foregroundColor(Color.text)
                    .cornerRadius(12)
            }
        }
        .padding(16)
        .background(Color.surface)
        .cornerRadius(16)
    }
}

#Preview {
    LoansView(isDrawerOpen: .constant(false))
}
