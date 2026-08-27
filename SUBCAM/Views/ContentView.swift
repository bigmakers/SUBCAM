import SwiftUI

struct ContentView: View {
    @StateObject private var permissionManager = PermissionManager()

    var body: some View {
        Group {
            if permissionManager.allAuthorized {
                RecordingView()
            } else {
                PermissionRequestView(permissionManager: permissionManager)
            }
        }
        .onAppear {
            permissionManager.checkPermissions()
        }
    }
}

struct PermissionRequestView: View {
    @ObservedObject var permissionManager: PermissionManager

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 32) {
                Image(systemName: "captions.bubble.fill")
                    .font(.system(size: 64))
                    .foregroundColor(.white)

                Text("SUBCAM")
                    .font(.system(size: 36, weight: .bold))
                    .foregroundColor(.white)

                Text(L10n.permissionIntro)
                    .font(.body)
                    .foregroundColor(.gray)

                VStack(alignment: .leading, spacing: 16) {
                    PermissionRow(
                        icon: "camera.fill",
                        title: L10n.permissionCamera,
                        granted: permissionManager.cameraAuthorized
                    )
                    PermissionRow(
                        icon: "mic.fill",
                        title: L10n.permissionMicrophone,
                        granted: permissionManager.microphoneAuthorized
                    )
                    PermissionRow(
                        icon: "waveform",
                        title: L10n.permissionSpeech,
                        granted: permissionManager.speechAuthorized
                    )
                }
                .padding(.vertical, 16)

                Button {
                    Task {
                        await permissionManager.requestAllPermissions()
                    }
                } label: {
                    Text(L10n.continueButton)
                        .font(.headline)
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.white)
                        .cornerRadius(12)
                }
                .padding(.horizontal, 40)
            }
        }
    }
}

struct PermissionRow: View {
    let icon: String
    let title: String
    let granted: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .frame(width: 24)
                .foregroundColor(.white)
            Text(title)
                .foregroundColor(.white)
            Spacer()
            Image(systemName: granted ? "checkmark.circle.fill" : "circle")
                .foregroundColor(granted ? .green : .gray)
        }
        .padding(.horizontal, 40)
    }
}
