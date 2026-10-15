import SwiftUI

struct BackendSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(StoryStudio.self) private var studio
    @Environment(SpeechPlayer.self) private var player
    @State private var address = ""
    @State private var token = ""
    @State private var isConnecting = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("https://fablo.example.com", text: $address)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("访问令牌", text: $token)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("后端服务")
                } footer: {
                    Text("短文、封面、音频和解析由服务端生成并保存。连接后即可查看书库。")
                }
                if let errorMessage {
                    Section { Text(errorMessage).foregroundStyle(.red) }
                }
                Section {
                    Button {
                        Task { await connect() }
                    } label: {
                        HStack {
                            Text(isConnecting ? "正在连接…" : "连接并保存")
                            if isConnecting { Spacer(); ProgressView() }
                        }
                    }
                    .disabled(isConnecting || address.isEmpty || token.isEmpty)
                }
            }
            .disabled(isConnecting)
            .navigationTitle("连接服务")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
            }
            .task {
                if let connection = studio.client?.connection {
                    address = connection.baseURL.absoluteString
                    token = connection.token
                }
            }
            .interactiveDismissDisabled(isConnecting)
        }
    }

    private func connect() async {
        isConnecting = true
        errorMessage = nil
        defer { isConnecting = false }
        do {
            let connection = try BackendConnection(address: address, token: token)
            _ = try await BackendClient(connection: connection).jobs()
            try await BackendCredentials.shared.save(connection)
            player.stop()
            await studio.connect(connection)
            await studio.refresh()
            dismiss()
        } catch { errorMessage = error.localizedDescription }
    }
}
