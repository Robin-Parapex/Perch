import PerchAI
import PerchCore
import PerchDesign
import PerchFrigate
import PerchHome
import PerchPlayer
import PerchPlex
import PerchSeerr
import PerchTautulli
import PerchTrakt

/// Referencing every package keeps each one genuinely linked into the app.
enum ModuleManifest {
    static let moduleNames: [String] = [
        PerchCoreModule.name,
        PerchDesignModule.name,
        PerchPlexModule.name,
        PerchPlayerModule.name,
        PerchSeerrModule.name,
        PerchTraktModule.name,
        PerchHomeModule.name,
        PerchFrigateModule.name,
        PerchAIModule.name,
        PerchTautulliModule.name,
    ]
}
