import SwiftUI

struct MainTabView: View {
    @State private var currentTab: NavTab = .dashboard
    @State private var isDrawerOpen: Bool = false
    @State private var drawerOffset: CGFloat = -UIScreen.main.bounds.width * 0.8
    
    var body: some View {
        let drawerWidth = UIScreen.main.bounds.width * 0.75
        
        ZStack(alignment: .leading) {
            // Main Content Area
            Group {
                switch currentTab {
                case .dashboard: DashboardView(isDrawerOpen: $isDrawerOpen)
                case .assistant: AssistantView(isDrawerOpen: $isDrawerOpen)
                
                case .accounts: AccountsView(isDrawerOpen: $isDrawerOpen)
                case .transactions: TransactionsView(isDrawerOpen: $isDrawerOpen)
                case .templates: TemplatesView(isDrawerOpen: $isDrawerOpen)
                case .cards: CreditCardsView(isDrawerOpen: $isDrawerOpen)
                case .splits: SplitsView(isDrawerOpen: $isDrawerOpen)
                case .search: SearchView(isDrawerOpen: $isDrawerOpen)
                
                case .budgets: BudgetsView(isDrawerOpen: $isDrawerOpen)
                case .goals: GoalsView(isDrawerOpen: $isDrawerOpen)
                case .cashflow: CashflowView(isDrawerOpen: $isDrawerOpen)
                case .recurring: RecurringView(isDrawerOpen: $isDrawerOpen)
                case .loans: LoansView(isDrawerOpen: $isDrawerOpen)
                
                case .investments: InvestmentsView(isDrawerOpen: $isDrawerOpen)
                case .insights: InsightsView(isDrawerOpen: $isDrawerOpen)
                case .statements: StatementsView(isDrawerOpen: $isDrawerOpen)
                
                case .settings: SettingsView(isDrawerOpen: $isDrawerOpen)
                case .help: HelpView(isDrawerOpen: $isDrawerOpen)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // Optional: push content slightly when drawer is open
            // .offset(x: isDrawerOpen ? drawerWidth : 0) 
            // .disabled(isDrawerOpen)

            // Dimming Background
            if isDrawerOpen {
                Color.black.opacity(0.4)
                    .edgesIgnoringSafeArea(.all)
                    .onTapGesture {
                        withAnimation(.spring()) {
                            isDrawerOpen = false
                        }
                    }
            }

            // Drawer
            DrawerMenuView(currentTab: $currentTab, isDrawerOpen: $isDrawerOpen)
                .frame(width: drawerWidth)
                .offset(x: isDrawerOpen ? 0 : -drawerWidth)
                // Gesture for swiping drawer
                .gesture(
                    DragGesture()
                        .onEnded { value in
                            if value.translation.width < -50 {
                                withAnimation(.spring()) {
                                    isDrawerOpen = false
                                }
                            }
                        }
                )
        }
    }
}

#Preview {
    MainTabView()
}
