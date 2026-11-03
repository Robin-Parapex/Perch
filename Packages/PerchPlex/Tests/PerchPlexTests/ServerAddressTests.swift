import Foundation
import Testing

@testable import PerchPlex

@Suite("Server address parser")
struct ServerAddressTests {
    @Test(arguments: [
        ("192.168.1.10", "http://192.168.1.10:32400"),
        ("https://plex.example.com", "https://plex.example.com:32400"),
        ("plex.local:32401", "http://plex.local:32401"),
        ("fe80::1", "http://[fe80::1]:32400"),
        ("[fe80::1]:32400", "http://[fe80::1]:32400"),
        ("[fe80::1]:8000", "http://[fe80::1]:8000"),
        ("  192.168.1.10  \n", "http://192.168.1.10:32400"),
        ("http://nas.lan:80/", "http://nas.lan:80"),
        ("HTTPS://Plex.Example.com:443", "https://Plex.Example.com:443"),
    ])
    func accepts(input: String, expected: String) throws {
        #expect(try ServerAddress.parse(input).absoluteString == expected)
    }

    @Test(arguments: [
        ("", ServerAddressError.empty),
        ("   ", .empty),
        ("ftp://x", .unsupportedScheme),
        ("192.168.1.10:0", .invalidPort),
        ("192.168.1.10:99999", .invalidPort),
        ("192.168.1.10:abc", .invalidPort),
        ("plex.local/library", .invalidHost),
        ("plex.local?x=1", .invalidHost),
        ("user:pass@plex.local", .invalidHost),
        ("http://user:pass@plex.local:32400", .invalidHost),
    ])
    func rejects(input: String, error: ServerAddressError) {
        #expect(throws: error) { try ServerAddress.parse(input) }
    }
}
