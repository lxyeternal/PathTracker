import Photos
import UIKit
import Vision

/// Picks the photos worth showing. Taking the middle photo near a place found lecture slides
/// and whiteboards as often as views, so each candidate is looked at on the phone: Vision scores
/// how good a picture it is and flags "utility" shots (documents, slides, receipts, screens),
/// which are left out unless there's nothing else.
enum PhotoCurator {
    private struct Verdict {
        let score: Float
        let isUtility: Bool
    }

    nonisolated(unsafe) private static var verdicts: [String: Verdict] = [:]
    private static let lock = NSLock()

    /// The best first. At most `limit` photos are looked at, spread evenly over the set, with
    /// favourites always among them.
    static func rank(_ assets: [PHAsset], limit: Int = 30) async -> [PHAsset] {
        let usable = assets.filter {
            $0.mediaType == .image && !$0.mediaSubtypes.contains(.photoScreenshot) && $0.pixelWidth * $0.pixelHeight >= 600_000
        }
        guard !usable.isEmpty else { return [] }
        let favorites = usable.filter(\.isFavorite)
        let step = max(1, usable.count / max(1, limit - min(favorites.count, limit / 2)))
        var seen = Set<String>()
        let candidates = (favorites.prefix(limit / 2) + stride(from: 0, to: usable.count, by: step).map { usable[$0] })
            .filter { seen.insert($0.localIdentifier).inserted }
            .prefix(limit)

        var scored: [(asset: PHAsset, score: Float, utility: Bool)] = []
        for asset in candidates {
            let verdict = await judge(asset)
            var score = verdict.score
            if asset.isFavorite { score += 0.35 }
            // Landscape pictures suit a card or a page better than a tall crop of one.
            if asset.pixelWidth >= asset.pixelHeight { score += 0.05 }
            scored.append((asset, score, verdict.isUtility))
        }
        let keep = scored.filter { !$0.utility }
        return (keep.isEmpty ? scored : keep).sorted { $0.score > $1.score }.map(\.asset)
    }

    private static func judge(_ asset: PHAsset) async -> Verdict {
        if let known = lock.withLock({ verdicts[asset.localIdentifier] }) { return known }
        var verdict = Verdict(score: 0, isUtility: false)
        if let image = await AssetLoader.image(for: asset, size: CGSize(width: 512, height: 512), exact: false),
           let cgImage = image.cgImage {
            let aesthetics = try? await CalculateImageAestheticsScoresRequest().perform(on: cgImage)
            let text = await isMostlyText(cgImage)
            verdict = Verdict(score: aesthetics?.overallScore ?? 0, isUtility: (aesthetics?.isUtility ?? false) || text)
        }
        lock.withLock { verdicts[asset.localIdentifier] = verdict }
        return verdict
    }

    /// Slides, pages and whiteboards: lots of lines of text over much of the picture. A second
    /// opinion, and the only one where the aesthetics model isn't available.
    private static func isMostlyText(_ image: CGImage) async -> Bool {
        var request = RecognizeTextRequest()
        request.recognitionLevel = .fast
        guard let lines = try? await request.perform(on: image) else { return false }
        let area = lines.reduce(0.0) { $0 + Double($1.boundingBox.width * $1.boundingBox.height) }
        return lines.count >= 6 || area > 0.12
    }
}
