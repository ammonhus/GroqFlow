import XCTest
@testable import GroqFlowKit

final class GroqTests: XCTestCase {

    // MARK: - Formatting system prompt

    func testSystemPromptRequestsJSONObject() {
        let sys = FormattingPrompt.system(context: .empty, preset: .formal,
                                          dictionary: [], smartFormatting: true)
        XCTAssertTrue(sys.contains("{\"text\""))
    }

    func testSystemPromptIncludesDictionaryWords() {
        let dict = [DictionaryEntry(text: "Groq"), DictionaryEntry(text: "Xcode")]
        let sys = FormattingPrompt.system(context: .empty, preset: .formal,
                                          dictionary: dict, smartFormatting: true)
        XCTAssertTrue(sys.contains("Groq"))
        XCTAssertTrue(sys.contains("Xcode"))
    }

    func testSystemPromptDictionaryStarredFirst() {
        let dict = [
            DictionaryEntry(text: "alpha", starred: false),
            DictionaryEntry(text: "beta", starred: true),
        ]
        let sys = FormattingPrompt.system(context: .empty, preset: .formal,
                                          dictionary: dict, smartFormatting: true)
        let betaRange = sys.range(of: "beta")
        let alphaRange = sys.range(of: "alpha")
        XCTAssertNotNil(betaRange)
        XCTAssertNotNil(alphaRange)
        XCTAssertLessThan(betaRange!.lowerBound, alphaRange!.lowerBound)
    }

    func testSystemPromptDictionaryMisspellingPair() {
        let dict = [DictionaryEntry(text: "Kubernetes", misspelling: "kubernetis")]
        let sys = FormattingPrompt.system(context: .empty, preset: .formal,
                                          dictionary: dict, smartFormatting: true)
        XCTAssertTrue(sys.contains("kubernetis -> Kubernetes"))
    }

    func testSystemPromptCodeCategoryLines() {
        let ctx = AppContext(bundleID: "com.apple.dt.Xcode", appName: "Xcode",
                             precedingText: nil, category: .code)
        let sys = FormattingPrompt.system(context: ctx, preset: .casual,
                                          dictionary: [], smartFormatting: true)
        XCTAssertTrue(sys.lowercased().contains("coding context"))
        XCTAssertTrue(sys.lowercased().contains("do not auto-capitalize"))
    }

    func testSystemPromptNonCodeOmitsCodeLines() {
        let sys = FormattingPrompt.system(context: .empty, preset: .casual,
                                          dictionary: [], smartFormatting: true)
        XCTAssertFalse(sys.lowercased().contains("do not auto-capitalize"))
    }

    func testSystemPromptPresetLines() {
        let veryCasual = FormattingPrompt.system(context: .empty, preset: .veryCasual,
                                                 dictionary: [], smartFormatting: true)
        XCTAssertTrue(veryCasual.contains("lowercase throughout"))

        let excited = FormattingPrompt.system(context: .empty, preset: .excited,
                                              dictionary: [], smartFormatting: true)
        XCTAssertTrue(excited.lowercased().contains("exclamation"))

        let formal = FormattingPrompt.system(context: .empty, preset: .formal,
                                             dictionary: [], smartFormatting: true)
        XCTAssertTrue(formal.lowercased().contains("trailing period"))
    }

    func testPresetDescriptionDistinct() {
        XCTAssertNotEqual(FormattingPrompt.presetDescription(.casual),
                          FormattingPrompt.presetDescription(.veryCasual))
        XCTAssertTrue(FormattingPrompt.presetDescription(.veryCasual).contains("Very Casual"))
    }

    func testSystemPromptSmartFormattingOffIsMinimal() {
        let sys = FormattingPrompt.system(context: .empty, preset: .formal,
                                          dictionary: [], smartFormatting: false)
        XCTAssertTrue(sys.lowercased().contains("minimal"))
        XCTAssertFalse(sys.contains("scratch that"))
    }

    func testSystemPromptSmartFormattingOnHasBacktrackTriggers() {
        let sys = FormattingPrompt.system(context: .empty, preset: .formal,
                                          dictionary: [], smartFormatting: true)
        XCTAssertTrue(sys.contains("scratch that"))
        XCTAssertTrue(sys.contains("I mean"))
    }

    func testSystemPromptNeverEmDash() {
        let sys = FormattingPrompt.system(context: .empty, preset: .formal,
                                          dictionary: [], smartFormatting: true)
        XCTAssertTrue(sys.lowercased().contains("never insert em dashes"))
    }

    func testSystemPromptPrecedingTextGuidance() {
        let ctx = AppContext(bundleID: nil, appName: nil,
                             precedingText: "the quick brown fox", category: .other)
        let sys = FormattingPrompt.system(context: ctx, preset: .formal,
                                          dictionary: [], smartFormatting: true)
        XCTAssertTrue(sys.contains("the quick brown fox"))
        XCTAssertTrue(sys.lowercased().contains("lowercase"))
    }

    // MARK: - Command prompt

    func testCommandSystemPromptShape() {
        let sys = FormattingPrompt.commandSystem()
        XCTAssertTrue(sys.contains("{\"text\""))
        XCTAssertTrue(sys.lowercased().contains("replacement"))
    }

    // MARK: - STT prompt

    func testSTTPromptContainsWords() {
        let dict = [DictionaryEntry(text: "Kubernetes"), DictionaryEntry(text: "Groq")]
        let prompt = FormattingPrompt.sttPrompt(dictionary: dict, context: .empty)
        XCTAssertTrue(prompt.contains("Kubernetes"))
        XCTAssertTrue(prompt.contains("Groq"))
    }

    func testSTTPromptStarredFirst() {
        let dict = [
            DictionaryEntry(text: "alpha", starred: false),
            DictionaryEntry(text: "beta", starred: true),
        ]
        let prompt = FormattingPrompt.sttPrompt(dictionary: dict, context: .empty)
        let betaRange = prompt.range(of: "beta")
        let alphaRange = prompt.range(of: "alpha")
        XCTAssertNotNil(betaRange)
        XCTAssertNotNil(alphaRange)
        XCTAssertLessThan(betaRange!.lowerBound, alphaRange!.lowerBound)
    }

    func testSTTPromptTruncatesTo900Chars() {
        let dict = (0..<500).map { DictionaryEntry(text: "vocabularyword\($0)") }
        let prompt = FormattingPrompt.sttPrompt(dictionary: dict, context: .empty)
        XCTAssertFalse(prompt.isEmpty)
        XCTAssertLessThanOrEqual(prompt.count, 900)
    }

    func testSTTPromptWithPrecedingContextStaysUnderCap() {
        let dict = (0..<500).map { DictionaryEntry(text: "vocabularyword\($0)") }
        let ctx = AppContext(bundleID: nil, appName: nil,
                             precedingText: String(repeating: "context ", count: 400),
                             category: .other)
        let prompt = FormattingPrompt.sttPrompt(dictionary: dict, context: ctx)
        XCTAssertLessThanOrEqual(prompt.count, 900)
    }

    func testSTTPromptEmptyDictionary() {
        let prompt = FormattingPrompt.sttPrompt(dictionary: [], context: .empty)
        XCTAssertEqual(prompt, "")
    }

    // MARK: - Snippet matching

    func testSnippetExactMatch() {
        let snips = [Snippet(trigger: "my address", body: "123 Main St")]
        XCTAssertEqual(FormattingService.matchSnippet(utterance: "my address", snippets: snips),
                       "123 Main St")
    }

    func testSnippetCaseInsensitive() {
        let snips = [Snippet(trigger: "My Address", body: "123 Main St")]
        XCTAssertEqual(FormattingService.matchSnippet(utterance: "my address", snippets: snips),
                       "123 Main St")
    }

    func testSnippetPunctuationInsensitive() {
        let snips = [Snippet(trigger: "my address", body: "123 Main St")]
        XCTAssertEqual(FormattingService.matchSnippet(utterance: "MY, ADDRESS!", snippets: snips),
                       "123 Main St")
    }

    func testSnippetNoMatch() {
        let snips = [Snippet(trigger: "my address", body: "123 Main St")]
        XCTAssertNil(FormattingService.matchSnippet(utterance: "something else entirely",
                                                    snippets: snips))
    }

    func testSnippetNearMatchOnLongerTrigger() {
        let snips = [Snippet(trigger: "signature", body: "Best, Ammon")]
        XCTAssertEqual(FormattingService.matchSnippet(utterance: "signatur", snippets: snips),
                       "Best, Ammon")
    }

    func testSnippetExactWinsOverFuzzy() {
        let snips = [
            Snippet(trigger: "hello", body: "FUZZY"),
            Snippet(trigger: "hallo", body: "EXACT"),
        ]
        XCTAssertEqual(FormattingService.matchSnippet(utterance: "hallo", snippets: snips), "EXACT")
    }

    func testSnippetEmptyUtterance() {
        let snips = [Snippet(trigger: "my address", body: "123 Main St")]
        XCTAssertNil(FormattingService.matchSnippet(utterance: "   ", snippets: snips))
    }

    // MARK: - JSON extraction

    func testExtractPlainJSON() {
        XCTAssertEqual(FormattingService.extractText(from: "{\"text\": \"hello world\"}"),
                       "hello world")
    }

    func testExtractFencedJSON() {
        let fenced = "```json\n{\"text\": \"fenced value\"}\n```"
        XCTAssertEqual(FormattingService.extractText(from: fenced), "fenced value")
    }

    func testExtractFencedNoLanguageTag() {
        let fenced = "```\n{\"text\": \"plain fence\"}\n```"
        XCTAssertEqual(FormattingService.extractText(from: fenced), "plain fence")
    }

    func testExtractJSONEmbeddedInProse() {
        let messy = "Here is your result: {\"text\": \"embedded\"} hope that helps"
        XCTAssertEqual(FormattingService.extractText(from: messy), "embedded")
    }

    func testExtractMalformedReturnsNil() {
        XCTAssertNil(FormattingService.extractText(from: "not json at all"))
        XCTAssertNil(FormattingService.extractText(from: "{\"text\": "))
        XCTAssertNil(FormattingService.extractText(from: ""))
    }

    func testExtractMissingTextKeyReturnsNil() {
        XCTAssertNil(FormattingService.extractText(from: "{\"result\": \"nope\"}"))
    }

    func testExtractPreservesUnicodeAndNewlines() {
        let json = "{\"text\": \"line one\\nline two \\u00e9\"}"
        XCTAssertEqual(FormattingService.extractText(from: json), "line one\nline two \u{00e9}")
    }

    // MARK: - Basic sentence case fallback

    func testBasicSentenceCase() {
        XCTAssertEqual(FormattingService.basicSentenceCase("hello there"), "Hello there")
        XCTAssertEqual(FormattingService.basicSentenceCase("  spaced  "), "Spaced")
        XCTAssertEqual(FormattingService.basicSentenceCase(""), "")
    }

    // MARK: - Model identifiers

    func testModelIdentifiers() {
        XCTAssertEqual(GroqModels.stt, "whisper-large-v3-turbo")
        XCTAssertEqual(GroqModels.formatter, "llama-3.3-70b-versatile")
    }

    // MARK: - Prompt injection hardening

    func testUserMessageWrapsTranscriptInTags() {
        let msg = FormattingPrompt.userMessage(transcript: "hello world")
        XCTAssertTrue(msg.contains("<transcript>"))
        XCTAssertTrue(msg.contains("</transcript>"))
        XCTAssertTrue(msg.contains("hello world"))
    }

    func testSystemPromptDeclaresTranscriptTagsAsData() {
        for smart in [true, false] {
            let sys = FormattingPrompt.system(context: .empty, preset: .formal,
                                              dictionary: [], smartFormatting: smart)
            XCTAssertTrue(sys.contains("<transcript>"), "smartFormatting=\(smart)")
        }
    }

    func testSystemPromptEndsWithNeverAnswerReminder() {
        for smart in [true, false] {
            let sys = FormattingPrompt.system(context: .empty, preset: .formal,
                                              dictionary: [], smartFormatting: smart)
            let last = sys.split(separator: "\n").last.map(String.init) ?? ""
            XCTAssertTrue(last.lowercased().contains("never answer"), "smartFormatting=\(smart)")
        }
    }

    // MARK: - Formatting guardrail

    func testGuardrailAcceptsNormalCleanup() {
        XCTAssertTrue(FormattingService.plausibleFormatting(
            raw: "um so I think we should uh ship it tomorrow period",
            formatted: "I think we should ship it tomorrow."))
    }

    func testGuardrailAcceptsShortUtterancePunctuation() {
        XCTAssertTrue(FormattingService.plausibleFormatting(
            raw: "test test", formatted: "Test, test."))
    }

    func testGuardrailAcceptsNumberedListConversion() {
        XCTAssertTrue(FormattingService.plausibleFormatting(
            raw: "first buy milk second buy eggs third call mom",
            formatted: "1. Buy milk\n2. Buy eggs\n3. Call mom"))
    }

    func testGuardrailAcceptsEmailAndNumberRewrites() {
        XCTAssertTrue(FormattingService.plausibleFormatting(
            raw: "send an email to john dot smith at gmail dot com about the five hundred dollar invoice",
            formatted: "Send an email to john.smith@gmail.com about the $500 invoice."))
    }

    func testGuardrailRejectsOverlongOutput() {
        let raw = "tell me about swift concurrency"
        let formatted = String(repeating: "Swift concurrency uses async await and actors. ", count: 8)
        XCTAssertFalse(FormattingService.plausibleFormatting(raw: raw, formatted: formatted))
    }

    func testSystemPromptIncludesVerbatimExamples() {
        for smart in [true, false] {
            let sys = FormattingPrompt.system(context: .empty, preset: .formal,
                                              dictionary: [], smartFormatting: smart)
            XCTAssertTrue(sys.contains("Come up with a few ideas for me."), "smartFormatting=\(smart)")
        }
    }

    // Regression: short answer slipped past the word-count gate ("Come up with a few
    // ideas for me." came back as "Here are a few ideas.").
    func testGuardrailRejectsShortAnswer() {
        XCTAssertFalse(FormattingService.plausibleFormatting(
            raw: "Come up with a few ideas for me.",
            formatted: "Here are a few ideas."))
        XCTAssertFalse(FormattingService.plausibleFormatting(
            raw: "Come up with a few ideas for me.",
            formatted: "Here are a few ideas:"))
    }

    func testGuardrailAcceptsSelfCorrectionRewrite() {
        XCTAssertTrue(FormattingService.plausibleFormatting(
            raw: "send it Monday actually scratch that send it Tuesday",
            formatted: "Send it Tuesday."))
    }

    func testGuardrailAcceptsSpokenNumberConversion() {
        XCTAssertTrue(FormattingService.plausibleFormatting(
            raw: "first buy milk second call mom",
            formatted: "1. Buy milk\n2. Call mom"))
    }

    // Regression: real incident where the formatter answered the dictation instead of formatting it.
    func testGuardrailRejectsAnswerToDictation() {
        let raw = "I do some research on obsidian. I already have it downloaded on my laptop. But I want to start using it to make you smarter and more efficient and make codec smarter and more efficient. And I want to link you two together with them. I also want to link my work account for Claude and my personal Claude account together using that so that it remembers everything I'm working on on on both projects and between different computers as well. Do some research. Let me know what you think we should do. Give suggestions, ask questions, do whatever you need to do."
        let answer = "obsidian is a note-taking and knowledge management tool that allows users to create a graph database of notes and links between them. to integrate obsidian with codec, we could use the obsidian api to create a custom plugin that allows codec to interact with obsidian's database. this would enable codec to access and update obsidian notes, as well as create new links between notes. to link your work and personal claudes, we could use the claudes api to create a single, unified account that syncs data across both projects and computers. this would require setting up a single login credential that grants access to both accounts, and configuring the claudes api to sync data between the two accounts. before we proceed, can you confirm that you have the necessary permissions to integrate obsidian and claudes with codec, and that you are comfortable with the potential security implications of linking your work and personal accounts?"
        XCTAssertFalse(FormattingService.plausibleFormatting(raw: raw, formatted: answer))
    }
}
