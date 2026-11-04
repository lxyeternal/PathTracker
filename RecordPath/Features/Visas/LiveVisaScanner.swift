import SwiftUI
import VisionKit

/// Point the camera at a visa and it reads itself: the text is recognised live, frame after
/// frame, and the moment the machine-readable lines pass their check the scan completes on
/// its own. Nothing is photographed or kept.
struct LiveVisaScanner: View {
    let done: (VisaScanner.Reading?) -> Void
    let choosePhoto: () -> Void

    @State private var reading = VisaScanner.Reading()
    @State private var finished = false
    @State private var pulse = false

    @MainActor static var isAvailable: Bool { DataScannerViewController.isSupported && DataScannerViewController.isAvailable }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            TextScanner(paused: finished) { lines in update(with: lines) }
                .ignoresSafeArea()
            GeometryReader { proxy in
                let width = proxy.size.width - 40
                let frame = CGRect(x: 20, y: proxy.size.height * 0.30, width: width, height: width / VisaCard.aspect)
                ZStack {
                    // Darken everything but the window the visa goes in.
                    Rectangle()
                        .fill(.black.opacity(0.5))
                        .mask {
                            Rectangle().overlay {
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .frame(width: frame.width, height: frame.height)
                                    .position(x: frame.midX, y: frame.midY)
                                    .blendMode(.destinationOut)
                            }
                            .compositingGroup()
                        }
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(finished ? Color.green : .white.opacity(pulse ? 0.95 : 0.55), lineWidth: finished ? 4 : 2.5)
                        .frame(width: frame.width, height: frame.height)
                        .position(x: frame.midX, y: frame.midY)
                        .scaleEffect(finished ? 1.03 : 1)
                    if finished {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 60, weight: .semibold))
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, .green)
                            .position(x: frame.midX, y: frame.midY)
                            .transition(.scale(scale: 0.4).combined(with: .opacity))
                    }
                    Text(finished ? "读好了" : "把签证页放进框里，对准底部两行字母")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .glassEffect(.regular, in: .capsule)
                        .position(x: frame.midX, y: frame.minY - 34)
                        .contentTransition(.opacity)
                }
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)
            VStack {
                HStack {
                    Button("关闭", systemImage: "xmark") { done(nil) }
                        .labelStyle(.iconOnly)
                        .font(.title3.weight(.semibold))
                        .frame(width: 44, height: 44)
                        .glassEffect(.regular.interactive(), in: .circle)
                        .foregroundStyle(.white)
                    Spacer()
                }
                .padding(.horizontal, 20)
                Spacer()
                checklist
            }
        }
        .environment(\.colorScheme, .dark)
        .sensoryFeedback(.success, trigger: finished)
        .animation(.spring(response: 0.45, dampingFraction: 0.75), value: finished)
        .onAppear { withAnimation(.easeInOut(duration: 1.1).repeatForever()) { pulse = true } }
    }

    /// What has been read so far, ticking off as each piece is found.
    private var checklist: some View {
        VStack(spacing: 14) {
            HStack(spacing: 8) {
                item("国家", done: reading.country != nil)
                item("类型", done: reading.category != nil)
                item("到期日", done: reading.expires != nil)
                item("机读码", done: reading.verified)
            }
            HStack(spacing: 10) {
                Button(action: choosePhoto) {
                    Label("从照片识别", systemImage: "photo.on.rectangle").frame(maxWidth: .infinity)
                }
                .buttonStyle(.glass)
                Button {
                    finish()
                } label: {
                    Label("用这些信息", systemImage: "checkmark").frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .disabled(reading.expires == nil)
            }
            .controlSize(.large)
        }
        .padding(18)
        .glassEffect(.regular, in: .rect(cornerRadius: 30, style: .continuous))
        .padding(.horizontal, 14)
        .padding(.bottom, 8)
    }

    private func item(_ title: LocalizedStringKey, done: Bool) -> some View {
        HStack(spacing: 4) {
            Image(systemName: done ? "checkmark.circle.fill" : "circle.dashed")
                .foregroundStyle(done ? .green : .white.opacity(0.5))
                .contentTransition(.symbolEffect(.replace))
            Text(title).foregroundStyle(.white.opacity(done ? 1 : 0.6))
        }
        .font(.footnote.weight(.semibold))
        .frame(maxWidth: .infinity)
        .animation(.snappy, value: done)
    }

    /// Each frame's text adds to what's known; a field once read stays read.
    private func update(with lines: [String]) {
        guard !finished else { return }
        let fresh = VisaScanner.parse(lines)
        var merged = reading
        if fresh.verified {
            merged = fresh
        } else if !merged.verified {
            merged.country = fresh.country ?? merged.country
            merged.expires = fresh.expires ?? merged.expires
            merged.number = fresh.number ?? merged.number
            merged.holder = fresh.holder ?? merged.holder
        }
        merged.category = fresh.category ?? merged.category
        merged.post = fresh.post ?? merged.post
        merged.issued = fresh.issued ?? merged.issued
        merged.entries = fresh.entries ?? merged.entries
        merged.stayDays = fresh.stayDays ?? merged.stayDays
        reading = merged
        if merged.verified { finish() }
    }

    private func finish() {
        guard !finished else { return }
        finished = true
        let result = reading
        Task {
            try? await Task.sleep(for: .seconds(0.9))
            done(result)
        }
    }
}

/// VisionKit's live text scanner, reporting every line it currently sees, top to bottom.
private struct TextScanner: UIViewControllerRepresentable {
    var paused: Bool
    let onLines: ([String]) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.text(languages: ["en-US", "zh-Hans", "ja-JP", "fr-FR", "de-DE"])],
            qualityLevel: .accurate,
            recognizesMultipleItems: true,
            isHighFrameRateTrackingEnabled: false,
            isPinchToZoomEnabled: true,
            isGuidanceEnabled: false,
            isHighlightingEnabled: false)
        scanner.delegate = context.coordinator
        return scanner
    }

    func updateUIViewController(_ scanner: DataScannerViewController, context: Context) {
        context.coordinator.onLines = onLines
        if paused {
            scanner.stopScanning()
        } else if !scanner.isScanning {
            try? scanner.startScanning()
        }
    }

    static func dismantleUIViewController(_ scanner: DataScannerViewController, coordinator: Coordinator) {
        scanner.stopScanning()
    }

    func makeCoordinator() -> Coordinator { Coordinator(onLines: onLines) }

    @MainActor
    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        var onLines: ([String]) -> Void
        init(onLines: @escaping ([String]) -> Void) { self.onLines = onLines }

        private func report(_ items: [RecognizedItem]) {
            let lines = items.compactMap { item -> (CGFloat, String)? in
                guard case .text(let text) = item else { return nil }
                return (text.bounds.topLeft.y, text.transcript)
            }
            .sorted { $0.0 < $1.0 }
            .flatMap { $0.1.components(separatedBy: .newlines) }
            onLines(lines)
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            report(allItems)
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didUpdate updatedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            report(allItems)
        }
    }
}
