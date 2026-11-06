import Foundation

/// How a certificate reads on screen (WP-11): Plex sends some with a country prefix ("gb/12A", "de/16"); the
/// screen shows only the rating ("12A"). Parsing for the ceiling stays in `RatingCeiling`, which strips the same
/// prefix. Empty or blank values give nil, so a facts line simply leaves the certificate out.
public enum CertificateDisplay {
    public static func text(_ certificate: String?) -> String? {
        guard var text = certificate?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        if let slash = text.firstIndex(of: "/") {
            text = String(text[text.index(after: slash)...]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return text.isEmpty ? nil : text
    }
}
