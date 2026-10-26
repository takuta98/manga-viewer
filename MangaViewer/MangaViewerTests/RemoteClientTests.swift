import XCTest
@testable import MangaViewer

final class RemoteClientTests: XCTestCase {
    func testSMBEndpointParsesHostShareAndCredentials() throws {
        var source = RemoteSource.blank(.smb)
        source.host = "smb://user:secret@192.168.1.10/media/comics"
        source.shareOrPath = ""
        source.username = ""
        source.password = ""

        let endpoint = try SMBClientService.Endpoint.resolve(source)
        XCTAssertEqual(endpoint.urlString, "smb://192.168.1.10")
        XCTAssertEqual(endpoint.share, "media")
        XCTAssertEqual(endpoint.pathInsideShare, "comics")
        XCTAssertEqual(endpoint.username, "user")
        XCTAssertEqual(endpoint.password, "secret")
    }

    func testSMBEndpointKeepsExplicitShareWhenHostHasPath() throws {
        var source = RemoteSource.blank(.smb)
        source.host = "192.168.1.20"
        source.shareOrPath = "books/manga"
        source.port = 445

        let endpoint = try SMBClientService.Endpoint.resolve(source)
        XCTAssertEqual(endpoint.urlString, "smb://192.168.1.20")
        XCTAssertEqual(endpoint.share, "books")
        XCTAssertEqual(endpoint.pathInsideShare, "manga")
    }

    func testSMBEndpointParsesDomainFromUsername() throws {
        var source = RemoteSource.blank(.smb)
        source.host = "nas.local"
        source.username = "WORKGROUP;alice"
        source.password = "pw"
        source.shareOrPath = "share"

        let endpoint = try SMBClientService.Endpoint.resolve(source)
        XCTAssertEqual(endpoint.domain, "WORKGROUP")
        XCTAssertEqual(endpoint.username, "alice")
        XCTAssertFalse(endpoint.sessionKey.isEmpty)
    }

    func testFTPPASVParse() throws {
        let parsed = try FTPClient.parsePASV("227 Entering Passive Mode (192,168,0,5,195,123).")
        XCTAssertEqual(parsed.0, "192.168.0.5")
        XCTAssertEqual(parsed.1, UInt16(195 * 256 + 123))
    }

    func testFTPPASVParseRejectsMalformed() {
        XCTAssertThrowsError(try FTPClient.parsePASV("200 OK"))
        XCTAssertThrowsError(try FTPClient.parsePASV("227 Entering Passive Mode (1,2,3)."))
    }
}
