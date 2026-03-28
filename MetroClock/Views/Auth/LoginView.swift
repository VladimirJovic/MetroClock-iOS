import SwiftUI

struct LoginView: View {
    @Environment(AuthService.self) var authService
    
    @State private var email = ""
    @State private var password = ""
    
    var body: some View {
        ZStack {
            Color.mcBackground.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                // Logo
                VStack(spacing: 8) {
                    Image(systemName: "clock.fill")
                        .font(.system(size: 60))
                        .foregroundStyle(Color.mcOrange)
                    Text("MetroClock")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .foregroundStyle(Color.mcText)
                    Text("by Echo")
                        .font(.subheadline)
                        .foregroundStyle(Color.mcTextSecondary)
                }
                .padding(.bottom, 48)

                // Fields
                VStack(spacing: 16) {
                    TextField("Email", text: $email)
                        .keyboardType(.emailAddress)
                        .autocapitalization(.none)
                        .foregroundStyle(Color.mcText)
                        .padding()
                        .background(Color.mcSurface)
                        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.mcBorder, lineWidth: 1))
                        .cornerRadius(12)

                    SecureField("Password", text: $password)
                        .foregroundStyle(Color.mcText)
                        .padding()
                        .background(Color.mcSurface)
                        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.mcBorder, lineWidth: 1))
                        .cornerRadius(12)
                }
                .padding(.horizontal, 32)

                // Error
                if let error = authService.errorMessage {
                    Text(error)
                        .foregroundStyle(.red)
                        .font(.caption)
                        .padding(.top, 8)
                }

                // Login Button
                Button {
                    authService.login(email: email, password: password)
                } label: {
                    Group {
                        if authService.isLoading {
                            ProgressView().tint(.white)
                        } else {
                            Text("Login")
                                .fontWeight(.semibold)
                                .tracking(1.5)
                                .textCase(.uppercase)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(Color.mcOrange)
                    .foregroundStyle(Color.mcText)
                    .cornerRadius(12)
                }
                .padding(.horizontal, 32)
                .padding(.top, 24)
                .disabled(authService.isLoading || email.isEmpty || password.isEmpty)

                Spacer()
            }
        }
    }
}
