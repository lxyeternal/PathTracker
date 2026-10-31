import SwiftUI
import PhotosUI
import AuthenticationServices

/// Edit avatar, name, email and bio, and link or unlink Sign in with Apple.
struct ProfileEditView: View {
    @Environment(AccountManager.self) private var account
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var email = ""
    @State private var bio = ""
    @State private var photoItem: PhotosPickerItem?
    @State private var showingPhotoPicker = false
    @State private var confirmingSignOut = false
    @State private var isLoadingPhoto = false
    @State private var nationality = Nationality.code ?? ""

    private var emailIsValid: Bool {
        let trimmed = email.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty || trimmed.wholeMatch(of: /[^@\s]+@[^@\s]+\.[^@\s]+/) != nil
    }

    var body: some View {
        Form {
            avatarSection
            infoSection
            nationalitySection
            appleSection
        }
        .navigationTitle("个人资料")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("保存", systemImage: "checkmark", action: save)
                    .disabled(!emailIsValid)
            }
        }
        .photosPicker(isPresented: $showingPhotoPicker, selection: $photoItem, matching: .images)
        .onChange(of: photoItem) { _, item in loadPhoto(item) }
        .confirmationDialog("退出 Apple 登录？", isPresented: $confirmingSignOut, titleVisibility: .visible) {
            Button("退出登录", role: .destructive) { account.signOut() }
        }
        .onChange(of: account.profile.email) { _, newValue in
            // Signing in may fill in an email Apple provided; show it right away.
            if email.isEmpty, let newValue { email = newValue }
        }
        .onChange(of: account.profile.displayName) { _, newValue in
            // Likewise the name, so saving doesn't wipe the one Apple just gave.
            if name.isEmpty, let newValue { name = newValue }
        }
        .onChange(of: account.profile.bio) { _, newValue in
            if bio.isEmpty, let newValue { bio = newValue }
        }
        .onAppear(perform: loadFields)
    }

    // MARK: Sections

    private var avatarSection: some View {
        Section {
            VStack(spacing: 12) {
                Menu {
                    Button("从相册选择", systemImage: "photo.on.rectangle") { showingPhotoPicker = true }
                    if account.avatar != nil {
                        Button("移除头像", systemImage: "trash", role: .destructive) {
                            withAnimation { account.removeAvatar() }
                        }
                    }
                } label: {
                    EditableAvatar(isLoading: isLoadingPhoto)
                }
                .accessibilityLabel("更换头像")
                Button(account.avatar == nil ? "添加头像" : "更换头像") { showingPhotoPicker = true }
                    .font(.subheadline.weight(.medium))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .listRowBackground(Color.clear)
        }
    }

    private var infoSection: some View {
        Section {
            LabeledContent("名字") {
                TextField("旅行者", text: $name)
                    .multilineTextAlignment(.trailing)
                    .textContentType(.name)
            }
            LabeledContent("邮箱") {
                TextField("可不填", text: $email)
                    .multilineTextAlignment(.trailing)
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
            TextField("一句话介绍自己（可不填）", text: $bio, axis: .vertical)
                .lineLimit(1...4)
        } header: {
            Text("个人信息")
        } footer: {
            if emailIsValid {
                Text("资料只保存在你的设备和 iCloud 中，用来在你的设备之间同步。")
            } else {
                Text("邮箱格式不正确").foregroundStyle(.red)
            }
        }
    }

    private var nationalitySection: some View {
        Section {
            Picker("国籍", selection: $nationality) {
                Text("自动（停留最久的国家）").tag("")
                ForEach(Nationality.all, id: \.code) { country in
                    Text("\(String.flag(for: country.code)) \(country.name)").tag(country.code)
                }
            }
            .pickerStyle(.navigationLink)
            .onChange(of: nationality) { _, code in
                Nationality.code = code.isEmpty ? nil : code
                PlaceSummaries.shared.refresh()
            }
        } footer: {
            Text("护照的签发国。去这个国家以外的地方才算出国，护照上也不会给它盖入境章。")
        }
    }

    private var appleSection: some View {
        Section {
            if account.isSignedIn {
                Label("已通过 Apple 登录", systemImage: "apple.logo")
                Button("退出 Apple 登录", role: .destructive) { confirmingSignOut = true }
            } else {
                SignInWithAppleButton(.signIn, onRequest: account.configure, onCompletion: account.handle)
                    .signInWithAppleButtonStyle(.black)
                    .frame(height: 46)
                    .clipShape(.capsule)
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                if let error = account.lastError {
                    Text(error).font(.footnote).foregroundStyle(.red)
                }
            }
        } header: {
            Text("Apple 账户")
        } footer: {
            Text(account.isSignedIn ? "退出后，你的头像、名字和所有记录都会保留。" : "登录是可选的，不登录也能使用全部功能。")
        }
    }

    // MARK: Actions

    private func loadFields() {
        name = account.profile.displayName ?? ""
        email = account.profile.email ?? ""
        bio = account.profile.bio ?? ""
    }

    private func save() {
        account.update(name: name, email: email, bio: bio)
        dismiss()
    }

    private func loadPhoto(_ item: PhotosPickerItem?) {
        guard let item else { return }
        isLoadingPhoto = true
        Task {
            if let data = try? await item.loadTransferable(type: Data.self) {
                withAnimation(.smooth) { account.setAvatar(from: data) }
            }
            isLoadingPhoto = false
            photoItem = nil
        }
    }
}

/// The large avatar with a camera badge, shown at the top of the profile editor.
private struct EditableAvatar: View {
    let isLoading: Bool

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Avatar(size: 112)
                .overlay { if isLoading { loadingOverlay } }
            badge
        }
    }

    private var loadingOverlay: some View {
        ZStack {
            Circle().fill(Color.black.opacity(0.35))
            ProgressView().tint(.white)
        }
    }

    private var badge: some View {
        Image(systemName: "camera.fill")
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 34, height: 34)
            .background(Circle().fill(Color.accentColor))
            .overlay(Circle().stroke(Color(uiColor: .systemGroupedBackground), lineWidth: 3))
    }
}
