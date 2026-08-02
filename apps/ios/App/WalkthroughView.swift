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
                            Text("Welcome to Sanvya").font(.title2).fontWeight(.bold)
                            Text("Sanvya is your private money diary. You write down what you spend and earn, and it shows you where your money is actually going.")
                            Text("It is not connected to your bank.").fontWeight(.bold)
                            Text("We never ask for your bank login, card number or OTP, and we can't see your bank at all.")
                            Text("Nothing is tracked automatically — you'll type your spends in yourself. That's deliberate: the few seconds it takes is what makes you notice where your money goes, and noticing is the whole point.")
                            
                            VStack(spacing: 12) {
                                PrimaryButton("Show me how") { step = 2 }
                                
                                PrimaryButton("I'll look around myself", isGhost: true) { onFinish() }
                            }
                            .padding(.top, 10)
                        } else if step == 2 {
                            Text("Where do you keep your money?").font(.title2).fontWeight(.bold)
                            Text("An \"account\" here is just your own note of somewhere money sits — your bank, the cash in your purse, a credit card. It's a name and a number you type. Nothing is linked to the real bank.")
                            
                            VStack(spacing: 10) {
                                FloatingInput("Give it a name", text: .constant(""))
                                FloatingInput("Roughly how much is in it now?", text: .constant(""))
                            }
                            
                            VStack(spacing: 12) {
                                PrimaryButton("Save") { step = 3 }
                                
                                PrimaryButton("Skip this for now", isGhost: true) { step = 3 }
                            }
                            .padding(.top, 10)
                        } else if step == 3 {
                            Text("Now write down one thing you spent").font(.title2).fontWeight(.bold)
                            Text("Think of the last thing you paid for — tea, groceries, a bill.")
                            Text("This is the one habit that matters — everything else in the app is built from it.").fontWeight(.bold)
                            
                            VStack(spacing: 10) {
                                FloatingInput("What was it for?", text: .constant(""))
                                FloatingInput("How much?", text: .constant(""))
                            }
                            
                            VStack(spacing: 12) {
                                PrimaryButton("Save") { step = 4 }
                                
                                PrimaryButton("Skip this for now", isGhost: true) { step = 4 }
                            }
                            .padding(.top, 10)
                        } else if step == 4 {
                            Text("That's it — you're set up").font(.title2).fontWeight(.bold)
                            Text("Your data is yours. It stays on your device and in your private account — we don't share it, and nobody else can see it.")
                                .font(.caption)
                                .foregroundColor(Color.text2)
                            
                            VStack(spacing: 12) {
                                PrimaryButton("Finish") { onFinish() }
                                
                                PrimaryButton("See what else it does →", isGhost: true) { step = 5 }
                            }
                            .padding(.top, 10)
                        } else if step == 5 {
                            Text("Sanvya reads your entries back to you").font(.title2).fontWeight(.bold)
                            Text("Once you've written a few things down, Sanvya starts pointing things out on its own: which category is eating the most, a month running hotter than the last, a subscription you may have forgotten.")
                            
                            VStack(spacing: 12) {
                                PrimaryButton("Next") { step = 6 }
                                
                                PrimaryButton("Finish", isGhost: true) { onFinish() }
                            }
                            .padding(.top, 10)
                        } else if step == 6 {
                            Text("Or just ask, in your own words").font(.title2).fontWeight(.bold)
                            Text("Type or say things like \"how much did I spend on groceries last month?\" or \"can I afford ₹15,000 this week?\" — and it answers from your own entries.")
                            
                            VStack(spacing: 12) {
                                PrimaryButton("Next") { step = 7 }
                                
                                PrimaryButton("Finish", isGhost: true) { onFinish() }
                            }
                            .padding(.top, 10)
                        } else if step == 7 {
                            Text("You're using Sanvya as a guest").font(.title2).fontWeight(.bold)
                            Text("Your entries live only on this device, and guest data is deleted after a few days. Create a free account to keep it — and you'll get 14 days with everything unlocked.")
                            
                            VStack(spacing: 12) {
                                PrimaryButton("Create a free account") { onNavigateToLogin() }
                                
                                PrimaryButton("Later", isGhost: true) { onFinish() }
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
