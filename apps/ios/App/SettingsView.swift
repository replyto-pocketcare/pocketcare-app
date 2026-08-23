import SwiftUI
import UIKit
import Domain
import Data
import Factory
import Observation

/// Local-only device prefs -- mirrors apps/web/src/prefs.ts/theme.ts's
/// localStorage-backed useAmountsHidden/useTheme/useBaseCurrency (same key
/// names, same defaults). NOT synced (matches web: device preferences, not
/// ledger data). Persisted via UserDefaults, mirroring Android's Prefs.kt
/// SharedPreferences pattern -- previously `amountsHidden` was in-memory
/// only here (lost on relaunch); this pass fixes that while adding
/// theme/baseCurrency alongside it.
@MainActor
class Prefs: ObservableObject {
    static let shared = Prefs()

    private let defaults = UserDefaults.standard
    /// Internal, not private: MoneyFormat.swift reads this key directly so the
    /// hide-amounts rule can be honoured outside the main actor. One key, one meaning.
    static let hideKey = "amountsHidden"
    private static let themeKey = "theme"
    /// Internal for the same reason as `hideKey` — see MoneyFormat.swift.
    static let currencyKey = "baseCurrency"

    @Published var amountsHidden: Bool {
        didSet { defaults.set(amountsHidden, forKey: Prefs.hideKey) }
    }
    @Published var theme: String {
        didSet { defaults.set(theme, forKey: Prefs.themeKey) }
    }
    @Published var baseCurrency: String {
        didSet { defaults.set(baseCurrency, forKey: Prefs.currencyKey) }
    }

    private init() {
        amountsHidden = defaults.bool(forKey: Prefs.hideKey)
        theme = defaults.string(forKey: Prefs.themeKey) ?? "light"
        baseCurrency = defaults.string(forKey: Prefs.currencyKey) ?? "INR"
    }
}

private let currencies = ["INR", "USD", "EUR", "GBP", "JPY", "AUD", "CAD", "SGD", "AED"]
private let genders: [(String, String)] = [("", "Not specified"), ("female", "Female"), ("male", "Male"), ("non-binary", "Non-binary"), ("prefer not to say", "Prefer not to say")]
private let countries = ["", "IN", "US", "GB", "CA", "AU", "SG", "AE", "DE", "FR", "NL", "JP", "BR", "ZA", "NG", "KE", "Other"]

struct SettingsView: View {
    @Binding var isDrawerOpen: Bool
    @Environment(\.dismiss) private var dismiss
    @StateObject private var prefs = Prefs.shared

    @State private var viewModel = SettingsViewModel()

    @State private var username = ""
    @State private var confirmSignout = false
    @State private var confirmDelete = false
    @State private var expandedLog = false
    @State private var profileGenderSel = ""
    @State private var profileCountrySel = ""

    var body: some View {
        NavigationStack {
            Form {
                // MARK: Account
                Section(header: Text("Account")) {
                    if viewModel.session?.isGuest == true {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("You're using Sanvya as a guest.\(viewModel.session?.daysLeft.map { " Your data will be deleted in \($0) day\($0 == 1 ? "" : "s") unless you create an account." } ?? "")")
                                .font(.footnote)
                        }
                    } else {
                        Text("Signed in as \(viewModel.session?.email ?? "—")")
                            .font(.footnote)
                            .foregroundColor(Color.text2)
                    }

                    HStack(spacing: 6) {
                        Circle()
                            .fill(viewModel.syncConnected ? Color.green : Color.red)
                            .frame(width: 8, height: 8)
                        Text(viewModel.syncConnected ? "Synced" + (viewModel.syncLastSyncedAt.map { " · last \($0)" } ?? "") : "Not connected")
                            .font(.caption)
                            .foregroundColor(Color.text2)
                    }

                    HStack {
                        TextField("Your name", text: $username)
                        Button(viewModel.usernameSaved ? "Saved" : "Save") { viewModel.saveUsername(username) }
                    }
                }

                // MARK: Appearance
                Section(header: Text("Appearance")) {
                    Picker("Theme", selection: $prefs.theme) {
                        Text("Light").tag("light")
                        Text("Dark").tag("dark")
                    }
                    .pickerStyle(.segmented)
                }

                // MARK: Privacy
                Section(header: Text("Privacy"), footer: Text("Mask balances and transaction amounts across the app.")) {
                    Toggle("Hide Amounts", isOn: $prefs.amountsHidden)
                        .tint(Color.accent)
                }

                // MARK: About you
                Section(header: Text("About you"), footer: Text("Optional. Helps us tailor offers and beta invites. Private.")) {
                    Picker("Gender", selection: $profileGenderSel) {
                        ForEach(genders, id: \.0) { v, label in Text(label).tag(v) }
                    }
                    Picker("Country", selection: $profileCountrySel) {
                        ForEach(countries, id: \.self) { c in Text(c.isEmpty ? "Not specified" : c).tag(c) }
                    }
                    HStack {
                        Button("Save") { viewModel.saveProfile(gender: profileGenderSel, country: profileCountrySel) }
                        if let msg = viewModel.profileMsg {
                            Text(msg).font(.footnote).foregroundColor(Color.text2)
                        }
                    }
                }

                // MARK: Notifications (existing)
                if let notif = viewModel.notifPrefs {
                    Section(header: Text("Notifications"), footer: Text("Get alerted about bills, budgets, low balances and unusual spend.")) {
                        Toggle("Push notifications", isOn: Binding(
                            get: { notif.push_enabled == 1 },
                            set: { viewModel.updatePref(keyPath: \.push_enabled, value: $0) }
                        )).tint(Color.accent)
                        Toggle("Upcoming EMIs & bills", isOn: Binding(
                            get: { notif.emi_due == 1 },
                            set: { viewModel.updatePref(keyPath: \.emi_due, value: $0) }
                        )).tint(Color.accent)
                        Toggle("Budget limits", isOn: Binding(
                            get: { notif.budget == 1 },
                            set: { viewModel.updatePref(keyPath: \.budget, value: $0) }
                        )).tint(Color.accent)
                        Toggle("Low balance", isOn: Binding(
                            get: { notif.low_balance == 1 },
                            set: { viewModel.updatePref(keyPath: \.low_balance, value: $0) }
                        )).tint(Color.accent)
                        Toggle("Unusual transactions", isOn: Binding(
                            get: { notif.outlier == 1 },
                            set: { viewModel.updatePref(keyPath: \.outlier, value: $0) }
                        )).tint(Color.accent)
                        Toggle("Group activity", isOn: Binding(
                            get: { notif.group_invite == 1 },
                            set: { viewModel.updatePref(keyPath: \.group_invite, value: $0) }
                        )).tint(Color.accent)
                        Toggle("Shared expenses", isOn: Binding(
                            get: { notif.group_expense == 1 },
                            set: { viewModel.updatePref(keyPath: \.group_expense, value: $0) }
                        )).tint(Color.accent)
                    }
                }

                // MARK: Base currency
                Section(header: Text("Base Currency"), footer: Text("Used as the default across new accounts and reports.")) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(currencies, id: \.self) { c in
                                Button(c) { prefs.baseCurrency = c }
                                    .buttonStyle(.bordered)
                                    .tint(c == prefs.baseCurrency ? Color.accent : Color.text2)
                            }
                        }
                    }
                }

                // MARK: Plan & billing
                Section(header: Text("Plan & Billing")) {
                    Text("You're on the \(viewModel.entitlement.tier.capitalized) plan.")
                        .font(.subheadline)
                        .foregroundColor(Color.text2)
                    Button(action: { /* No native in-app-purchase flow yet -- see settings.md */ }) {
                        Text(viewModel.entitlement.isPaid ? "Manage Plan" : "Upgrade to Premium")
                            .fontWeight(.bold)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }

                // MARK: Problems syncing (dead-letter queue; hidden when empty)
                if !viewModel.failedWrites.isEmpty {
                    Section(
                        header: Text("Problems syncing"),
                        footer: Text("\(viewModel.failedWrites.count) change\(viewModel.failedWrites.count == 1 ? "" : "s") couldn't be saved to the server. Still on this device — nothing has been lost.")
                    ) {
                        ForEach(viewModel.failedWrites, id: \.id) { item in
                            FailedWriteRow(item: item, viewModel: viewModel)
                        }
                        Button(viewModel.problemsBusy == "all" ? "Trying…" : "Try all \(viewModel.failedWrites.count) again") {
                            viewModel.retryAllFailedWrites()
                        }.disabled(viewModel.problemsBusy != nil)
                    }
                }

                // MARK: Check for unsynced data
                Section(header: Text("Check for unsynced data"), footer: Text("Compares this device against the server and re-uploads anything that never made it. Safe to run any time.")) {
                    RepairSectionView(viewModel: viewModel)
                }

                // MARK: Diagnostics
                Section(
                    header: Text("Diagnostics"),
                    footer: Text("If something isn't working, share this with support. Amounts, names and contact details are removed automatically.")
                ) {
                    HStack {
                        DiagStat(label: "Status", value: viewModel.syncConnected ? "Connected" : "Not connected")
                        DiagStat(label: "Waiting", value: viewModel.queueDepth.map { String($0) } ?? "—", warn: (viewModel.queueDepth ?? 0) > 0)
                        DiagStat(label: "Errors", value: String(viewModel.diagnosticsEntries.filter { $0.level == "error" }.count), warn: viewModel.diagnosticsEntries.contains { $0.level == "error" })
                    }

                    let stuck = viewModel.queueOps.filter { $0.orphaned }
                    if !stuck.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("\(stuck.count) change\(stuck.count == 1 ? "" : "s") can't be saved")
                                .font(.subheadline).bold()
                            Text("These refer to something that no longer exists, so they'll never upload — and they're blocking everything queued behind them.")
                                .font(.caption)
                            Button(viewModel.discardingStuck ? "Working…" : "Discard \(stuck.count) stuck change\(stuck.count == 1 ? "" : "s")") {
                                viewModel.discardStuck()
                            }.disabled(viewModel.discardingStuck)
                        }
                        .padding(8)
                        .background(Color.red.opacity(0.1))
                        .cornerRadius(8)
                    }

                    HStack {
                        Button("Share diagnostics") { shareDiagnostics() }
                        Button(expandedLog ? "Hide log" : "Show log (\(viewModel.diagnosticsEntries.count))") { expandedLog.toggle() }
                    }
                    if expandedLog {
                        let logText = viewModel.diagnosticsEntries.isEmpty
                            ? "Nothing logged yet — that's a good sign."
                            : viewModel.diagnosticsEntries.reversed().map { "\($0.level.uppercased()) [\($0.scope)] \($0.message)" }.joined(separator: "\n")
                        Text(logText).font(.system(size: 11, design: .monospaced))
                    }
                }

                // MARK: Help & support
                Section(header: Text("Help & Support")) {
                    Button("Contact support") {
                        if let url = URL(string: "mailto:support@sanvya.app") { UIApplication.shared.open(url) }
                    }
                }

                // MARK: Sign out / delete
                Section {
                    HStack {
                        Spacer()
                        Button("Sign out") { confirmSignout = true }
                        Spacer()
                        Button("Delete account") { confirmDelete = true }
                            .foregroundColor(.red)
                        Spacer()
                    }
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        withAnimation(.spring()) { isDrawerOpen.toggle() }
                    } label: {
                        Image(systemName: "line.3.horizontal").imageScale(.large)
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }.foregroundColor(Color.text2)
                }
            }
            .background(Color.bg)
            .scrollContentBackground(.hidden)
            .task {
                await viewModel.start()
            }
            .onChange(of: viewModel.session?.username) { _, newValue in
                if let newValue, username.isEmpty { username = newValue }
            }
            .onChange(of: viewModel.usernameSaved) { _, saved in
                if saved {
                    Task {
                        try? await Task.sleep(nanoseconds: 1_500_000_000)
                        viewModel.clearUsernameSaved()
                    }
                }
            }
            .onChange(of: viewModel.profileGender) { _, v in profileGenderSel = v }
            .onChange(of: viewModel.profileCountry) { _, v in profileCountrySel = v }
            .alert("Sign out?", isPresented: $confirmSignout) {
                Button("Cancel", role: .cancel) {}
                Button("Sign out anyway", role: .destructive) { viewModel.signOut() }
            } message: {
                Text(viewModel.session?.isGuest == true
                    ? "You're a guest — signing out deletes this device's data with nothing backed up."
                    : "You can sign back in any time to restore your data.")
            }
            .alert("Delete account", isPresented: $confirmDelete) {
                Button("Cancel", role: .cancel) {}
                Button(viewModel.deleting ? "Deleting…" : "Delete everything", role: .destructive) { viewModel.deleteAccount() }
                    .disabled(viewModel.deleting)
            } message: {
                Text("This permanently deletes your account and data. This can't be undone." + (viewModel.deleteError.map { "\n\($0)" } ?? ""))
            }
        }
    }

    private func shareDiagnostics() {
        let text = viewModel.diagnosticsShareText()
        let activityVC = UIActivityViewController(activityItems: [text], applicationActivities: nil)
        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let root = scene.windows.first?.rootViewController {
            root.present(activityVC, animated: true)
        }
    }
}

private struct DiagStat: View {
    let label: String
    let value: String
    var warn: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption2).foregroundColor(Color.text2)
            Text(value).font(.subheadline).bold()
        }
        .padding(8)
        .background(warn ? Color.red.opacity(0.12) : Color.gray.opacity(0.1))
        .cornerRadius(8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct FailedWriteRow: View {
    let item: FailedWriteItem
    let viewModel: SettingsViewModel
    @State private var confirming = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(item.label).font(.subheadline).bold()
            Text(item.explanation).font(.caption)
            HStack(spacing: 8) {
                Button(viewModel.problemsBusy == item.id ? "Trying…" : "Try again") { viewModel.retryFailedWrite(item) }
                    .disabled(viewModel.problemsBusy != nil)
                if confirming {
                    Button("Copy & discard") { viewModel.discardFailedWrite(item) }
                        .foregroundColor(.red)
                        .disabled(viewModel.problemsBusy != nil)
                } else {
                    Button("Discard") { confirming = true }
                }
            }
            .font(.caption)
        }
        .padding(.vertical, 4)
    }
}

private struct RepairSectionView: View {
    let viewModel: SettingsViewModel

    var body: some View {
        switch viewModel.repairStage {
        case "idle":
            Button("Check now") { viewModel.scanForStranded() }
        case "scanning":
            HStack { ProgressView(); Text("Comparing this device with the server…").font(.subheadline) }
        case "clean":
            VStack(alignment: .leading, spacing: 6) {
                Text("Everything is synced.").font(.subheadline).bold()
                if !viewModel.repairUnchecked.isEmpty {
                    Text("Couldn't check: \(viewModel.repairUnchecked.joined(separator: ", ")).").font(.caption).foregroundColor(Color.text2)
                }
                Button("Check again") { viewModel.resetRepair() }
            }
        case "found":
            VStack(alignment: .leading, spacing: 6) {
                Text("\(viewModel.strandedRows.count) item\(viewModel.strandedRows.count == 1 ? "" : "s") never reached the server").font(.subheadline).bold()
                Text("They're safe here but aren't backed up. Save a copy, then upload them.").font(.caption)
                HStack {
                    Button("Copy a copy") { UIPasteboard.general.string = viewModel.exportStrandedJson() }
                    Button("Upload \(viewModel.strandedRows.count) item\(viewModel.strandedRows.count == 1 ? "" : "s")") { viewModel.repairStrandedNow() }
                }
            }
        case "repairing":
            HStack { ProgressView(); Text("Uploading…").font(.subheadline) }
        case "done":
            VStack(alignment: .leading, spacing: 6) {
                Text("Uploaded \(viewModel.repairUploaded) item\(viewModel.repairUploaded == 1 ? "" : "s").").font(.subheadline).bold()
                if !viewModel.repairFailed.isEmpty {
                    Text("\(viewModel.repairFailed.count) still couldn't be uploaded.").font(.caption).foregroundColor(.red)
                }
                Button("Check again") { viewModel.resetRepair() }
            }
        default:
            Button("Try again") { viewModel.resetRepair() }
        }
    }
}
