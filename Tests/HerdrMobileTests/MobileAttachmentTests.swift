import XCTest
@testable import HerdrMobile

@MainActor
final class MobileAttachmentTests: XCTestCase {
    func testOversizeFileIsRejectedBeforeExternalUpload() async {
        let draft = MobileChatDraft()
        let boundary = UploadBoundary()
        await draft.upload(data: Data(repeating: 1, count: 8 * 1024 * 1024 + 1), name: "large.pdf", contentType: "application/pdf") { _, _, _ in
            await boundary.upload()
        }
        XCTAssertNotNil(draft.error)
        XCTAssertTrue(draft.attachments.isEmpty)
        let calls = await boundary.calls
        XCTAssertEqual(calls, 0)
    }

    func testProfileInvalidationDiscardsUploadThatFinishesForOldTarget() async throws {
        let draft = MobileChatDraft()
        let uploading = Task {
            await draft.upload(data: Data([1, 2]), name: "file.txt", contentType: "text/plain") { _, _, _ in
                try await Task.sleep(for: .milliseconds(80))
                return "/tmp/old-target.txt"
            }
        }
        try await Task.sleep(for: .milliseconds(20))
        draft.invalidate()
        await uploading.value
        XCTAssertTrue(draft.attachments.isEmpty)
        XCTAssertFalse(draft.uploading)
    }
}
private actor UploadBoundary {
    var calls = 0
    func upload() -> String { calls += 1; return "/tmp/uploaded.pdf" }
}
