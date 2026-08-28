import SwiftUI
import Data

/// The corner spinner shown while any synced-row write is in flight — web's
/// `GlobalLoader`, which `AppShell.tsx` renders once for the whole app.
///
/// It is deliberately NOT a blocking overlay. Web's is 24pt in the top-right
/// corner and the page stays usable underneath, because these writes go to a
/// local database first and sync afterwards: blocking the UI for a write that
/// has already effectively succeeded would make the app feel slower than it is.
///
/// Reads `WriteActivity`, which the three helpers in WriteHelpers.swift
/// maintain. `allowsHitTesting(false)` so it never eats a tap meant for the
/// content beneath it.
///
/// Mirrors Android's WriteIndicator.kt.
@MainActor
struct WriteIndicatorView: View {
    @Environment(\.colorScheme) private var colorScheme
    private var activity = WriteActivity.shared

    var body: some View {
        Group {
            if activity.busy {
                SanvyaSpinner(size: 24)
                    .padding(6)
                    .background(Color.surface)
                    .clipShape(Circle())
                    .sanvyaShadow(SanvyaShadows.shadow(dark: colorScheme == .dark))
                    .padding(16)
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        .allowsHitTesting(false)
        .animation(.easeInOut(duration: 0.15), value: activity.busy)
    }
}
