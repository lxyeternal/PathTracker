import SwiftUI

struct HelpSupportView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selectedQuestion: FAQItem?
    @State private var feedbackText = ""
    @State private var showingFeedbackSheet = false
    
    var body: some View {
        NavigationView {
            List {
                Section("快速操作") {
                    Button(action: { showingFeedbackSheet = true }) {
                        HelpActionRow(
                            title: "发送反馈",
                            subtitle: "报告错误或提出改进建议",
                            icon: "envelope.fill",
                            color: .blue
                        )
                    }
                    
                    Button(action: {}) {
                        HelpActionRow(
                            title: "联系支持",
                            subtitle: "从我们的支持团队获取帮助",
                            icon: "message.fill",
                            color: .green
                        )
                    }
                    
                    Button(action: {}) {
                        HelpActionRow(
                            title: "用户指南",
                            subtitle: "学习如何使用 PathTracker",
                            icon: "book.fill",
                            color: .orange
                        )
                    }
                }
                
                Section("常见问题") {
                    ForEach(faqItems) { item in
                        FAQRow(item: item, isExpanded: selectedQuestion?.id == item.id) {
                            selectedQuestion = selectedQuestion?.id == item.id ? nil : item
                        }
                    }
                }
                
                Section("应用信息") {
                    HStack {
                        Text("版本")
                        Spacer()
                        Text("1.0.0")
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Text("构建版本")
                        Spacer()
                        Text("100")
                            .foregroundColor(.secondary)
                    }
                    
                    Button("隐私政策") {}
                    Button("服务条款") {}
                }
            }
            .navigationTitle("帮助与支持")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(
                trailing: Button("完成") { dismiss() }
            )
        }
        .sheet(isPresented: $showingFeedbackSheet) {
            FeedbackSheet(feedbackText: $feedbackText)
        }
    }
    
    private let faqItems = [
        FAQItem(
            question: "如何开始追踪我的行程？",
            answer: "点击仪表盘上的“记录”按钮即可开始追踪您当前的位置。请确保您已授予应用位置权限。"
        ),
        FAQItem(
            question: "为什么我的位置没有被记录？",
            answer: "请检查您是否已授予位置权限，以及您的设备是否有清晰的GPS信号。请尝试移动到远离建筑物的开阔区域。"
        ),
        FAQItem(
            question: "记录后可以编辑我的行程吗？",
            answer: "是的！您可以从时间线视图中编辑行程标题、添加备注和包含照片。点击任何行程以查看详情并进行更改。"
        ),
        FAQItem(
            question: "如何导出我的旅行数据？",
            answer: "前往“我的” > “设置” > “导出数据”，以JSON、GPX和KML等多种格式保存您的行程。"
        ),
        FAQItem(
            question: "我的位置数据是私密的吗？",
            answer: "是的，您所有的位置数据都存储在您的设备本地。您可以控制要共享的数据，并可以随时查看隐私设置。"
        )
    ]
}

struct FAQItem: Identifiable {
    let id = UUID()
    let question: String
    let answer: String
}

struct HelpActionRow: View {
    let title: String
    let subtitle: String
    let icon: String
    let color: Color
    
    var body: some View {
        HStack(spacing: 16) {
            Circle()
                .fill(color)
                .frame(width: 40, height: 40)
                .overlay(
                    Image(systemName: icon)
                        .font(.caption)
                        .foregroundColor(.white)
                )
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                    .foregroundColor(.primary)
                
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }
}

struct FAQRow: View {
    let item: FAQItem
    let isExpanded: Bool
    let onTap: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: onTap) {
                HStack {
                    Text(item.question)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                        .multilineTextAlignment(.leading)
                    
                    Spacer()
                    
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .buttonStyle(PlainButtonStyle())
            
            if isExpanded {
                Text(item.answer)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.top, 4)
            }
        }
        .padding(.vertical, 4)
    }
}

struct FeedbackSheet: View {
    @Binding var feedbackText: String
    @Environment(\.dismiss) private var dismiss
    @State private var feedbackType: FeedbackType = .general
    @State private var showingSuccessAlert = false
    
    var body: some View {
        NavigationView {
            Form {
                Section("反馈类型") {
                    Picker("类型", selection: $feedbackType) {
                        ForEach(FeedbackType.allCases, id: \.self) { type in
                            Text(type.rawValue).tag(type)
                        }
                    }
                    .pickerStyle(SegmentedPickerStyle())
                }
                
                Section("你的反馈") {
                    TextEditor(text: $feedbackText)
                        .frame(minHeight: 100)
                }
                
                Section {
                    Button("发送反馈") {
                        sendFeedback()
                    }
                    .disabled(feedbackText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .navigationTitle("发送反馈")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(
                leading: Button("取消") { dismiss() },
                trailing: Button("发送") { sendFeedback() }
                    .disabled(feedbackText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            )
        }
        .alert("谢谢！", isPresented: $showingSuccessAlert) {
            Button("好的") { dismiss() }
        } message: {
            Text("您的反馈已发送。我们感谢您的意见！")
        }
    }
    
    private func sendFeedback() {
        // Simulate sending feedback
        showingSuccessAlert = true
        feedbackText = ""
    }
}

enum FeedbackType: String, CaseIterable {
    case general = "一般"
    case bug = "错误报告"
    case feature = "功能请求"
}

#Preview {
    HelpSupportView()
}