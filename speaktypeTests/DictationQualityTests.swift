import Foundation
import XCTest
@testable import speaktype

final class DictationQualityTests: XCTestCase {
    func testDictionaryBoundsAndNormalizesHintsWithoutChangingPreferredSpelling() {
        let dictionary = " Clerk \nclerk\r\nGöteborg\nConvex Webhooks\n<invalid>\n\t\n"
            + String(repeating: "x", count: 200)
        XCTAssertEqual(DictationHints.keywords(in: dictionary), ["Clerk", "Göteborg", "Convex Webhooks"])
    }

    func testOpenRouterGPTTranscribeSendsNativeBilingualAndDictionaryHints() throws {
        let model = try XCTUnwrap(RemoteTranscriptionModel.defaultModel(for: .openRouter))
        let client = RemoteTranscriptionClient(provider: .openRouter, model: model)
        let request = try client.makeRequest(
            key: "test", audioData: Data([1, 2, 3]), filename: "test.wav",
            language: DictationHints.swedishEnglish, dictionary: "Clerk\nGöteborg"
        )
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        let payload = try XCTUnwrap(
            JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any]
        )
        let provider = try XCTUnwrap(payload["provider"] as? [String: Any])
        let options = try XCTUnwrap(provider["options"] as? [String: [String: [String]]])
        XCTAssertEqual(options["openai"]?["languages"], ["sv", "en"])
        XCTAssertEqual(options["openai"]?["keywords"], ["Clerk", "Göteborg"])
        XCTAssertNil(payload["language"])
    }

    func testDirectGPTTranscribeUsesRepeatedMultipartFields() throws {
        let model = try XCTUnwrap(RemoteTranscriptionModel.model(id: "gpt-transcribe"))
        let client = RemoteTranscriptionClient(provider: .openAI, model: model)
        let request = try client.makeRequest(
            key: "test", audioData: Data(), filename: "test.wav",
            language: DictationHints.swedishEnglish, dictionary: "Clerk"
        )
        let body = try XCTUnwrap(request.httpBody.map { String(decoding: $0, as: UTF8.self) })
        XCTAssertTrue(body.contains("name=\"languages[]\"\r\n\r\nsv"))
        XCTAssertTrue(body.contains("name=\"languages[]\"\r\n\r\nen"))
        XCTAssertTrue(body.contains("name=\"keywords[]\"\r\n\r\nClerk"))
        XCTAssertFalse(body.contains("name=\"language\""))
    }

    func testOtherProviderKeepsAutoDetectForMixedSpeechAndUsesSingleLanguageAsBefore() throws {
        let model = try XCTUnwrap(RemoteTranscriptionModel.defaultModel(for: .groq))
        let client = RemoteTranscriptionClient(provider: .groq, model: model)
        for language in [DictationHints.swedishEnglish, "sv"] {
            let request = try client.makeRequest(
                key: "test", audioData: Data(), filename: "test.wav",
                language: language, dictionary: "Clerk"
            )
            let body = try XCTUnwrap(request.httpBody.map { String(decoding: $0, as: UTF8.self) })
            XCTAssertEqual(body.contains("name=\"language\"\r\n\r\nsv"), language == "sv")
            XCTAssertFalse(body.contains("Clerk"))
        }
    }

    func testHaikuIsPinnedAndDisablesThinkingForShortCleanup() {
        XCTAssertEqual(CleanupModel.defaultModelID, "anthropic/claude-haiku-5.5")
        let payload = RemoteCleanupClient.requestBody(
            provider: .openRouter, modelID: CleanupModel.defaultModelID,
            transcript: "Kan du granska ändringarna?", instruction: RemoteCleanupClient.systemPrompt, wrapInTags: true
        )
        XCTAssertNil(payload["temperature"])
        XCTAssertEqual(payload["reasoning"] as? [String: Bool], ["enabled": false])
        let messages = payload["messages"] as? [[String: String]]
        XCTAssertEqual(messages?.last?["content"], "<transcript>\nKan du granska ändringarna?\n</transcript>")
    }

    func testCleanupKeepsDictatedQuestionButRejectsAnswerOrLeakedTags() {
        let question = "Vad är huvudstaden i Frankrike?"
        XCTAssertTrue(WritingPolishService.isPlausibleCleanup(raw: question, cleaned: question))
        XCTAssertFalse(WritingPolishService.isPlausibleCleanup(raw: question, cleaned: "Paris."))
        XCTAssertFalse(WritingPolishService.isPlausibleCleanup(raw: question, cleaned: "\(question)</transcript>"))
    }
}
