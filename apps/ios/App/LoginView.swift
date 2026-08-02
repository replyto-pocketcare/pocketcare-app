import SwiftUI

struct LoginView: View {
    var onLoginSuccess: () -> Void
    var onContinueAsGuest: () -> Void
    
    @State private var email: String = ""
    @State private var otpSent: Bool = false
    @State private var otp: String = ""
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 32) {
                Text("Sanvya")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .foregroundColor(Color.accent)
                
                VStack(spacing: 20) {
                    Text("Sign in or create an account")
                        .font(.title3)
                        .fontWeight(.bold)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    
                    if !otpSent {
                        TextField("Email address", text: $email)
                            .padding()
                            .background(Color.bg)
                            .cornerRadius(8)
                            .keyboardType(.emailAddress)
                            .autocapitalization(.none)
                        
                        Button(action: { otpSent = true }) {
                            Text("Continue with Email")
                                .font(.headline)
                                .fontWeight(.bold)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(Color.accent)
                                .foregroundColor(Color.surface)
                                .cornerRadius(12)
                        }
                    } else {
                        Text("We sent a code to \(email)")
                            .font(.subheadline)
                            .foregroundColor(Color.text2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        
                        TextField("Enter OTP", text: $otp)
                            .padding()
                            .background(Color.bg)
                            .cornerRadius(8)
                            .keyboardType(.numberPad)
                        
                        Button(action: { onLoginSuccess() }) {
                            Text("Verify & Sign In")
                                .font(.headline)
                                .fontWeight(.bold)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(Color.accent)
                                .foregroundColor(Color.surface)
                                .cornerRadius(12)
                        }
                    }
                    
                    HStack {
                        Rectangle().fill(Color.surface2).frame(height: 1)
                        Text(" OR ").font(.caption).foregroundColor(Color.text2)
                        Rectangle().fill(Color.surface2).frame(height: 1)
                    }
                    .padding(.vertical, 8)
                    
                    Button(action: { onLoginSuccess() }) {
                        Text("Continue with Google")
                            .font(.headline)
                            .fontWeight(.bold)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color.surface2)
                            .foregroundColor(Color.text)
                            .cornerRadius(12)
                    }
                    
                    Button(action: { onContinueAsGuest() }) {
                        Text("Continue as Guest (No account needed)")
                            .font(.subheadline)
                            .foregroundColor(Color.text2)
                    }
                    .padding(.top, 8)
                }
                .padding(24)
                .background(Color.surface)
                .cornerRadius(16)
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.bg.ignoresSafeArea())
        }
    }
}

#Preview {
    LoginView(onLoginSuccess: {}, onContinueAsGuest: {})
}
