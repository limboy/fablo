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
        #if os(macOS)
        macBody
        #else
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
                    Text(Self.footnote)
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
                    .disabled(!canConnect)
                }
            }
            .disabled(isConnecting)
            .navigationTitle("连接服务")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
            }
            .task { loadSavedConnection() }
            .interactiveDismissDisabled(isConnecting)
        }
        #endif
    }

    private static let footnote = "短文、封面、音频和解析由服务端生成并保存。连接后即可查看书库。"
    private var canConnect: Bool { !isConnecting && !address.isEmpty && !token.isEmpty }

    private func loadSavedConnection() {
        if let connection = studio.client?.connection {
            address = connection.baseURL.absoluteString
            token = connection.token
        }
    }

    #if os(macOS)
    /// A compact Mac sheet: title, fields and buttons share one leading edge, and the sheet hugs its content.
    private var macBody: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("连接服务").font(.title2.bold())

            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                GridRow {
                    Text("地址").gridColumnAlignment(.trailing)
                    TextField("地址", text: $address, prompt: Text(verbatim: "https://fablo.example.com"))
                }
                GridRow {
                    Text("访问令牌")
                    SecureField("访问令牌", text: $token, prompt: Text(verbatim: ""))
                }
            }
            .textFieldStyle(.roundedBorder)
            .labelsHidden()
            .autocorrectionDisabled()
            .disabled(isConnecting)

            Text(Self.footnote).font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let errorMessage {
                Text(errorMessage).font(.callout).foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                if isConnecting {
                    ProgressView().controlSize(.small)
                    Text("正在连接…").foregroundStyle(.secondary)
                }
                Spacer()
                Button("取消") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("连接并保存") { Task { await connect() } }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .foregroundStyle(Theme.onAccent)
                    .disabled(!canConnect)
            }
            .padding(.top, 4)
        }
        .padding(24)
        .frame(width: 460)
        .task { loadSavedConnection() }
        .interactiveDismissDisabled(isConnecting)
    }
    #endif

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
