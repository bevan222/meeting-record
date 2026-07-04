enum WhisperKitPrompt {
    static func prompt(for language: String?) -> String? {
        guard language == "zh" else { return nil }
        return "以下是台灣繁體中文會議逐字稿。請使用繁體中文，不要使用簡體中文。"
    }
}
