import SwiftUI

/// "那天的天空": when the sun rose and set over this place that day, the moon that night, and
/// a line when the visit took in a sunrise or a sunset.
struct SkySection: View {
    let stay: Stay
    @Environment(\.colorScheme) private var colorScheme
    @State private var weather: PastWeather.Day?
    @State private var attribution: (light: URL, dark: URL, legal: URL)?

    var body: some View {
        let sun = Sky.sun(on: stay.arrival, at: stay.coordinate)
        let end = stay.departure ?? Date()
        let moon = Sky.moon(at: Calendar.current.date(bySettingHour: 22, minute: 0, second: 0, of: stay.arrival) ?? stay.arrival)
        Section {
            if let weather {
                LabeledContent {
                    Text("\(weather.condition) · \(temperature(weather.low)) – \(temperature(weather.high))").monospacedDigit()
                } label: {
                    Label("天气", systemImage: weather.symbol).symbolRenderingMode(.multicolor)
                }
            }
            if let set = sun.set, stay.arrival <= set, end >= set {
                moment(String(localized: "日落 \(time(set)) 时，你正在这里", bundle: .appLanguage), symbol: "sunset.fill", tint: .orange)
            } else if let rise = sun.rise, stay.arrival <= rise, end >= rise {
                moment(String(localized: "日出 \(time(rise)) 时，你已经在这里", bundle: .appLanguage), symbol: "sunrise.fill", tint: .yellow)
            }
            if let rise = sun.rise, let set = sun.set {
                LabeledContent {
                    Text("\(time(rise)) – \(time(set))").monospacedDigit()
                } label: {
                    Label("日出 – 日落", systemImage: "sun.horizon.fill").symbolRenderingMode(.multicolor)
                }
            }
            LabeledContent {
                Text("\(moon.phase.title) · \(moon.illumination.formatted(.percent.precision(.fractionLength(0)).locale(appLocale)))")
            } label: {
                Label("那晚的月亮", systemImage: moon.phase.symbol)
            }
        } header: {
            Text("那天的天空")
        } footer: {
            if weather != nil, let attribution {
                // Apple Weather's mark and data sources, as WeatherKit asks.
                HStack(spacing: 6) {
                    AsyncImage(url: colorScheme == .dark ? attribution.dark : attribution.light) { image in
                        image.resizable().scaledToFit()
                    } placeholder: { EmptyView() }
                    .frame(height: 11)
                    Link("数据来源", destination: attribution.legal).font(.caption2)
                }
            }
        }
        .task(id: stay.persistentModelID) {
            weather = await PastWeather.day(stay.arrival, at: stay.coordinate)
            if weather != nil { attribution = await PastWeather.attribution() }
        }
    }

    private func temperature(_ celsius: Double) -> String {
        Measurement(value: celsius, unit: UnitTemperature.celsius)
            .formatted(.measurement(width: .narrow, usage: .weather, numberFormatStyle: .number.precision(.fractionLength(0))).locale(appLocale))
    }

    private func moment(_ text: String, symbol: String, tint: Color) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .symbolRenderingMode(.multicolor)
                .font(.title3)
                .frame(width: 36, height: 36)
                .background(Circle().fill(tint.opacity(0.15)))
            Text(text).font(.subheadline.weight(.semibold))
        }
    }

    private func time(_ date: Date) -> String { date.formatted(.dateTime.hour().minute().locale(appLocale)) }
}
