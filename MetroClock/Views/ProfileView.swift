import SwiftUI
import FirebaseStorage
import FirebaseFirestore
import PhotosUI
import Kingfisher

struct ProfileView: View {
    @Environment(AuthService.self) var authService
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var isUploadingPhoto = false
    
    var user: MCUser? { authService.currentUser }
    
    var roleLabel: String {
        switch user?.role {
        case .admin: return "Admin"
        case .manager: return "Manager"
        case .employee: return "Employee"
        case .none: return ""
        }
    }
    
    var roleColor: Color {
        switch user?.role {
        case .admin: return .purple
        case .manager: return .blue
        case .employee: return .green
        case .none: return .gray
        }
    }
    
    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 16) {
                        PhotosPicker(selection: $selectedPhoto, matching: .images) {
                            ZStack(alignment: .bottomTrailing) {
                                if let urlString = user?.profileImageURL,
                                   let url = URL(string: urlString) {
                                    KFImage(url)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 64, height: 64)
                                        .clipShape(Circle())
                                } else {
                                    ZStack {
                                        Circle()
                                            .fill(roleColor.opacity(0.15))
                                            .frame(width: 64, height: 64)
                                        Text((user?.firstName.prefix(1) ?? "") + (user?.lastName.prefix(1) ?? ""))
                                            .font(.title2)
                                            .fontWeight(.semibold)
                                            .foregroundStyle(roleColor)
                                    }
                                }
                                
                                if isUploadingPhoto {
                                    ZStack {
                                        Circle()
                                            .fill(.black.opacity(0.4))
                                            .frame(width: 64, height: 64)
                                        ProgressView()
                                            .tint(.white)
                                    }
                                } else {
                                    ZStack {
                                        Circle()
                                            .fill(Color(.systemBackground))
                                            .frame(width: 22, height: 22)
                                        Image(systemName: "camera.fill")
                                            .font(.system(size: 11))
                                            .foregroundStyle(roleColor)
                                    }
                                    .offset(x: 2, y: 2)
                                }
                            }
                        }
                        .disabled(isUploadingPhoto)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text(user?.fullName ?? "")
                                .font(.headline)
                            Text(user?.email ?? "")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(roleLabel)
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundStyle(roleColor)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(roleColor.opacity(0.12))
                                .cornerRadius(6)
                        }
                    }
                    .padding(.vertical, 8)
                }
                
                Section("Account") {
                    LabeledContent("First Name", value: user?.firstName ?? "")
                    LabeledContent("Last Name", value: user?.lastName ?? "")
                    LabeledContent("Email", value: user?.email ?? "")
                    LabeledContent("Role", value: roleLabel)
                }
                
                Section {
                    Button(role: .destructive) {
                        authService.logout()
                    } label: {
                        HStack {
                            Spacer()
                            Label("Log Out", systemImage: "rectangle.portrait.and.arrow.right")
                                .fontWeight(.semibold)
                            Spacer()
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Profile")
            .onChange(of: selectedPhoto) { _, newItem in
                guard let newItem else { return }
                uploadPhoto(item: newItem)
            }
        }
    }
    
    @MainActor
    func uploadPhoto(item: PhotosPickerItem) {
        isUploadingPhoto = true
        
        Task {
            guard let rawData = try? await item.loadTransferable(type: Data.self),
                  let userId = user?.id else {
                isUploadingPhoto = false
                return
            }

            // Kompresuj sliku na max 300x300px, JPEG 70%
            let data: Data
            if let uiImage = UIImage(data: rawData),
               let resized = uiImage.resized(to: CGSize(width: 300, height: 300)),
               let compressed = resized.jpegData(compressionQuality: 0.7) {
                data = compressed
            } else {
                data = rawData
            }
            
            let storageRef = Storage.storage().reference().child("profileImages/\(userId).jpg")
            let metadata = StorageMetadata()
            metadata.contentType = "image/jpeg"
            
            do {
                _ = try await storageRef.putDataAsync(data, metadata: metadata)
                let url = try await storageRef.downloadURL()
                
                let db = Firestore.firestore()
                try await db.collection("users").document(userId).updateData([
                    "profileImageURL": url.absoluteString
                ])
                
                if var updatedUser = authService.currentUser {
                    updatedUser.profileImageURL = url.absoluteString
                    authService.currentUser = updatedUser
                }
                isUploadingPhoto = false
            } catch {
                print("Upload error: \(error.localizedDescription)")
                isUploadingPhoto = false
            }
        }
    }
}
extension UIImage {
    func resized(to size: CGSize) -> UIImage? {
        let aspectWidth = size.width / self.size.width
        let aspectHeight = size.height / self.size.height
        let scale = min(aspectWidth, aspectHeight)
        let newSize = CGSize(width: self.size.width * scale, height: self.size.height * scale)
        
        UIGraphicsBeginImageContextWithOptions(newSize, false, 0)
        defer { UIGraphicsEndImageContext() }
        draw(in: CGRect(origin: .zero, size: newSize))
        return UIGraphicsGetImageFromCurrentImageContext()
    }
}
