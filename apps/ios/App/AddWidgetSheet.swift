import SwiftUI

/**
 Web's "Add a widget" modal.

 **It only offers tiles that are built.** Web can list all fourteen because all
 fourteen render; here `TileId.isBuilt` gates the list, so a user can never add
 a tile that would appear as an empty card. The eleven unbuilt ones are absent
 from the picker, not present-and-broken, and are tracked in
 ABSENT-BY-DECISION.md.

 A premium tile the user is not entitled to is shown **locked rather than
 hidden**, which is web's behaviour: knowing the feature exists is the point of
 the lock. It is only ever a locked row here, never a locked tile on the
 dashboard — those are filtered out of the grid entirely.

 Mirrors `apps/android/.../ui/dashboard/AddWidgetSheet.kt`.
 */
struct AddWidgetSheet: View {
    let isPaid: Bool
    let onClose: () -> Void

    @ObservedObject private var prefs = DashboardPrefs.shared

    private var available: [TileId] {
        TileId.allCases.filter { $0.isBuilt && !prefs.ids.contains($0) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                SanvyaH2(S.Dashboard.addWidget)
                Text(S.Dashboard.addWidgetIntro)
                    .sanvyaStyle(SanvyaType.statLabel)
                    .foregroundStyle(Color.text2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.bottom, 12)

            if available.isEmpty {
                Text(S.Dashboard.allAdded)
                    .sanvyaStyle(SanvyaType.statLabel)
                    .foregroundStyle(Color.text2)
            } else {
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(available) { tile in
                            row(tile)
                        }
                    }
                }
                .frame(maxHeight: 360)
            }

            if !isPaid {
                Text(S.Dashboard.premiumNote)
                    .sanvyaStyle(SanvyaType.statLabel)
                    .foregroundStyle(Color.text2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 10)
            }

            HStack {
                Spacer(minLength: 0)
                SanvyaButton(action: onClose) { Text(S.Translation.commonDone) }
            }
            .padding(.top, 14)
        }
    }

    private func row(_ tile: TileId) -> some View {
        let locked = tile.isPremium && !isPaid
        return SanvyaCard {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(tile.title)
                        .sanvyaStyle(SanvyaType.body)
                        .foregroundStyle(locked ? Color.text2 : Color.text)
                    if locked {
                        Text(S.Dashboard.premium)
                            .sanvyaStyle(SanvyaType.statLabel)
                            .foregroundStyle(Color.text2)
                    }
                }
                Spacer(minLength: 0)
                SanvyaButton { prefs.setEnabled(tile, true) } label: {
                    Text(S.Translation.commonAdd)
                }
                .disabled(locked)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
