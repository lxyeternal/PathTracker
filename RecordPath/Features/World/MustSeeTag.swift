import SwiftUI

/// "★ 此生必去" in gold, for a place that's on one of the lists.
struct MustSeeTag: View {
    var compact = false

    var body: some View {
        Label("此生必去", systemImage: "star.fill")
            .font(compact ? .caption2.weight(.bold) : .caption.weight(.bold))
            .labelStyle(.titleAndIcon)
            .foregroundStyle(Color(red: 0.42, green: 0.27, blue: 0.0))
            .padding(.horizontal, compact ? 6 : 9)
            .padding(.vertical, compact ? 2 : 4)
            .background(Capsule().fill(LinearGradient(colors: [Color(red: 1, green: 0.88, blue: 0.5), Color(red: 0.93, green: 0.7, blue: 0.25)],
                                                      startPoint: .top, endPoint: .bottom)))
            .overlay(Capsule().stroke(.white.opacity(0.6), lineWidth: 0.5))
            .fixedSize()
    }
}

/// Opens a place's own page from 足迹, without the list it usually opens from.
struct MustSeeFromPlaceRoute: Hashable {
    let id: String
}

/// The top of a place's page when it's one worth a lifetime: the cover photograph, its name
/// set large, the tag, and the short story behind it.
struct MustSeePlaceHeader: View {
    let must: MustSeePlace
    let name: String
    @State private var cover: UIImage?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .bottomLeading) {
                // The photograph fills a fixed frame instead of widening the page to its own shape.
                Color.clear
                    .frame(maxWidth: .infinity)
                    .frame(height: 300)
                    .overlay {
                        if let cover {
                            Image(uiImage: cover).resizable().scaledToFill().transition(.opacity)
                        } else {
                            LinearGradient(colors: [Color(red: 0.2, green: 0.17, blue: 0.1), .black], startPoint: .top, endPoint: .bottom)
                        }
                    }
                    .clipped()
                LinearGradient(colors: [.clear, .black.opacity(0.75)], startPoint: .center, endPoint: .bottom)
                VStack(alignment: .leading, spacing: 8) {
                    MustSeeTag()
                    Text(must.localizedName)
                        .font(.system(size: 34, weight: .bold, design: .serif))
                        .foregroundStyle(.white)
                    if name != must.localizedName {
                        Text(name).font(.subheadline).foregroundStyle(.white.opacity(0.8))
                    }
                }
                .padding(20)
            }
            .frame(height: 300)
            if let story = MustSee.story(must.id) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(story.localizedText).font(.body).lineSpacing(4)
                    Label(story.localizedSeason, systemImage: "leaf").font(.footnote).foregroundStyle(.secondary)
                    NavigationLink(value: MustSeeFromPlaceRoute(id: must.id)) {
                        // The list draws the disclosure arrow.
                        Text("看看它的此生必去页面").font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color(red: 0.75, green: 0.52, blue: 0.1))
                    }
                    .padding(.top, 4)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
            }
        }
        .task { cover = await MustSeePhotos.cover(must.id) }
        .animation(.smooth(duration: 0.5), value: cover != nil)
    }
}
