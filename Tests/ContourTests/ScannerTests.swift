import XCTest
@testable import Contour

final class ScannerTests: XCTestCase {
    var root: URL!
    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: root) }
    func put(_ path: String, count: Int) throws {
        let url = root.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: 0x61, count: count).write(to: url)
    }
    func testTotalsAndGroupingAndSnapshotRoundtrip() throws {
        try put("images/a.png", count: 13); try put("b.txt", count: 7)
        let snapshot = try DiskScanner().scan(root: root)
        XCTAssertEqual(snapshot.logicalBytes, 20)
        XCTAssertEqual(snapshot.bytesByExtension["png"], 13)
        XCTAssertEqual(snapshot.bytesByTopDirectory["images"], 13)
        XCTAssertEqual(snapshot.largestFiles(limit: 1).first?.path, "images/a.png")
        XCTAssertEqual(try DiskSnapshot.decode(snapshot.json()).files, snapshot.files)
    }
    func testSymbolicLinksAreNotFollowedAndHardLinksAreDeduplicated() throws {
        try put("a", count: 10)
        try FileManager.default.linkItem(at: root.appendingPathComponent("a"), to: root.appendingPathComponent("hard"))
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("outside"), withDestinationURL: root.deletingLastPathComponent())
        let snapshot = try DiskScanner().scan(root: root)
        XCTAssertEqual(snapshot.files.count, 2)
        XCTAssertEqual(snapshot.logicalBytes, 10)
        XCTAssertEqual(snapshot.skippedLinks, 1)
    }
    func testDiffFindsAdditionRemovalAndGrowth() throws {
        try put("grow", count: 1); try put("remove", count: 3)
        let before = try DiskScanner().scan(root: root)
        try put("grow", count: 5); try put("new", count: 2)
        try FileManager.default.removeItem(at: root.appendingPathComponent("remove"))
        let after = try DiskScanner().scan(root: root)
        let diff = try SnapshotDifference(before: before, after: after)
        XCTAssertEqual(diff.added.map(\.path), ["new"])
        XCTAssertEqual(diff.removed.map(\.path), ["remove"])
        XCTAssertEqual(diff.changed.map { $0.after.path }, ["grow"])
    }
    func testCancellationReturnsPartialAndDiffRejectsIt() throws {
        try put("a", count: 1)
        let token = ScanCancellation(); token.cancel()
        let partial = try DiskScanner().scan(root: root, cancellation: token)
        XCTAssertTrue(partial.cancelled); XCTAssertTrue(partial.files.isEmpty)
        XCTAssertThrowsError(try SnapshotDifference(before: partial, after: partial))
    }
    func testCancelFromProgress() throws {
        for n in 0..<300 { try put("f\(n)", count: 1) }
        let token = ScanCancellation()
        let snapshot = try DiskScanner().scan(root: root, cancellation: token) { _ in token.cancel() }
        XCTAssertTrue(snapshot.cancelled)
        XCTAssertLessThan(snapshot.files.count, 300)
    }
    func testRejectsFileRoot() throws {
        try put("a", count: 1)
        XCTAssertThrowsError(try DiskScanner().scan(root: root.appendingPathComponent("a")))
    }
    func testRelativePathsRemainCorrectWhenRootIsASymbolicLink() throws {
        try put("folder/item.bin", count: 11)
        let alias = root.deletingLastPathComponent().appendingPathComponent(UUID().uuidString)
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: root)
        defer { try? FileManager.default.removeItem(at: alias) }
        let snapshot = try DiskScanner().scan(root: alias)
        XCTAssertEqual(snapshot.files.map(\.path), ["folder/item.bin"])
        XCTAssertEqual(snapshot.bytesByTopDirectory["folder"], 11)
    }
}
