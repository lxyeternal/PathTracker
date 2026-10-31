import SwiftUI

/// A pattern noticed in the person's life, said quietly on Today: at most one a week.
struct EchoCard: View {
    private var summaries = PlaceSummaries.shared
    @State private var echo: Echo?

    var body: some View {
        Group {
            if let echo {
                HStack(alignment: .top, spacing: 14) {
                    Image(systemName: echo.symbol)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 38, height: 38)
                        .background(Circle().fill(LinearGradient(colors: [.indigo, .purple], startPoint: .top, endPoint: .bottom)))
                    VStack(alignment: .leading, spacing: 5) {
                        Text(echo.title).font(.subheadline.weight(.semibold))
                        Text(echo.detail).font(.footnote).foregroundStyle(.secondary)
                        if let day = echo.day {
                            NavigationLink(value: DayRoute(day: day)) {
                                Text("看看那天").font(.footnote.weight(.semibold))
                            }
                            .padding(.top, 2)
                        }
                    }
                    Spacer(minLength: 0)
                    Button("关闭", systemImage: "xmark") {
                        EchoSchedule.dismiss()
                        withAnimation(.smooth) { self.echo = nil }
                    }
                    .labelStyle(.iconOnly)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                }
                .padding(16)
                .background(.background.secondary, in: .rect(cornerRadius: 24, style: .continuous))
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .onChange(of: summaries.echoes, initial: true) { _, echoes in
            let picked = EchoSchedule.pick(from: echoes)
            withAnimation(.smooth) { echo = picked }
        }
    }
}
