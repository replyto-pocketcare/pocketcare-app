import SwiftUI


struct InsightsView: View {
    @Binding var isDrawerOpen: Bool
    
    @State private var viewModel = InsightsViewModel()
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Month Comparison")
                        .font(.headline)
                        .fontWeight(.bold)
                        .padding(.top, 8)
                    
                    MonthComparisonCard(thisMonthSpending: viewModel.thisMonthSpending, lastMonthSpending: viewModel.lastMonthSpending)
                    
                    Text("Highlights")
                        .font(.headline)
                        .fontWeight(.bold)
                        .padding(.top, 8)
                    
                    ForEach(viewModel.insights) { insight in
                        InsightCard(insight: insight)
                    }
                }
                .padding(16)
            }
            .background(Color.bg.ignoresSafeArea())
            .navigationTitle("Insights")
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

        }
    }
}

struct MonthComparisonCard: View {
    let thisMonthSpending: String
    let lastMonthSpending: String
    
    var body: some View {
        VStack(spacing: 16) {
            HStack {
                VStack(alignment: .leading) {
                    Text("This Month").font(.caption).foregroundColor(Color.text2)
                    Text(thisMonthSpending).font(.title3).fontWeight(.bold).foregroundColor(Color.accent)
                }
                Spacer()
                VStack(alignment: .trailing) {
                    Text("Last Month").font(.caption).foregroundColor(Color.text2)
                    Text(lastMonthSpending).font(.headline).fontWeight(.medium).foregroundColor(Color.text)
                }
            }
            
            Divider().background(Color.bg)
            
            // Mock chart
            HStack(alignment: .bottom, spacing: 4) {
                RoundedRectangle(cornerRadius: 4).fill(Color.surface2).frame(height: 24)
                RoundedRectangle(cornerRadius: 4).fill(Color.accent.opacity(0.5)).frame(height: 32)
                RoundedRectangle(cornerRadius: 4).fill(Color.surface2).frame(height: 16)
                RoundedRectangle(cornerRadius: 4).fill(Color.accent).frame(height: 36)
                RoundedRectangle(cornerRadius: 4).fill(Color.surface2).frame(height: 20)
            }
            .frame(height: 40)
        }
        .padding(16)
        .background(Color.surface)
        .cornerRadius(16)
    }
}

struct InsightCard: View {
    let insight: InsightsViewModel.InsightUiModel
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                Text(insight.title)
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundColor(Color.text)
                
                Spacer()
                
                if let amount = insight.highlightAmount {
                    Text(amount)
                        .font(.headline)
                        .fontWeight(.bold)
                        .foregroundColor(insight.isPositive ? Color.positive : Color.accent)
                }
            }
            
            Text(insight.description)
                .font(.subheadline)
                .foregroundColor(Color.text2)
                .lineSpacing(4)
        }
        .padding(16)
        .background(Color.surface)
        .cornerRadius(16)
    }
}

#Preview {
    InsightsView(isDrawerOpen: .constant(false))
}
