// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CompanyMail",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "CompanyMail",
            targets: ["CompanyMail"]
        ),
    ],
    dependencies: [
        // Zéro dépendance externe !
        // IMAP/SMTP : Network.framework (natif Apple)
        // Keychain : Security.framework (natif Apple)
        // HTML : WebKit (natif Apple)
    ],
    targets: [
        .target(
            name: "CompanyMail",
            dependencies: [],
            path: "CompanyMail"
        ),
    ]
)
