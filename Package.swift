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
        // MailCore2 pour IMAP/SMTP
        .package(url: "https://github.com/nicklama/mailcore2-spm", from: "0.6.4"),
        // KeychainAccess pour le stockage sécurisé
        .package(url: "https://github.com/kishikawakatsumi/KeychainAccess.git", from: "4.2.2"),
        // SwiftSoup pour parser le HTML des emails
        .package(url: "https://github.com/scinfu/SwiftSoup.git", from: "2.7.0"),
    ],
    targets: [
        .target(
            name: "CompanyMail",
            dependencies: [
                .product(name: "MailCore2", package: "mailcore2-spm"),
                "KeychainAccess",
                "SwiftSoup",
            ],
            path: "CompanyMail"
        ),
    ]
)
