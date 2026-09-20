import SwiftUI

/// AI 对话：仅可选用已配置 API Key 的 Provider；本地保存历史并可管理
struct AIChatView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.theme) private var theme
    @State private var path = NavigationPath()
    @State private var showClearAllConfirm = false
    @State private var renamingID: UUID?
    @State private var renameText = ""

    var body: some View {
        NavigationStack(path: $path) {
            List {
                if store.chatCapableProviders.isEmpty {
                    Section {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("尚未配置可用模型")
                                .font(.headline)
                            Text("请到「设置 → AI 设置」添加 Provider 并填写 API Key。对话仅限已配置 Key 的模型。")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 6)
                    }
                }

                Section {
                    if store.chatConversations.isEmpty {
                        Text("暂无对话，点右上角新建")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(store.chatConversations) { conv in
                            NavigationLink(value: conv.id) {
                                ChatConversationRow(conversation: conv)
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    store.deleteChatConversation(conv.id)
                                } label: {
                                    Label("删除", systemImage: "trash")
                                }
                                Button {
                                    renamingID = conv.id
                                    renameText = conv.title
                                } label: {
                                    Label("重命名", systemImage: "pencil")
                                }
                                .tint(.orange)
                            }
                        }
                        .onDelete { store.deleteChatConversations(at: $0) }
                    }
                } header: {
                    Text("历史记录")
                }
            }
            .navigationTitle("AI 对话")
            .navigationDestination(for: UUID.self) { id in
                AIChatDetailView(conversationID: id)
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if !store.chatConversations.isEmpty {
                        Button("清空", role: .destructive) {
                            showClearAllConfirm = true
                        }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        let conv = store.createChatConversation()
                        path.append(conv.id)
                    } label: {
                        Label("新建", systemImage: "square.and.pencil")
                    }
                    .disabled(store.chatCapableProviders.isEmpty)
                }
            }
            .alert("清空全部对话？", isPresented: $showClearAllConfirm) {
                Button("取消", role: .cancel) {}
                Button("清空", role: .destructive) {
                    store.clearAllChatConversations()
                    path = NavigationPath()
                }
            } message: {
                Text("将删除所有本地对话历史，且不可恢复。")
            }
            .alert("重命名对话", isPresented: Binding(
                get: { renamingID != nil },
                set: { if !$0 { renamingID = nil } }
            )) {
                TextField("标题", text: $renameText)
                Button("取消", role: .cancel) { renamingID = nil }
                Button("保存") {
                    if let id = renamingID {
                        store.renameChatConversation(id, to: renameText)
                    }
                    renamingID = nil
                }
            }
        }
    }
}

private struct ChatConversationRow: View {
    @Environment(AppStore.self) private var store
    let conversation: ChatConversation

    private var providerName: String {
        guard let pid = conversation.providerID,
              let p = store.aiProviders.first(where: { $0.id == pid }) else {
            return "未指定模型"
        }
        let m = (conversation.model?.isEmpty == false ? conversation.model! : p.model)
        return "\(p.name) · \(m)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(conversation.title)
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
                Text(Self.relative(conversation.updatedAt))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(conversation.previewText)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            Text(providerName)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 2)
    }

    private static func relative(_ date: Date) -> String {
        let diff = Date().timeIntervalSince(date)
        if diff < 3600 { return "\(max(1, Int(diff / 60)))分钟前" }
        if diff < 86400 { return "\(Int(diff / 3600))小时前" }
        if diff < 30 * 86400 { return "\(Int(diff / 86400))天前" }
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "yyyy年M月d日"
        return f.string(from: date)
    }
}

struct AIChatDetailView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.theme) private var theme
    let conversationID: UUID

    @State private var input = ""
    @State private var isSending = false
    @State private var errorText: String?
    @FocusState private var inputFocused: Bool
    @State private var showClearConfirm = false

    private var conversation: ChatConversation? {
        store.chatConversations.first(where: { $0.id == conversationID })
    }

    private var providers: [AIProvider] {
        store.chatCapableProviders
    }

    var body: some View {
        VStack(spacing: 0) {
            if let conv = conversation {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 12) {
                            ForEach(conv.messages) { msg in
                                ChatBubble(message: msg)
                                    .id(msg.id)
                            }
                            if isSending {
                                HStack {
                                    ProgressView()
                                        .scaleEffect(0.85)
                                    Text("正在回复…")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                }
                                .padding(.horizontal, 12)
                                .id("sending")
                            }
                            Color.clear.frame(height: 8).id("bottom")
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                    }
                    // 下滑/拖动消息列表时收起键盘（跟随手指）
                    .scrollDismissesKeyboard(.interactively)
                    .onScrollGeometryChange(for: CGFloat.self) { geo in
                        geo.contentOffset.y
                    } action: { oldY, newY in
                        // 明显滑动浏览时再收起，避免误触
                        guard inputFocused, abs(newY - oldY) > 12 else { return }
                        inputFocused = false
                    }
                    .onChange(of: conv.messages.count) { _, _ in
                        DispatchQueue.main.async {
                            withAnimation(.easeOut(duration: 0.2)) {
                                proxy.scrollTo("bottom", anchor: .bottom)
                            }
                        }
                    }
                    .onChange(of: isSending) { _, sending in
                        if sending {
                            DispatchQueue.main.async {
                                proxy.scrollTo("sending", anchor: .bottom)
                            }
                        }
                    }
                }

                if let errorText {
                    Text(errorText)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 4)
                }

                Divider()
                inputBar(conv: conv)
            } else {
                ContentUnavailableView("对话不存在", systemImage: "bubble.left.and.bubble.right")
            }
        }
        .navigationTitle(conversation?.title ?? "对话")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Section("模型（仅已配置 Key）") {
                        if providers.isEmpty {
                            Text("无可用模型")
                        } else {
                            ForEach(providers) { p in
                                let models = p.availableModels
                                if models.count <= 1 {
                                    Button {
                                        store.setChatProvider(
                                            conversationID: conversationID,
                                            providerID: p.id,
                                            model: models.first ?? p.model
                                        )
                                    } label: {
                                        let label = p.name + " · " + (models.first ?? p.model)
                                        if conversation?.providerID == p.id {
                                            Label(label, systemImage: "checkmark")
                                        } else {
                                            Text(label)
                                        }
                                    }
                                } else {
                                    Menu(p.name) {
                                        ForEach(models, id: \.self) { m in
                                            Button {
                                                store.setChatProvider(
                                                    conversationID: conversationID,
                                                    providerID: p.id,
                                                    model: m
                                                )
                                            } label: {
                                                let selected = conversation?.providerID == p.id
                                                    && (conversation?.model == m
                                                        || (conversation?.model == nil && m == p.model))
                                                if selected {
                                                    Label(m, systemImage: "checkmark")
                                                } else {
                                                    Text(m)
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                    Divider()
                    Button("清空本对话消息", role: .destructive) {
                        showClearConfirm = true
                    }
                } label: {
                    Label("选项", systemImage: "ellipsis.circle")
                }
                .labelStyle(.iconOnly)
            }
        }
        .alert("清空本对话消息？", isPresented: $showClearConfirm) {
            Button("取消", role: .cancel) {}
            Button("清空", role: .destructive) {
                store.clearChatMessages(conversationID)
            }
        }
    }

    @ViewBuilder
    private func inputBar(conv: ChatConversation) -> some View {
        HStack(alignment: .bottom, spacing: 10) {
            TextField("输入消息…", text: $input, axis: .vertical)
                .lineLimit(1...6)
                .textFieldStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous)
                        .fill(Color(.secondarySystemBackground))
                )
                .focused($inputFocused)
                .disabled(isSending || providers.isEmpty)

            Button {
                Task { await send() }
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 32))
                    .symbolRenderingMode(.hierarchical)
            }
            .disabled(isSending || input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || providers.isEmpty)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private func send() async {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        input = ""
        errorText = nil
        isSending = true
        defer { isSending = false }
        do {
            try await store.sendChatMessage(conversationID: conversationID, text: text)
        } catch {
            errorText = error.localizedDescription
        }
    }
}

private struct ChatBubble: View {
    let message: ChatMessage

    var body: some View {
        HStack {
            if message.role == .user { Spacer(minLength: 40) }
            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 4) {
                Text(message.content)
                    .font(.body)
                    .foregroundStyle(message.isError ? Color.red : Color.primary)
                    .textSelection(.enabled)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(
                        RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous)
                            .fill(bubbleColor)
                    )
                if message.role == .assistant, let name = message.providerName, !name.isEmpty {
                    Text(name)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 4)
                }
            }
            if message.role != .user { Spacer(minLength: 40) }
        }
    }

    private var bubbleColor: Color {
        if message.isError {
            return Color.red.opacity(0.12)
        }
        switch message.role {
        case .user:
            return Color.accentColor.opacity(0.18)
        case .assistant:
            return Color(.secondarySystemBackground)
        case .system:
            return Color(.tertiarySystemBackground)
        }
    }
}
