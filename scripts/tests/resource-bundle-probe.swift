import Foundation

@main
struct ResourceBundleProbe {
    static func main() throws {
        let expected = Bundle.main.bundleURL
            .appendingPathComponent("Contents/Resources/swift-transformers_Hub.bundle")
            .resolvingSymlinksInPath().standardizedFileURL
        let resolved = Bundle.module.bundleURL.resolvingSymlinksInPath().standardizedFileURL
        guard resolved == expected else {
            fputs("Resource accessor used a build-path fallback: \(resolved.path)\n", stderr)
            exit(1)
        }
        for name in ["gpt2_tokenizer_config", "t5_tokenizer_config"] {
            guard let url = Bundle.module.url(forResource: name, withExtension: "json") else {
                fputs("Missing tokenizer resource: \(name)\n", stderr)
                exit(1)
            }
            _ = try JSONSerialization.jsonObject(with: Data(contentsOf: url))
        }
        print("Generated Hub accessor resolved packaged resources: \(resolved.path)")
    }
}
