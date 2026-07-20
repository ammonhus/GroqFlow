import Foundation

// Turns a raw transcript into finished text. Order of operations:
// 1. snippet short-circuit (no LLM call), 2. light sentence-case when smart formatting is off,
// 3. LLM formatting with the full rule set, parsing {"text": ...} with one retry, raw fallback.
public struct FormattingService: Sendable {
    private let api: GroqAPI

    public init(api: GroqAPI) {
        self.api = api
    }

    public func format(raw: String,
                       context: AppContext,
                       preset: StylePreset,
                       dictionary: [DictionaryEntry],
                       snippets: [Snippet],
                       smartFormatting: Bool) async -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "" }

        // 1. Whole-utterance snippet match returns the body verbatim.
        if let body = Self.matchSnippet(utterance: trimmed, snippets: snippets) {
            return body
        }

        // 2. Smart formatting off: minimal local cleanup, no network call.
        if !smartFormatting {
            return Self.basicSentenceCase(trimmed)
        }

        // 3. LLM formatting. On malformed JSON retry once, then fall back to the raw transcript.
        // Output that fails the guardrail (model answered instead of formatting) also falls back to raw.
        let system = FormattingPrompt.system(context: context, preset: preset,
                                             dictionary: dictionary, smartFormatting: smartFormatting)
        let user = FormattingPrompt.userMessage(transcript: trimmed)
        do {
            let response = try await api.chat(system: system, user: user,
                                             model: GroqModels.formatter,
                                             temperature: 0.2, jsonMode: true)
            if let text = Self.extractText(from: response) {
                return Self.accept(raw: trimmed, formatted: text)
            }
            let retry = try await api.chat(system: system, user: user,
                                          model: GroqModels.formatter,
                                          temperature: 0.2, jsonMode: true)
            if let text = Self.extractText(from: retry) {
                return Self.accept(raw: trimmed, formatted: text)
            }
            return trimmed
        } catch {
            Log.groq.error("Formatting failed: \(String(describing: error), privacy: .public)")
            return trimmed
        }
    }

    // MARK: - Guardrail

    private static func accept(raw: String, formatted: String) -> String {
        if plausibleFormatting(raw: raw, formatted: formatted) {
            return formatted
        }
        Log.groq.warning("Formatted output rejected by guardrail; falling back to raw transcript.")
        return raw
    }

    // Formatting rewrites the transcript; it should never grow much or swap out its vocabulary.
    // Rejects output that is far longer than the raw text or shares too few words with it,
    // which is the signature of the model answering the dictation instead of formatting it.
    static func plausibleFormatting(raw: String, formatted: String) -> Bool {
        if Double(formatted.count) > Double(raw.count) * 1.3 + 40 {
            return false
        }
        let formattedWords = normalize(formatted).split(separator: " ")
        let rawWords = Set(normalize(raw).split(separator: " "))

        if formattedWords.count >= 12 {
            let hits = formattedWords.filter { rawWords.contains($0) }.count
            if Double(hits) < 0.5 * Double(formattedWords.count) {
                return false
            }
        } else if formattedWords.count >= 3 {
            // Short outputs: formatting never invents words, so more than one new
            // non-numeric word means the model replied ("Here are a few ideas").
            // Digits stay exempt: spoken numbers legitimately become 500, 1., 2.
            let novel = formattedWords.filter { word in
                !rawWords.contains(word) && word.rangeOfCharacter(from: .decimalDigits) == nil
            }.count
            if novel >= 2, Double(novel) >= 0.3 * Double(formattedWords.count) {
                return false
            }
        }
        return true
    }

    // Command mode: returns nil on failure so the caller can abort the paste.
    public func command(selected: String?, instruction: String) async -> String? {
        let system = FormattingPrompt.commandSystem()
        let user: String
        if let selected, !selected.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            user = "Selected text:\n\(selected)\n\nInstruction:\n\(instruction)"
        } else {
            user = "Instruction:\n\(instruction)"
        }
        do {
            let response = try await api.chat(system: system, user: user,
                                             model: GroqModels.formatter,
                                             temperature: 0.2, jsonMode: true)
            if let text = Self.extractText(from: response) {
                return text
            }
            let retry = try await api.chat(system: system, user: user,
                                          model: GroqModels.formatter,
                                          temperature: 0.2, jsonMode: true)
            return Self.extractText(from: retry)
        } catch {
            Log.groq.error("Command failed: \(String(describing: error), privacy: .public)")
            return nil
        }
    }

    // MARK: - Snippet matching

    // Exact normalized match wins; otherwise a near match (edit distance <= 1) on longer triggers.
    static func matchSnippet(utterance: String, snippets: [Snippet]) -> String? {
        let normUtter = normalize(utterance)
        if normUtter.isEmpty { return nil }

        for snippet in snippets {
            let normTrigger = normalize(snippet.trigger)
            if !normTrigger.isEmpty, normTrigger == normUtter {
                return snippet.body
            }
        }
        for snippet in snippets {
            let normTrigger = normalize(snippet.trigger)
            if normTrigger.count >= 5, levenshtein(normUtter, normTrigger) <= 1 {
                return snippet.body
            }
        }
        return nil
    }

    // Lowercase, drop punctuation, collapse whitespace.
    static func normalize(_ s: String) -> String {
        let lowered = s.lowercased()
        var chars: [Character] = []
        for scalar in lowered.unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar) {
                chars.append(Character(scalar))
            } else {
                chars.append(" ")
            }
        }
        return String(chars).split(separator: " ").joined(separator: " ")
    }

    static func levenshtein(_ a: String, _ b: String) -> Int {
        let ac = Array(a), bc = Array(b)
        let n = ac.count, m = bc.count
        if n == 0 { return m }
        if m == 0 { return n }
        var prev = Array(0...m)
        var curr = [Int](repeating: 0, count: m + 1)
        for i in 1...n {
            curr[0] = i
            for j in 1...m {
                let cost = ac[i - 1] == bc[j - 1] ? 0 : 1
                curr[j] = min(prev[j] + 1, curr[j - 1] + 1, prev[j - 1] + cost)
            }
            swap(&prev, &curr)
        }
        return prev[m]
    }

    // MARK: - JSON extraction

    // Pulls the "text" value out of an LLM response: plain JSON, fenced JSON, or JSON embedded in prose.
    static func extractText(from response: String) -> String? {
        let trimmed = response.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return nil }

        if let text = parseTextJSON(trimmed) {
            return text
        }
        let unfenced = stripCodeFence(trimmed)
        if unfenced != trimmed, let text = parseTextJSON(unfenced) {
            return text
        }
        if let start = trimmed.firstIndex(of: "{"),
           let end = trimmed.lastIndex(of: "}"),
           start < end {
            let candidate = String(trimmed[start...end])
            if let text = parseTextJSON(candidate) {
                return text
            }
        }
        return nil
    }

    static func parseTextJSON(_ s: String) -> String? {
        guard let data = s.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return object["text"] as? String
    }

    static func stripCodeFence(_ s: String) -> String {
        var result = s
        if result.hasPrefix("```") {
            if let firstNewline = result.firstIndex(of: "\n") {
                result = String(result[result.index(after: firstNewline)...])
            }
            if let fence = result.range(of: "```", options: .backwards) {
                result = String(result[..<fence.lowerBound])
            }
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Local fallback

    static func basicSentenceCase(_ s: String) -> String {
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmed.first else { return trimmed }
        return String(first).uppercased() + trimmed.dropFirst()
    }
}
