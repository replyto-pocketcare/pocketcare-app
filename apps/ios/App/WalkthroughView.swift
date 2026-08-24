import SwiftUI

struct WalkthroughView: View {
    var onFinish: () -> Void
    var onNavigateToLogin: () -> Void
    
    @State private var step: Int = 1
    
    var body: some View {
        let totalSteps = step <= 4 ? 4 : 3
        let stepDisplay = step <= 4 ? step : step - 4
        
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        Text("Step \(stepDisplay) of \(totalSteps)")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundColor(Color.text2)
                            .padding(.top, 10)
                        
                        if step == 1 {
                            Text(S.Onboarding.wtIntroTitle).font(.title2).fontWeight(.bold)
                            Text(S.Onboarding.wtIntroP1)
                            Text(S.Onboarding.wtIntroP2).fontWeight(.bold)
                            Text(S.Onboarding.wtIntroP3)
                            Text("Nothing is tracked automatically — you'll type your spends in yourself. That's deliberate: the few seconds it takes is what makes you notice where your money goes, and noticing is the whole point.")
                            
                            VStack(spacing: 12) {
                                PrimaryButton(S.Onboarding.wtIntroCta) { step = 2 }
                                
                                PrimaryButton(S.Onboarding.wtSkip, isGhost: true) { onFinish() }
                            }
                            .padding(.top, 10)
                        } else if step == 2 {
                            Text(S.Onboarding.wtAccTitle).font(.title2).fontWeight(.bold)
                            Text(S.Onboarding.wtAccP1)
                            
                            VStack(spacing: 10) {
                                FloatingInput(S.Onboarding.wtAccNameLabel, text: .constant(""))
                                FloatingInput(S.Onboarding.wtAccBalLabel, text: .constant(""))
                            }
                            
                            VStack(spacing: 12) {
                                PrimaryButton(S.Translation.commonSave) { step = 3 }
                                
                                PrimaryButton(S.Onboarding.wtLater, isGhost: true) { step = 3 }
                            }
                            .padding(.top, 10)
                        } else if step == 3 {
                            Text(S.Onboarding.wtSpendTitle).font(.title2).fontWeight(.bold)
                            Text(S.Onboarding.wtSpendP1)
                            Text(S.Onboarding.wtSpendP3).fontWeight(.bold)
                            
                            VStack(spacing: 10) {
                                FloatingInput(S.Onboarding.wtSpendWhatLabel, text: .constant(""))
                                FloatingInput(S.Onboarding.wtSpendAmountLabel, text: .constant(""))
                            }
                            
                            VStack(spacing: 12) {
                                PrimaryButton(S.Translation.commonSave) { step = 4 }
                                
                                PrimaryButton(S.Onboarding.wtLater, isGhost: true) { step = 4 }
                            }
                            .padding(.top, 10)
                        } else if step == 4 {
                            Text(S.Onboarding.wtDoneTitle).font(.title2).fontWeight(.bold)
                            Text(S.Onboarding.wtDonePrivacy)
                                .font(.caption)
                                .foregroundColor(Color.text2)
                            
                            VStack(spacing: 12) {
                                PrimaryButton(S.Onboarding.wtDoneCta) { onFinish() }
                                
                                PrimaryButton(S.Onboarding.wtDoneMore, isGhost: true) { step = 5 }
                            }
                            .padding(.top, 10)
                        } else if step == 5 {
                            Text(S.Onboarding.wtInsightsTitle).font(.title2).fontWeight(.bold)
                            Text("Once you've written a few things down, Sanvya starts pointing things out on its own: which category is eating the most, a month running hotter than the last, a subscription you may have forgotten.")
                            
                            VStack(spacing: 12) {
                                PrimaryButton(S.Onboarding.next) { step = 6 }
                                
                                PrimaryButton(S.Onboarding.wtDoneCta, isGhost: true) { onFinish() }
                            }
                            .padding(.top, 10)
                        } else if step == 6 {
                            Text(S.Onboarding.wtAskTitle).font(.title2).fontWeight(.bold)
                            Text(S.Onboarding.wtAskP1)
                            
                            VStack(spacing: 12) {
                                PrimaryButton(S.Onboarding.next) { step = 7 }
                                
                                PrimaryButton(S.Onboarding.wtDoneCta, isGhost: true) { onFinish() }
                            }
                            .padding(.top, 10)
                        } else if step == 7 {
                            Text(S.Onboarding.wtGuestTitle).font(.title2).fontWeight(.bold)
                            Text(S.Onboarding.wtGuestP1)
                            
                            VStack(spacing: 12) {
                                PrimaryButton(S.Onboarding.wtGuestCta) { onNavigateToLogin() }
                                
                                PrimaryButton(S.Onboarding.wtGuestLater, isGhost: true) { onFinish() }
                            }
                            .padding(.top, 10)
                        }
                    }
                    .padding(24)
                }
            }
            .background(Color.bg.ignoresSafeArea())
        }
    }
}

#Preview {
    WalkthroughView(onFinish: {}, onNavigateToLogin: {})
}
