import SwiftUI

/// What makes this fork Sprechwerk: Schaltwerk colors, where it lives, what it is based on.
enum SprechwerkBrand {
    /// Schaltwerk Digital brand colors (speech bubble mark).
    static let anthracite = Color(red: 0x2A / 255, green: 0x2D / 255, blue: 0x34 / 255)
    static let turquoise = Color(red: 0x2C / 255, green: 0xD5 / 255, blue: 0xC4 / 255)

    static let repositoryURL = "https://github.com/schaltwerkdigital/sprechwerk"
    /// Install and update in one line, see install.sh in the repository.
    static let installCommand = "curl -fsSL https://raw.githubusercontent.com/schaltwerkdigital/sprechwerk/main/install.sh | bash"

    /// The Blitztext release this version is built on, and where Blitztext lives.
    static let upstreamVersion = "1.15.1"
    static let upstreamURL = "https://github.com/cmagnussen/blitztext-app"
}
