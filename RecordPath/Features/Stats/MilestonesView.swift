import SwiftUI

struct MilestonesRoute: Hashable {}

/// Every badge, earned and not yet, grouped by kind. The newest medal leads the page; in each
/// kind the one you're working towards is lit, the ones after it wait quietly.
struct MilestonesView: View {
    let progress: MilestoneProgress
    @State private var selected: MilestoneProgress.Status?
    @State private var appeared = false

    private var earned: Int { progress.all.filter(\.isReached).count }

    /// The most recently earned medal, or the closest one still to go.
    private var lead: MilestoneProgress.Status? {
        if let latest = progress.reached.first { return progress.all.first { $0.id == latest.id } }
        return progress.all.filter(\.isNext).max { $0.fraction < $1.fraction }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                hero
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

    // MARK: Hero

    private var hero: some View {
        VStack(spacing: 14) {
            if let lead {
                Button { selected = lead } label: {
                    ZStack {
                        HeroGlow(color: lead.milestone.kind.colors[0], isLit: lead.isReached)
                            .frame(width: 260, height: 260)
                        MilestoneBadge(milestone: lead.milestone, isReached: lead.isReached, progress: lead.fraction,
                                       size: 128, shimmers: lead.isReached)
                            .phaseAnimator([0, 1]) { badge, phase in
                                badge.offset(y: phase == 0 ? -3 : 3)
                            } animation: { _ in .easeInOut(duration: 2.4) }
                            .scaleEffect(appeared ? 1 : 0.7)
                            .opacity(appeared ? 1 : 0)
                    }
                    .frame(height: 190)
                }
                .buttonStyle(PressableStyle())

                VStack(spacing: 4) {
                    Text(lead.isReached ? "最近获得" : "第一枚奖章就在前面")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(lead.milestone.title).font(.title3.bold())
                    if let date = lead.date {
                        Text(date.formatted(.dateTime.year().month().day().locale(appLocale)))
                            .font(.subheadline).foregroundStyle(.secondary)
                    } else {
                        Text(lead.remaining).font(.subheadline).foregroundStyle(.secondary)
                    }
                }
            }

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(earned)")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .contentTransition(.numericText())
                Text("/ \(progress.all.count) 枚").font(.headline).foregroundStyle(.secondary)
            }
            .padding(.top, 6)
            tally
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 4)
    }

    /// One small bar per medal, in its kind's colour once earned.
    private var tally: some View {
        HStack(spacing: 3) {
            ForEach(Array(progress.all.enumerated()), id: \.element.id) { index, item in
                Capsule()
                    .fill(item.isReached ? AnyShapeStyle(item.milestone.kind.colors[1].gradient) : AnyShapeStyle(Color.secondary.opacity(0.15)))
                    .frame(height: 6)
                    .scaleEffect(y: appeared ? 1 : 0.2)
                    .animation(.spring(response: 0.5, dampingFraction: 0.7).delay(0.2 + Double(index) * 0.02), value: appeared)
            }
        }
        .frame(maxWidth: 300)
        .accessibilityHidden(true)
    }

    // MARK: Sections

    private func section(_ kind: Milestone.Kind) -> some View {
        let items = progress.all.filter { $0.milestone.kind == kind }
        return VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: kind.symbol)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(LinearGradient(colors: kind.colors, startPoint: .top, endPoint: .bottom)))
                VStack(alignment: .leading, spacing: 1) {
                    Text(kind.title).font(.title3.bold())
                    Text(soFar(kind, current: items.first?.current ?? 0))
                        .font(.footnote).foregroundStyle(.secondary).monospacedDigit()
                }
                Spacer()
                Text("\(items.filter(\.isReached).count) / \(items.count)")
                    .font(.subheadline.weight(.medium)).foregroundStyle(.secondary).monospacedDigit()
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 12)], spacing: 24) {
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

    /// "已走 1,412 公里"
    private func soFar(_ kind: Milestone.Kind, current: Double) -> String {
        let value = Int(current.rounded(.down)).formatted(.number.locale(appLocale))
        return switch kind {
        case .distance: String(localized: "已走 \(value) 公里，不含飞行", bundle: .appLanguage)
        case .countries: String(localized: "已去过 \(value) 个国家和地区", bundle: .appLanguage)
        case .provinces: String(localized: "已点亮 \(value) 个省份", bundle: .appLanguage)
        case .cities: String(localized: "已去过 \(value) 座城市", bundle: .appLanguage)
        case .days: String(localized: "已记录 \(value) 天", bundle: .appLanguage)
        }
    }

    private func cell(_ item: MilestoneProgress.Status) -> some View {
        VStack(spacing: 4) {
            MilestoneBadge(milestone: item.milestone, isReached: item.isReached,
                           progress: item.isNext ? item.fraction : 0, size: 82)
                .opacity(item.isReached || item.isNext ? 1 : 0.55)
                .padding(.bottom, 4)
            Text(item.milestone.title)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(item.isReached ? .primary : .secondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
            Group {
                if let date = item.date {
                    Text(date.formatted(.dateTime.year().month().day().locale(appLocale))).foregroundStyle(.tertiary)
                } else {
                    Text(item.remaining).foregroundStyle(item.isNext ? AnyShapeStyle(item.milestone.kind.colors[1]) : AnyShapeStyle(.tertiary))
                }
            }
            .font(.caption2)
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

/// Soft light behind the leading medal, with slow rays turning in it.
private struct HeroGlow: View {
    let color: Color
    let isLit: Bool
    @State private var turn = false

    var body: some View {
        ZStack {
            Circle()
                .fill(RadialGradient(colors: [color.opacity(isLit ? 0.45 : 0.15), color.opacity(0)],
                                     center: .center, startRadius: 10, endRadius: 130))
            if isLit {
                Rays(count: 14)
                    .fill(RadialGradient(colors: [color.opacity(0.28), color.opacity(0)], center: .center, startRadius: 30, endRadius: 130))
                    .rotationEffect(.degrees(turn ? 360 : 0))
                    .animation(.linear(duration: 60).repeatForever(autoreverses: false), value: turn)
            }
        }
        .allowsHitTesting(false)
        .onAppear { turn = true }
    }
}

/// Thin wedges fanning out from the centre.
private struct Rays: Shape {
    let count: Int

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        var path = Path()
        for index in 0..<count {
            let angle = Double(index) / Double(count) * 2 * .pi
            let half = .pi / Double(count) * 0.35
            path.move(to: center)
            path.addLine(to: CGPoint(x: center.x + radius * cos(angle - half), y: center.y + radius * sin(angle - half)))
            path.addLine(to: CGPoint(x: center.x + radius * cos(angle + half), y: center.y + radius * sin(angle + half)))
            path.closeSubpath()
        }
        return path
    }
}
