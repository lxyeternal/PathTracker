import SwiftUI
import PhotosUI

struct VisaWalletRoute: Hashable {}

/// The passport and every visa in it, stacked like cards in Wallet. Tapping one lifts it to
/// the top with its details below while the rest settle into a pile at the foot of the
/// screen; tapping it again, or the pile, deals them back out.
struct VisaWalletView: View {
    private var documents = TravelDocuments.shared
    @State private var editing: EditorRequest?
    @State private var scanning = false
    @State private var picking: PhotosPickerItem?
    @State private var choosingPhoto = false
    @State private var reading = false
    @State private var selected: UUID?
    @State private var stackWidth: CGFloat = 360
    @State private var scroll = ScrollPosition(edge: .top)
    @Namespace private var namespace

    private static let spring = Animation.spring(response: 0.55, dampingFraction: 0.82)

    private var chosen: TravelDocument? { selected.flatMap { id in documents.all.first { $0.id == id } } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                if documents.all.isEmpty {
                    WalletEmptyState(scan: startScan, choosePhoto: { choosingPhoto = true },
                                     addByHand: { editing = EditorRequest(document: Self.blank(.visa)) })
                } else if let chosen {
                    card(chosen)
                        .zIndex(10)
                    VisaDetails(document: chosen) { editing = EditorRequest(document: chosen) } onDelete: {
                        withAnimation(Self.spring) { selected = nil }
                        documents.delete(chosen)
                    }
                    .transition(.asymmetric(insertion: .opacity.combined(with: .offset(y: 40)).animation(Self.spring.delay(0.12)),
                                            removal: .opacity.animation(.easeOut(duration: 0.15))))
                    Color.clear.frame(height: pileHeight)
                } else {
                    WalletSummary(documents: documents.sorted)
                        .transition(.opacity)
                    stack
                    if let schengen = documents.sorted.first(where: { $0.isSchengen && !$0.isExpired }) {
                        SchengenCard(visa: schengen).transition(.opacity)
                    }
                    Text("签证信息只保存在你的 iCloud 里。识别在手机上完成，画面和照片不会保存或上传。")
                        .font(.footnote).foregroundStyle(.secondary)
                        .padding(.horizontal, 4)
                        .transition(.opacity)
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 32)
        }
        .scrollPosition($scroll)
        .overlay(alignment: .bottom) {
            if selected != nil { pile }
        }
        .navigationTitle(chosen.map { $0.kind == .passport ? String(localized: "护照", bundle: .appLanguage) : $0.countryName }
                         ?? String(localized: "签证夹", bundle: .appLanguage))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                if let chosen {
                    Button("编辑") { editing = EditorRequest(document: chosen) }
                } else {
                    Menu("添加", systemImage: "plus") {
                        Button("扫描签证", systemImage: "viewfinder", action: startScan)
                        Button("从照片中识别", systemImage: "photo.on.rectangle") { choosingPhoto = true }
                        Divider()
                        Button("手动添加签证", systemImage: "square.and.pencil") { editing = EditorRequest(document: Self.blank(.visa)) }
                        Button("手动添加电子签", systemImage: "qrcode") { editing = EditorRequest(document: Self.blank(.eVisa)) }
                        Button(documents.passport == nil ? "添加护照" : "更新护照", systemImage: "person.text.rectangle") {
                            editing = EditorRequest(document: documents.passport ?? Self.blank(.passport))
                        }
                    }
                }
            }
        }
        .sensoryFeedback(.impact(weight: .light), trigger: selected)
        .sheet(item: $editing) { request in
            VisaEditor(document: request.document, reading: request.reading)
        }
        .fullScreenCover(isPresented: $scanning) {
            LiveVisaScanner { reading in
                scanning = false
                if let reading { open(reading) }
            } choosePhoto: {
                scanning = false
                choosingPhoto = true
            }
        }
        .photosPicker(isPresented: $choosingPhoto, selection: $picking, matching: .images)
        .onChange(of: picking) {
            guard let item = picking else { return }
            picking = nil
            Task {
                if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                    await read(image)
                }
            }
        }
        .overlay {
            if reading {
                VStack(spacing: 14) {
                    ProgressView().controlSize(.large)
                    Text("正在识别签证…").font(.subheadline.weight(.medium))
                }
                .padding(28)
                .glassEffect(.regular, in: .rect(cornerRadius: 26, style: .continuous))
                .transition(.scale(scale: 0.9).combined(with: .opacity))
            }
        }
        .animation(.smooth, value: reading)
    }

    private func card(_ document: TravelDocument) -> some View {
        VisaCard(document: document)
            .cardSheen(selected == document.id)
            .matchedGeometryEffect(id: document.id, in: namespace)
            .shadow(color: .black.opacity(0.08), radius: 1.5, y: -1)
            .shadow(color: .black.opacity(0.12), radius: 14, y: selected == document.id ? 10 : -2)
            .contentShape(.rect(cornerRadius: 16))
            .onTapGesture {
                withAnimation(Self.spring) {
                    selected = selected == document.id ? nil : document.id
                    scroll.scrollTo(edge: .top)
                }
            }
            .accessibilityAddTraits(.isButton)
    }

    /// Overlapping like Wallet: each card's top strip, the last one whole.
    private var stack: some View {
        let sorted = documents.sorted
        let overlap = max(0, stackWidth / VisaCard.aspect - Self.strip)
        return VStack(spacing: -overlap) {
            ForEach(Array(sorted.enumerated()), id: \.element.id) { index, document in
                card(document).zIndex(Double(index))
            }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { stackWidth = $0 }
    }

    /// The other cards, tucked in at the foot of the screen with a sliver of each showing.
    private var pile: some View {
        let others = documents.sorted.filter { $0.id != selected }
        let shown = Array(others.prefix(5))
        return ZStack(alignment: .top) {
            ForEach(Array(shown.enumerated()), id: \.element.id) { index, document in
                VisaCard(document: document)
                    // Full size, running off the foot of the screen: only the tops show.
                    .frame(width: stackWidth, height: stackWidth / VisaCard.aspect)
                    .matchedGeometryEffect(id: document.id, in: namespace)
                    .shadow(color: .black.opacity(0.12), radius: 8, y: -2)
                    .scaleEffect(1 - CGFloat(shown.count - 1 - index) * 0.035, anchor: .top)
                    .offset(y: CGFloat(index) * Self.pileStep)
                    .zIndex(Double(index))
                    .allowsHitTesting(false)
            }
        }
        .frame(width: stackWidth, height: pileHeight, alignment: .top)
        .padding(.horizontal)
        .background(alignment: .top) {
            // A soft fade so the pile reads as resting on the page, not floating over it.
            LinearGradient(colors: [.clear, Color(.systemBackground).opacity(0.9)], startPoint: .top, endPoint: .bottom)
                .frame(height: pileHeight + 60)
                .offset(y: -40)
                .allowsHitTesting(false)
        }
        .contentShape(.rect)
        .onTapGesture { withAnimation(Self.spring) { selected = nil } }
        .accessibilityElement()
        .accessibilityLabel(Text("收起，显示所有卡片"))
        .accessibilityAddTraits(.isButton)
        .ignoresSafeArea(edges: .bottom)
    }

    private static let pileStep: CGFloat = 9
    private var pileHeight: CGFloat {
        let count = min(5, max(documents.all.count - 1, 0))
        return count == 0 ? 0 : 34 + CGFloat(count) * Self.pileStep
    }

    /// How much of each stacked card shows: its header strip.
    private static let strip: CGFloat = 41

    private func startScan() {
        if LiveVisaScanner.isAvailable { scanning = true } else { choosingPhoto = true }
    }

    private func read(_ image: UIImage) async {
        reading = true
        let result = await VisaScanner.read(image)
        reading = false
        open(result)
    }

    /// The editor, filled in with what was read, for the person to check.
    private func open(_ result: VisaScanner.Reading) {
        var document = Self.blank(result.isPassport ? .passport : .visa)
        if let country = result.country { document.country = country }
        if let category = result.category { document.category = category }
        if let number = result.number { document.number = number }
        if let holder = result.holder { document.holder = holder }
        document.post = result.post
        document.issued = result.issued
        if let expires = result.expires { document.expires = expires }
        if let entries = result.entries { document.entries = entries }
        document.stayDays = result.stayDays
        if document.country == "AU" || document.country == "NZ" { document.kind = .eVisa }
        if result.isPassport, let existing = documents.passport { document.id = existing.id }
        editing = EditorRequest(document: document, reading: result)
    }

    static func blank(_ kind: TravelDocument.Kind) -> TravelDocument {
        let country = kind == .passport ? (Nationality.code ?? Locale.current.region?.identifier ?? "CN") : "US"
        let years = kind == .passport ? 10 : 1
        return TravelDocument(kind: kind, country: country,
                              expires: Calendar.current.date(byAdding: .year, value: years, to: .now) ?? .now)
    }
}

struct EditorRequest: Identifiable {
    let id = UUID()
    var document: TravelDocument
    var reading: VisaScanner.Reading?
}

// MARK: - Summary

/// One quiet line over the cards: how many are good, and the next to run out.
private struct WalletSummary: View {
    let documents: [TravelDocument]

    var body: some View {
        let valid = documents.filter { !$0.isExpired && $0.kind != .passport }
        let next = documents.filter { !$0.isExpired }.min { $0.expires < $1.expires }
        VStack(alignment: .leading, spacing: 4) {
            Text(String(localized: "\(valid.count) 张有效签证", bundle: .appLanguage))
                .font(.title2.weight(.bold))
                .contentTransition(.numericText())
            if let next {
                HStack(spacing: 6) {
                    Circle().fill(next.isExpiringSoon ? Color.orange : .green).frame(width: 7, height: 7)
                    Text(String(localized: "\(next.kind == .passport ? String(localized: "护照", bundle: .appLanguage) : next.countryName) \(next.daysLeft()) 天后到期", bundle: .appLanguage))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 4)
        .padding(.top, 4)
    }
}

private struct WalletEmptyState: View {
    let scan: () -> Void
    let choosePhoto: () -> Void
    let addByHand: () -> Void
    @State private var fanned = false

    private static let samples: [TravelDocument] = [
        TravelDocument(kind: .visa, country: "JP", category: String(localized: "短期滞在", bundle: .appLanguage),
                       expires: .now.addingTimeInterval(86_400 * 400), entries: .multiple, stayDays: 30),
        TravelDocument(kind: .visa, country: TravelDocument.schengen, category: "C",
                       expires: .now.addingTimeInterval(86_400 * 700), entries: .multiple, stayDays: 90),
        TravelDocument(kind: .visa, country: "US", category: "B1/B2", expires: .now.addingTimeInterval(86_400 * 2_900)),
    ]

    var body: some View {
        VStack(spacing: 22) {
            ZStack {
                ForEach(Array(Self.samples.enumerated()), id: \.offset) { index, sample in
                    VisaCard(document: sample)
                        .frame(width: 250)
                        .shadow(color: .black.opacity(0.14), radius: 12, y: 8)
                        .rotationEffect(.degrees(fanned ? Double(index - 1) * 7 : 0), anchor: .bottom)
                        .offset(x: fanned ? CGFloat(index - 1) * 26 : 0, y: fanned ? CGFloat(abs(index - 1)) * 10 : 0)
                }
            }
            .frame(height: 230)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .onAppear { withAnimation(.spring(response: 0.8, dampingFraction: 0.7).delay(0.2)) { fanned = true } }

            VStack(spacing: 8) {
                Text("把签证放进来").font(.title2.weight(.bold))
                Text("用相机对准护照上的签证页，就能自动读出国家、类型和有效期。哪张快到期、还能停留多久，一眼就知道，到期前也会提醒你。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 8)

            VStack(spacing: 10) {
                Button(action: scan) {
                    Label("扫描签证", systemImage: "viewfinder")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
                HStack(spacing: 10) {
                    Button(action: choosePhoto) {
                        Label("从照片识别", systemImage: "photo.on.rectangle").frame(maxWidth: .infinity)
                    }
                    Button(action: addByHand) {
                        Label("手动填写", systemImage: "square.and.pencil").frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.glass)
                .controlSize(.large)
            }
        }
        .padding(.top, 24)
    }
}

// MARK: - Schengen

/// The 90 days in any 180, counted from where the person has actually been.
struct SchengenCard: View {
    let visa: TravelDocument
    /// Inside another sheet: no background of its own.
    var plain = false
    private var summaries = PlaceSummaries.shared

    init(visa: TravelDocument, plain: Bool = false) {
        self.visa = visa
        self.plain = plain
    }

    var body: some View {
        let allowance = Schengen.allowance(stays: summaries.stays.map { ($0.countryCode, $0.arrival, $0.departure) })
        let limit = min(visa.stayDays ?? 90, 90)
        let remaining = max(0, limit - allowance.used)
        HStack(spacing: 18) {
            ZStack {
                Circle().stroke(.quaternary, lineWidth: 9)
                Circle()
                    .trim(from: 0, to: CGFloat(min(allowance.used, limit)) / CGFloat(max(limit, 1)))
                    .stroke(remaining < 15 ? Color.orange.gradient : Color.blue.gradient, style: StrokeStyle(lineWidth: 9, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 0) {
                    Text("\(remaining)").font(.title2.weight(.bold)).monospacedDigit()
                    Text("天可用").font(.caption2).foregroundStyle(.secondary)
                }
            }
            .frame(width: 86, height: 86)
            VStack(alignment: .leading, spacing: 5) {
                Label("申根 90/180 天", systemImage: "eurosign.circle.fill")
                    .font(.headline)
                    .foregroundStyle(.blue)
                Text("最近 180 天里，你在申根区待了 \(allowance.used) 天，还能再待 \(remaining) 天。")
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
                if allowance.used > 0, let freed = allowance.nextFreed {
                    Text("\(freed.formatted(.dateTime.month().day().locale(appLocale))) 起会陆续多出可用天数。")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .padding(plain ? 0 : 18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(plain ? AnyShapeStyle(.clear) : AnyShapeStyle(.background.secondary), in: .rect(cornerRadius: 24, style: .continuous))
    }
}

// MARK: - Detail

struct VisaDetails: View {
    let document: TravelDocument
    let onEdit: () -> Void
    let onDelete: () -> Void
    private var summaries = PlaceSummaries.shared
    @State private var confirmingDelete = false
    @State private var showsNumber = false
    @State private var appeared = false

    init(document: TravelDocument, onEdit: @escaping () -> Void, onDelete: @escaping () -> Void) {
        self.document = document
        self.onEdit = onEdit
        self.onDelete = onDelete
    }

    private var tint: Color { document.isExpired ? .red : document.isExpiringSoon ? .orange : .green }

    /// Laid out like the back of a pass in Wallet: one sheet, its parts divided by hairlines.
    var body: some View {
        VStack(spacing: 18) {
            VStack(alignment: .leading, spacing: 0) {
                header.padding(18)
                if document.kind == .passport {
                    hairline
                    passportRule.padding(18)
                }
                if document.isSchengen, !document.isExpired {
                    hairline
                    SchengenCard(visa: document, plain: true).padding(18)
                }
                if document.kind != .passport {
                    hairline
                    usage.padding(18)
                }
                hairline
                fields.padding(18)
            }
            .background(.background.secondary, in: .rect(cornerRadius: 24, style: .continuous))
            HStack(spacing: 12) {
                Button("编辑", systemImage: "square.and.pencil", action: onEdit)
                    .frame(maxWidth: .infinity)
                Button("删除", systemImage: "trash", role: .destructive) { confirmingDelete = true }
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glass)
            .controlSize(.large)
        }
        .onAppear { withAnimation(.spring(response: 1.1, dampingFraction: 0.85).delay(0.25)) { appeared = true } }
        .confirmationDialog("删除这张\(document.kind == .passport ? String(localized: "护照", bundle: .appLanguage) : String(localized: "签证", bundle: .appLanguage))？",
                            isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("删除", role: .destructive, action: onDelete)
        }
    }

    private var hairline: some View { Rectangle().fill(.separator).frame(height: 0.5).padding(.leading, 18) }

    /// How long is left, as a ring that empties toward the expiry.
    private var header: some View {
        let days = document.daysLeft()
        let start = document.issued ?? document.added
        let total = max(document.expires.timeIntervalSince(start), 1)
        let remaining = min(max(document.expires.timeIntervalSince(.now) / total, 0), 1)
        return HStack(spacing: 18) {
            ZStack {
                Circle().stroke(tint.opacity(0.14), lineWidth: 8)
                Circle()
                    .trim(from: 0, to: appeared ? remaining : 0)
                    .stroke(tint.gradient, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: -2) {
                    Text(days >= 0 ? days.formatted() : (-days).formatted())
                        .font(.system(size: days >= 1_000 ? 22 : 26, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                    Text(days >= 0 ? "天" : "天前").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                }
            }
            .frame(width: 92, height: 92)
            VStack(alignment: .leading, spacing: 6) {
                Text(document.isExpired ? "已过期" : document.isExpiringSoon ? "即将到期" : "有效")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(tint)
                    .padding(.horizontal, 9).padding(.vertical, 4)
                    .background(tint.opacity(0.13), in: .capsule)
                Text(String(localized: "\(document.expires.formatted(Date.FormatStyle(date: .long, time: .omitted, locale: appLocale))) 到期", bundle: .appLanguage))
                    .font(.headline)
                if let issued = document.issued {
                    Text(String(localized: "签发于 \(issued.formatted(Date.FormatStyle(date: .long, time: .omitted, locale: appLocale)))", bundle: .appLanguage))
                        .font(.subheadline).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private var passportRule: some View {
        let short = document.daysLeft() < 183
        return Label {
            Text(short ? "护照有效期已不足 6 个月。很多国家要求入境时护照还剩 6 个月以上，出发前记得先换发。"
                       : "很多国家要求入境时护照还剩 6 个月以上。到期前 6 个月，这里会提醒你。")
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: short ? "exclamationmark.triangle.fill" : "info.circle.fill")
                .foregroundStyle(short ? .orange : .blue)
        }
    }

    /// Entries made with it so far, from the places recorded while it was valid.
    private var usage: some View {
        let start = document.issued ?? .distantPast
        let covered = document.coveredCountries
        let stays = summaries.stays
            .filter { stay in stay.countryCode.map(covered.contains) ?? false && stay.arrival >= start && stay.arrival <= document.expires }
            .sorted { $0.arrival < $1.arrival }
        let calendar = Calendar.current
        var entries = 0
        var lastDay: Date?
        var days = Set<Date>()
        for stay in stays {
            let day = calendar.startOfDay(for: stay.arrival)
            if let last = lastDay, day.timeIntervalSince(last) <= 2 * 86_400 {} else { entries += 1 }
            lastDay = calendar.startOfDay(for: stay.departure ?? .now)
            days.insert(day)
        }
        return HStack(spacing: 14) {
            Image(systemName: "airplane.arrival")
                .font(.body.weight(.semibold))
                .foregroundStyle(.indigo)
                .frame(width: 38, height: 38)
                .background(Color.indigo.opacity(0.12), in: .circle)
            VStack(alignment: .leading, spacing: 2) {
                Text("用这张签证去过").font(.caption).foregroundStyle(.secondary)
                Text(entries == 0 ? String(localized: "还没有用过", bundle: .appLanguage)
                                  : String(localized: "\(entries) 次入境 · 共 \(days.count) 天", bundle: .appLanguage))
                    .font(.headline)
                if document.entries != .multiple, entries > 0 {
                    let allowed = document.entries == .single ? 1 : 2
                    Text(entries >= allowed ? String(localized: "入境次数已经用完", bundle: .appLanguage)
                                            : String(localized: "还能再入境 \(allowed - entries) 次", bundle: .appLanguage))
                        .font(.caption).foregroundStyle(entries >= allowed ? .orange : .secondary)
                }
            }
            Spacer(minLength: 0)
        }
    }

    /// The details two to a row, label over value, as on the back of a pass.
    private var fields: some View {
        var items: [(LocalizedStringKey, String)] = []
        if document.kind != .passport {
            items.append(("类型", document.category.isEmpty ? "—" : document.category))
            items.append(("入境次数", document.entries.title))
            if let stay = document.stayDays { items.append(("每次停留", String(localized: "\(stay) 天", bundle: .appLanguage))) }
        }
        if let post = document.post, !post.isEmpty { items.append(("签发地", post.capitalized)) }
        if !document.holder.isEmpty { items.append(("持有人", document.holder)) }
        if let issued = document.issued { items.append(("签发日期", issued.formatted(Date.FormatStyle(date: .abbreviated, time: .omitted, locale: appLocale)))) }
        items.append(("到期日期", document.expires.formatted(Date.FormatStyle(date: .abbreviated, time: .omitted, locale: appLocale))))
        return VStack(alignment: .leading, spacing: 16) {
            LazyVGrid(columns: [GridItem(.flexible(), alignment: .topLeading), GridItem(.flexible(), alignment: .topLeading)],
                      alignment: .leading, spacing: 16) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    field(item.0) { Text(item.1) }
                }
            }
            if !document.number.isEmpty {
                field("号码") {
                    HStack(spacing: 8) {
                        Text(showsNumber ? document.number : String(repeating: "•", count: max(4, document.number.count - 3)) + document.number.suffix(3))
                            .monospaced()
                            .contentTransition(.interpolate)
                        Button(showsNumber ? "隐藏" : "显示", systemImage: showsNumber ? "eye.slash" : "eye") {
                            withAnimation(.snappy) { showsNumber.toggle() }
                        }
                        .labelStyle(.iconOnly)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    }
                }
            }
            if !document.notes.isEmpty { field("备注") { Text(document.notes) } }
        }
    }

    private func field<Value: View>(_ label: LocalizedStringKey, @ViewBuilder value: () -> Value) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            value().font(.body.weight(.medium)).lineLimit(2)
        }
    }
}

extension TravelDocument.Entries {
    var title: String {
        switch self {
        case .single: String(localized: "一次", bundle: .appLanguage)
        case .double: String(localized: "两次", bundle: .appLanguage)
        case .multiple: String(localized: "多次", bundle: .appLanguage)
        }
    }
}

extension TravelDocument.Kind {
    var title: LocalizedStringKey {
        switch self {
        case .passport: "护照"
        case .visa: "签证"
        case .eVisa: "电子签"
        }
    }
}

// MARK: - Editor

struct VisaEditor: View {
    @State var document: TravelDocument
    let reading: VisaScanner.Reading?
    @State private var hasIssued: Bool
    @State private var hasStay: Bool
    @Environment(\.dismiss) private var dismiss

    init(document: TravelDocument, reading: VisaScanner.Reading?) {
        _document = State(initialValue: document)
        self.reading = reading
        _hasIssued = State(initialValue: document.issued != nil)
        _hasStay = State(initialValue: document.stayDays != nil)
    }

    private var countries: [(code: String, name: String)] {
        [(TravelDocument.schengen, String(localized: "申根区", bundle: .appLanguage))] + Nationality.all
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VisaCard(document: preview)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                        .animation(.smooth, value: preview)
                }
                if let reading { readingNote(reading) }
                Section {
                    Picker("证件", selection: $document.kind) {
                        ForEach(TravelDocument.Kind.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }
                Section {
                    Picker(document.kind == .passport ? "签发国" : "国家或地区", selection: $document.country) {
                        ForEach(countries, id: \.code) { country in
                            Text(verbatim: "\(country.code == TravelDocument.schengen ? "🇪🇺" : String.flag(for: country.code)) \(country.name)")
                                .tag(country.code)
                        }
                    }
                    .pickerStyle(.navigationLink)
                    if document.kind != .passport {
                        TextField("类型，比如 B1/B2、C、旅游", text: $document.category)
                        Picker("入境次数", selection: $document.entries) {
                            ForEach(TravelDocument.Entries.allCases, id: \.self) { Text($0.title).tag($0) }
                        }
                        Toggle("限制每次停留天数", isOn: $hasStay.animation())
                        if hasStay {
                            Stepper(value: Binding(get: { document.stayDays ?? 90 }, set: { document.stayDays = $0 }), in: 1...365) {
                                Text("每次停留 \(document.stayDays ?? 90) 天").monospacedDigit()
                            }
                        }
                    }
                }
                Section {
                    DatePicker("到期日期", selection: $document.expires, displayedComponents: .date)
                    Toggle("填写签发日期", isOn: $hasIssued.animation())
                    if hasIssued {
                        DatePicker("签发日期", selection: Binding(get: { document.issued ?? .now }, set: { document.issued = $0 }),
                                   in: ...document.expires, displayedComponents: .date)
                    }
                } footer: {
                    Text("到期前 90 天、30 天和 7 天会各提醒你一次。")
                }
                Section("可选") {
                    TextField(document.kind == .passport ? "护照号码" : "签证号码", text: $document.number)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                    TextField("持有人姓名", text: $document.holder)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                    TextField("备注", text: $document.notes, axis: .vertical)
                }
            }
            .navigationTitle(TravelDocuments.shared.all.contains { $0.id == document.id } ? "编辑" : "添加")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消", systemImage: "xmark") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存", systemImage: "checkmark") {
                        var saved = preview
                        saved.category = saved.category.trimmingCharacters(in: .whitespaces)
                        TravelDocuments.shared.save(saved)
                        dismiss()
                    }
                    .buttonStyle(.glassProminent)
                }
            }
        }
        .sensoryFeedback(.success, trigger: TravelDocuments.shared.all.count)
    }

    /// What will be saved: the switches decide whether the optional dates count.
    private var preview: TravelDocument {
        var copy = document
        if !hasIssued { copy.issued = nil }
        if !hasStay || copy.kind == .passport { copy.stayDays = nil }
        if copy.kind == .passport, copy.country == TravelDocument.schengen { copy.country = Nationality.code ?? "CN" }
        return copy
    }

    private func readingNote(_ reading: VisaScanner.Reading) -> some View {
        Section {
            Label {
                VStack(alignment: .leading, spacing: 3) {
                    Text(reading.expires == nil ? "没能读出到期日期，请手动填写。" : "已从照片读出，请核对一遍。")
                        .font(.subheadline.weight(.semibold))
                    if reading.verified {
                        Text("到期日期来自签证底部的机读码，已通过校验。").font(.caption).foregroundStyle(.secondary)
                    } else {
                        Text("照片越清晰、越平整，识别越准。").font(.caption).foregroundStyle(.secondary)
                    }
                }
            } icon: {
                Image(systemName: reading.verified ? "checkmark.seal.fill" : "text.viewfinder")
                    .foregroundStyle(reading.verified ? .green : .blue)
            }
        }
    }
}

// MARK: - Shelf

/// The way into the wallet from the passport: the cards fanned, and what needs attention.
struct VisaShelf: View {
    private var documents = TravelDocuments.shared

    var body: some View {
        let sorted = documents.sorted
        NavigationLink(value: VisaWalletRoute()) {
            HStack(spacing: 16) {
                ZStack {
                    if sorted.isEmpty {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(.tertiary, style: StrokeStyle(lineWidth: 1.2, dash: [4, 3]))
                            .frame(width: 84, height: 54)
                            .overlay(Image(systemName: "plus").font(.title3.weight(.semibold)).foregroundStyle(.secondary))
                    } else {
                        ForEach(Array(sorted.prefix(3).enumerated().reversed()), id: \.element.id) { index, document in
                            VisaCard(document: document)
                                .frame(width: 84)
                                .shadow(color: .black.opacity(0.14), radius: 4, y: 2)
                                .rotationEffect(.degrees(Double(index) * -6), anchor: .bottomLeading)
                                .offset(x: CGFloat(index) * 4, y: CGFloat(index) * -3)
                        }
                    }
                }
                .frame(width: 96, height: 70)
                VStack(alignment: .leading, spacing: 4) {
                    Text("签证夹").font(.headline)
                    Text(subtitle(sorted)).font(.subheadline).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
            }
            .padding(14)
            .background(.background.secondary, in: .rect(cornerRadius: 24, style: .continuous))
        }
        .buttonStyle(PressableStyle())
    }

    private func subtitle(_ sorted: [TravelDocument]) -> String {
        guard !sorted.isEmpty else { return String(localized: "拍下护照上的签证，记住每张什么时候到期", bundle: .appLanguage) }
        if let soon = sorted.first(where: \.isExpiringSoon) {
            return String(localized: "\(soon.kind == .passport ? String(localized: "护照", bundle: .appLanguage) : soon.countryName) 还剩 \(soon.daysLeft()) 天到期", bundle: .appLanguage)
        }
        let valid = sorted.filter { !$0.isExpired && $0.kind != .passport }.count
        return String(localized: "\(valid) 张有效签证", bundle: .appLanguage)
    }
}
