import SwiftUI

struct AuthenticationView: View {
    @State private var isLogin = true
    @State private var username = ""
    @State private var email = "test@example.com"
    @State private var password = "password123"
    @State private var confirmPassword = ""
    @State private var showPassword = false
    @State private var isLoading = false
    @EnvironmentObject var authManager: AuthenticationManager
    
    var body: some View {
        NavigationView {
            GeometryReader { geometry in
                ScrollView {
                    VStack(spacing: 0) {
                        // Header Section
                        headerSection
                            .frame(height: geometry.size.height * 0.4)
                        
                        // Form Section
                        formSection
                            .frame(minHeight: geometry.size.height * 0.6)
                    }
                }
                .ignoresSafeArea()
            }
        }
        .navigationBarHidden(true)
    }
    
    private var headerSection: some View {
        ZStack {
            LinearGradient(
                gradient: Gradient(colors: [
                    Color.blue.opacity(0.8),
                    Color.purple.opacity(0.6),
                    Color.pink.opacity(0.4)
                ]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            
            VStack(spacing: 16) {
                // App Icon
                Image(systemName: "location.circle.fill")
                    .font(.system(size: 80))
                    .foregroundColor(.white)
                    .shadow(color: .black.opacity(0.3), radius: 10, x: 0, y: 5)
                
                // App Title
                Text("RecordPath")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .shadow(color: .black.opacity(0.3), radius: 5, x: 0, y: 2)
                
                // Subtitle
                Text("Track your journey around the world")
                    .font(.body)
                    .foregroundColor(.white.opacity(0.9))
                    .multilineTextAlignment(.center)
                    .shadow(color: .black.opacity(0.3), radius: 3, x: 0, y: 1)
            }
        }
    }
    
    private var formSection: some View {
        VStack(spacing: 20) {
            // Toggle between Login and Signup
            Picker("Auth Mode", selection: $isLogin) {
                Text("Login").tag(true)
                Text("Sign Up").tag(false)
            }
            .pickerStyle(SegmentedPickerStyle())
            .padding(.horizontal)
            
            // Form Fields
            VStack(spacing: 16) {
                if !isLogin {
                    CustomTextField(
                        title: "Username",
                        text: $username,
                        icon: "person.fill"
                    )
                }
                
                CustomTextField(
                    title: "Email",
                    text: $email,
                    icon: "envelope.fill"
                )
                .keyboardType(.emailAddress)
                .textContentType(.emailAddress)
                
                CustomSecureField(
                    title: "Password",
                    text: $password,
                    showPassword: $showPassword,
                    icon: "lock.fill"
                )
                
                if !isLogin {
                    CustomSecureField(
                        title: "Confirm Password",
                        text: $confirmPassword,
                        showPassword: $showPassword,
                        icon: "lock.fill"
                    )
                }
            }
            .padding(.horizontal)
            
            // Action Button
            Button(action: authenticate) {
                HStack {
                    if isLoading {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(0.8)
                    } else {
                        Text(isLogin ? "Login" : "Create Account")
                            .fontWeight(.semibold)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(
                    LinearGradient(
                        gradient: Gradient(colors: [Color.blue, Color.purple]),
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .foregroundColor(.white)
                .cornerRadius(25)
                .shadow(color: .blue.opacity(0.3), radius: 10, x: 0, y: 5)
            }
            .padding(.horizontal)
            .disabled(isLoading || !isValidForm)
            
            // Alternative Actions
            VStack(spacing: 8) {
                Button("Forgot Password?") {
                    // Handle forgot password
                }
                .font(.footnote)
                .foregroundColor(.blue)
                
                HStack {
                    Text(isLogin ? "Don't have an account?" : "Already have an account?")
                        .font(.footnote)
                        .foregroundColor(.gray)
                    
                    Button(isLogin ? "Sign Up" : "Login") {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            isLogin.toggle()
                        }
                    }
                    .font(.footnote)
                    .fontWeight(.semibold)
                    .foregroundColor(.blue)
                }
                
                // Quick Test Login
                Button("Quick Test Login") {
                    email = "test@example.com"
                    password = "password123"
                    username = "TestUser"
                    authenticate()
                }
                .font(.footnote)
                .fontWeight(.semibold)
                .foregroundColor(.green)
                .padding(.top, 8)
            }
            .padding(.top, 10)
        }
        .padding(.vertical, 30)
        .background(Color(.systemBackground))
        .cornerRadius(30, corners: [.topLeft, .topRight])
        .shadow(color: .black.opacity(0.1), radius: 20, x: 0, y: -10)
    }
    
    private var isValidForm: Bool {
        if isLogin {
            return !email.isEmpty && !password.isEmpty
        } else {
            return !username.isEmpty && !email.isEmpty && !password.isEmpty && 
                   password == confirmPassword && password.count >= 6
        }
    }
    
    private func authenticate() {
        isLoading = true
        
        // Simulate network delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            if isLogin {
                // For now, just create a user with the email
                let user = authManager.createUser(username: "User", email: email)
                
                // Navigate to main app
                NotificationCenter.default.post(name: .userDidAuthenticate, object: user)
            } else {
                // Create new user
                let user = authManager.createUser(username: username, email: email)
                
                // Navigate to main app
                NotificationCenter.default.post(name: .userDidAuthenticate, object: user)
            }
            
            isLoading = false
        }
    }
}

struct CustomTextField: View {
    let title: String
    @Binding var text: String
    let icon: String
    
    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(.gray)
                .frame(width: 20)
            
            TextField(title, text: $text)
                .textFieldStyle(PlainTextFieldStyle())
        }
        .padding()
        .background(Color.gray.opacity(0.1))
        .cornerRadius(10)
    }
}

struct CustomSecureField: View {
    let title: String
    @Binding var text: String
    @Binding var showPassword: Bool
    let icon: String
    
    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(.gray)
                .frame(width: 20)
            
            if showPassword {
                TextField(title, text: $text)
                    .textFieldStyle(PlainTextFieldStyle())
            } else {
                SecureField(title, text: $text)
                    .textFieldStyle(PlainTextFieldStyle())
            }
            
            Button(action: { showPassword.toggle() }) {
                Image(systemName: showPassword ? "eye.slash" : "eye")
                    .foregroundColor(.gray)
            }
        }
        .padding()
        .background(Color.gray.opacity(0.1))
        .cornerRadius(10)
    }
}

extension View {
    func cornerRadius(_ radius: CGFloat, corners: UIRectCorner) -> some View {
        clipShape(RoundedCorner(radius: radius, corners: corners))
    }
}

struct RoundedCorner: Shape {
    var radius: CGFloat = .infinity
    var corners: UIRectCorner = .allCorners
    
    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(
            roundedRect: rect,
            byRoundingCorners: corners,
            cornerRadii: CGSize(width: radius, height: radius)
        )
        return Path(path.cgPath)
    }
}

extension Notification.Name {
    static let userDidAuthenticate = Notification.Name("userDidAuthenticate")
}

#Preview {
    AuthenticationView()
        .environmentObject(AuthenticationManager())
}