import SwiftUI

struct BudgetsView: View {
    @Binding var isDrawerOpen: Bool
    @State private var showingCreateSheet = false
    @State private var viewModel = BudgetsViewModel()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    ForEach(viewModel.budgets) { budget in
                        PocketCard {
                            VStack(alignment: .leading, spacing: 12) {
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(budget.name)
                                            .font(.headline)
                                            .fontWeight(.bold)
                                            .foregroundColor(Color.text)

                                        Text("\(budget.period.capitalized) • \(budget.categories.joined(separator: ", "))")
                                            .font(.caption)
                                            .foregroundColor(Color.text2)
                                    }
                                    Spacer()
                                    BudgetStatusBadge(progress: Double(budget.progress))
                                }

                                ProgressView(value: min(Double(budget.progress), 1.0))
                                    .tint(budget.progress > 1.0 ? Color.accent : (budget.progress > 0.8 ? Color.orange : Color.positive))
                                    .scaleEffect(x: 1, y: 1.5, anchor: .center)
                                    .padding(.vertical, 4)

                                HStack {
                                    Text("Spent: \(budget.spentFormatted)")
                                        .font(.subheadline)
                                        .fontWeight(.semibold)
                                        .foregroundColor(Color.text)
                                    Spacer()
                                    Text("Limit: \(budget.limitFormatted)")
                                        .font(.subheadline)
                                        .fontWeight(.semibold)
                                        .foregroundColor(Color.text2)
                                }
                            }
                        }
                    }
                }
                .padding(16)
            }
            .background(Color.bg.ignoresSafeArea())
            .navigationTitle("Budgets")
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
                CreateBudgetView()
            }
        }
    }
}

struct BudgetStatusBadge: View {
    let progress: Double

    var body: some View {
        let (label, bg, fg) = statusInfo

        Text(label)
            .font(.caption2)
            .fontWeight(.bold)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(bg)
            .foregroundColor(fg)
            .cornerRadius(8)
    }

    private var statusInfo: (String, Color, Color) {
        if progress > 1.0 {
            return ("Over Budget", Color.accentSoft, Color.surface)
        } else if progress > 0.8 {
            return ("Near Limit", Color.orange.opacity(0.3), Color.text)
        } else {
            return ("On Track", Color.positive.opacity(0.3), Color.text)
        }
    }
}

#Preview {
    BudgetsView(isDrawerOpen: .constant(false))
}
