import SwiftUI

struct StatementUiModel: Identifiable {
    let id: String
    let month: String
    let dateRange: String
    let isPremium: Bool
}

struct StatementsView: View {
    
    @State private var searchQuery: String = ""
    
    let sampleStatements = [
        StatementUiModel(id: "1", month: "July 2026", dateRange: "01 Jul - 31 Jul", isPremium: false),
        StatementUiModel(id: "2", month: "June 2026", dateRange: "01 Jun - 30 Jun", isPremium: false),
        StatementUiModel(id: "3", month: "May 2026", dateRange: "01 May - 31 May", isPremium: false),
        StatementUiModel(id: "4", month: "2025 Annual Statement", dateRange: "01 Jan 2025 - 31 Dec 2025", isPremium: true)
    ]
    
    var filteredStatements: [StatementUiModel] {
        if searchQuery.isEmpty {
            return sampleStatements
        }
        return sampleStatements.filter { $0.month.localizedCaseInsensitiveContains(searchQuery) }
    }
    
    var body: some View {
        NavigationStack {
            VStack {
                TextField("Search statements...", text: $searchQuery)
                    .padding(12)
                    .background(Color.surface)
                    .cornerRadius(12)
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                
                ScrollView {
                    VStack(spacing: 12) {
                        ForEach(filteredStatements) { statement in
                            StatementCard(statement: statement)
                        }
                    }
                    .padding(16)
                }
            }
            .background(Color.bg.ignoresSafeArea())
            .navigationTitle("Statements")
            .navigationBarTitleDisplayMode(.inline)

        }
    }
}

struct StatementCard: View {
    let statement: StatementUiModel
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(statement.month)
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundColor(Color.text)
                Text(statement.dateRange)
                    .font(.subheadline)
                    .foregroundColor(Color.text2)
            }
            
            Spacer()
            
            if statement.isPremium {
                Text("Premium")
                    .font(.caption2)
                    .fontWeight(.bold)
                    .foregroundColor(Color.accent)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                    .background(Color.accent.opacity(0.1))
                    .cornerRadius(6)
            } else {
                Button(action: { /* TODO: Share/Print */ }) {
                    Text("Share")
                        .font(.caption)
                        .fontWeight(.medium)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.surface2)
                        .foregroundColor(Color.text)
                        .cornerRadius(8)
                }
            }
        }
        .padding(16)
        .background(Color.surface)
        .cornerRadius(16)
    }
}

#Preview {
    StatementsView()
}
