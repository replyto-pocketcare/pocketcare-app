import SwiftUI
import Domain
import Data
import Factory
import Observation

@MainActor
class Prefs: ObservableObject {
    static let shared = Prefs()
    @Published var amountsHidden: Bool = false
}

@MainActor
func formatMoneyAware(_ money: Domain.Money, mask: String = "••••") -> String {
    if Prefs.shared.amountsHidden {
        return mask
    }
    let major = Domain.toMajor(money)
    return String(format: "₹%.2f", major)
}

@MainActor
@Observable
class SettingsViewModel {
    @ObservationIgnored
    @Injected(\.prefsRepository) private var prefsRepo
    @ObservationIgnored
    @Injected(\.authRepository) private var authRepo
    
    var notifPrefs: NotificationPrefs?
    
    func loadPrefs() async {
        guard let userId = authRepo.currentUserId else { return }
        do {
            if let p = try await prefsRepo.getNotificationPrefs(userId: userId) {
                self.notifPrefs = p
            } else {
                let p = NotificationPrefs(user_id: userId)
                try await prefsRepo.updateNotificationPrefs(userId: userId, prefs: p)
                self.notifPrefs = p
            }
        } catch {
            print("Failed to load notif prefs: \(error)")
        }
    }
    
    func updatePref(keyPath: WritableKeyPath<NotificationPrefs, Int>, value: Bool) {
        guard var prefs = notifPrefs, let userId = authRepo.currentUserId else { return }
        prefs[keyPath: keyPath] = value ? 1 : 0
        self.notifPrefs = prefs
        
        Task {
            do {
                try await prefsRepo.updateNotificationPrefs(userId: userId, prefs: prefs)
            } catch {
                print("Failed to save notif prefs: \(error)")
            }
        }
    }
}

struct SettingsView: View {
    @Binding var isDrawerOpen: Bool
    @Environment(\.dismiss) private var dismiss
    @StateObject private var prefs = Prefs.shared
    
    @State private var viewModel = SettingsViewModel()
    
    var currentTier: String = "free"
    
    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Plan & Billing")) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("You're on the \(currentTier) plan.")
                            .font(.subheadline)
                            .foregroundColor(Color.text2)
                        
                        Button(action: { /* open billing */ }) {
                            Text(currentTier == "free" ? "Upgrade to Premium" : "Manage Plan")
                                .font(.headline)
                                .fontWeight(.bold)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(Color.accent)
                                .foregroundColor(Color.surface)
                                .cornerRadius(8)
                        }
                        .buttonStyle(PlainButtonStyle())
                        .padding(.top, 4)
                    }
                    .padding(.vertical, 4)
                }
                
                Section(header: Text("Preferences")) {
                    HStack {
                        Text("Currency")
                        Spacer()
                        Text("INR").foregroundColor(Color.text2)
                    }
                    HStack {
                        Text("Language")
                        Spacer()
                        Text("English").foregroundColor(Color.text2)
                    }
                    HStack {
                        Text("Theme")
                        Spacer()
                        Text("System default").foregroundColor(Color.text2)
                    }
                }
                
                Section(header: Text("Privacy"), footer: Text("Mask balances and transaction amounts across the app.")) {
                    Toggle("Hide Amounts", isOn: $prefs.amountsHidden)
                        .tint(Color.accent)
                }
                
                if let _ = viewModel.notifPrefs {
                    Section(header: Text("Notifications"), footer: Text("Get alerted about bills, budgets, low balances and unusual spend.")) {
                        Toggle("Push notifications", isOn: Binding(
                            get: { viewModel.notifPrefs?.push_enabled == 1 },
                            set: { viewModel.updatePref(keyPath: \.push_enabled, value: $0) }
                        )).tint(Color.accent)
                        
                        Toggle("Upcoming EMIs & bills", isOn: Binding(
                            get: { viewModel.notifPrefs?.emi_due == 1 },
                            set: { viewModel.updatePref(keyPath: \.emi_due, value: $0) }
                        )).tint(Color.accent)
                        
                        Toggle("Budget limits", isOn: Binding(
                            get: { viewModel.notifPrefs?.budget == 1 },
                            set: { viewModel.updatePref(keyPath: \.budget, value: $0) }
                        )).tint(Color.accent)
                        
                        Toggle("Low balance", isOn: Binding(
                            get: { viewModel.notifPrefs?.low_balance == 1 },
                            set: { viewModel.updatePref(keyPath: \.low_balance, value: $0) }
                        )).tint(Color.accent)
                        
                        Toggle("Unusual transactions", isOn: Binding(
                            get: { viewModel.notifPrefs?.outlier == 1 },
                            set: { viewModel.updatePref(keyPath: \.outlier, value: $0) }
                        )).tint(Color.accent)
                        
                        Toggle("Group activity", isOn: Binding(
                            get: { viewModel.notifPrefs?.group_invite == 1 },
                            set: { viewModel.updatePref(keyPath: \.group_invite, value: $0) }
                        )).tint(Color.accent)
                        
                        Toggle("Shared expenses", isOn: Binding(
                            get: { viewModel.notifPrefs?.group_expense == 1 },
                            set: { viewModel.updatePref(keyPath: \.group_expense, value: $0) }
                        )).tint(Color.accent)
                    }
                }
            }
            .navigationTitle("Settings")
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
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                        .foregroundColor(Color.text2)
                }
            }
            .background(Color.bg)
            .scrollContentBackground(.hidden)
            .task {
                await viewModel.loadPrefs()
            }
        }
    }
}
