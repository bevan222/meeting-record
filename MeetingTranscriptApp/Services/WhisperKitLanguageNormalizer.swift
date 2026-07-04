import Foundation

enum WhisperKitLanguageNormalizer {
    static func normalize(_ language: String) -> String? {
        let trimmed = language.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        return trimmed.split(separator: "-").first.map(String.init)?.lowercased()
    }
}
