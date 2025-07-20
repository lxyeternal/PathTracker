import SwiftUI

struct HelpSupportView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selectedQuestion: FAQItem?
    @State private var feedbackText = ""
    @State private var showingFeedbackSheet = false
    
    var body: some View {
        NavigationView {
            List {
                Section("Quick Actions") {
                    Button(action: { showingFeedbackSheet = true }) {
                        HelpActionRow(
                            title: "Send Feedback",
                            subtitle: "Report bugs or suggest improvements",
                            icon: "envelope.fill",
                            color: .blue
                        )
                    }
                    
                    Button(action: {}) {
                        HelpActionRow(
                            title: "Contact Support",
                            subtitle: "Get help from our support team",
                            icon: "message.fill",
                            color: .green
                        )
                    }
                    
                    Button(action: {}) {
                        HelpActionRow(
                            title: "User Guide",
                            subtitle: "Learn how to use PathTracker",
                            icon: "book.fill",
                            color: .orange
                        )
                    }
                }
                
                Section("Frequently Asked Questions") {
                    ForEach(faqItems) { item in
                        FAQRow(item: item, isExpanded: selectedQuestion?.id == item.id) {
                            selectedQuestion = selectedQuestion?.id == item.id ? nil : item
                        }
                    }
                }
                
                Section("App Information") {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("1.0.0")
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Text("Build")
                        Spacer()
                        Text("100")
                            .foregroundColor(.secondary)
                    }
                    
                    Button("Privacy Policy") {}
                    Button("Terms of Service") {}
                }
            }
            .navigationTitle("Help & Support")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(
                trailing: Button("Done") { dismiss() }
            )
        }
        .sheet(isPresented: $showingFeedbackSheet) {
            FeedbackSheet(feedbackText: $feedbackText)
        }
    }
    
    private let faqItems = [
        FAQItem(
            question: "How do I start tracking my journey?",
            answer: "Tap the record button on the Dashboard to start tracking your current location. Make sure you've granted location permissions to the app."
        ),
        FAQItem(
            question: "Why isn't my location being recorded?",
            answer: "Check that you've granted location permissions and that your device has a clear GPS signal. Try moving to an open area away from buildings."
        ),
        FAQItem(
            question: "Can I edit my journey after recording?",
            answer: "Yes! You can edit journey titles, add notes, and include photos from the Timeline view. Tap on any journey to view details and make changes."
        ),
        FAQItem(
            question: "How do I export my travel data?",
            answer: "Go to Profile > Settings > Export Data to save your journeys in various formats including JSON, GPX, and KML."
        ),
        FAQItem(
            question: "Is my location data private?",
            answer: "Yes, all your location data is stored locally on your device. You control what data to share and can review privacy settings at any time."
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
                Section("Feedback Type") {
                    Picker("Type", selection: $feedbackType) {
                        ForEach(FeedbackType.allCases, id: \.self) { type in
                            Text(type.rawValue).tag(type)
                        }
                    }
                    .pickerStyle(SegmentedPickerStyle())
                }
                
                Section("Your Feedback") {
                    TextEditor(text: $feedbackText)
                        .frame(minHeight: 100)
                }
                
                Section {
                    Button("Send Feedback") {
                        sendFeedback()
                    }
                    .disabled(feedbackText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .navigationTitle("Send Feedback")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(
                leading: Button("Cancel") { dismiss() },
                trailing: Button("Send") { sendFeedback() }
                    .disabled(feedbackText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            )
        }
        .alert("Thank You!", isPresented: $showingSuccessAlert) {
            Button("OK") { dismiss() }
        } message: {
            Text("Your feedback has been sent. We appreciate your input!")
        }
    }
    
    private func sendFeedback() {
        // Simulate sending feedback
        showingSuccessAlert = true
        feedbackText = ""
    }
}

enum FeedbackType: String, CaseIterable {
    case general = "General"
    case bug = "Bug Report"
    case feature = "Feature Request"
}

#Preview {
    HelpSupportView()
}