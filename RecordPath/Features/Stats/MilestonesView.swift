import SwiftUI

struct MilestonesRoute: Hashable {}

/// Every badge, earned and not yet, grouped by kind.
struct MilestonesView: View {
    let progress: MilestoneProgress
    @State private var selected: MilestoneProgress.Status?
    @State private var appeared = false

    private var earned: Int { progress.all.filter(\.isReached).count }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                header
                ForEach(Milestone.Kind.allCases, id: \.self) { kind in
                    section(kind)
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 32)
        }
        .navigationTitle("里程碑")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $selected) { MilestoneDetailSheet(status: $0) }
        .onAppear { withAnimation(.spring(response: 0.6, dampingFraction: 0.75)) { appeared = true } }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 18) {
            ZStack {
                ForEach(Array(progress.reached.prefix(3).enumerated().reversed()), id: \.element.id) { index, item in
                    MilestoneBadge(milestone: item.milestone, size: 70)
                        .rotationEffect(.degrees(Double(index - 1) * -10))
                        .offset(x: CGFloat(index - 1) * -26)
                }
            }
            .frame(width: 120, height: 80)
            VStack(alignment: .leading, spacing: 4) {
                Text("已获得").font(.subheadline).foregroundStyle(.secondary)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(earned)").font(.system(size: 40, weight: .bold, design: .rounded)).contentTransition(.numericText())
                    Text("/ \(progress.all.count)").font(.title3).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.top, 8)
    }

    private func section(_ kind: Milestone.Kind) -> some View {
        let items = progress.all.filter { $0.milestone.kind == kind }
        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text(kind.title).font(.title3.bold())
                Spacer()
                Text("\(items.filter(\.isReached).count) / \(items.count)").font(.subheadline).foregroundStyle(.secondary).monospacedDigit()
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 12)], spacing: 22) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    Button { selected = item } label: { cell(item) }
                        .buttonStyle(PressableStyle())
                        .scaleEffect(appeared ? 1 : 0.6)
                        .opacity(appeared ? 1 : 0)
                        .animation(.spring(response: 0.5, dampingFraction: 0.7).delay(Double(index) * 0.04), value: appeared)
                }
            }
        }
    }

    private func cell(_ item: MilestoneProgress.Status) -> some View {
        VStack(spacing: 4) {
            MilestoneBadge(milestone: item.milestone, isReached: item.isReached, progress: item.fraction, size: 82)
                .padding(.bottom, 4)
            Text(item.milestone.title)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(item.isReached ? .primary : .secondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
            Text(item.date.map { $0.formatted(.dateTime.year().month().day().locale(appLocale)) }
                 ?? item.fraction.formatted(.percent.precision(.fractionLength(0)).locale(appLocale)))
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}
