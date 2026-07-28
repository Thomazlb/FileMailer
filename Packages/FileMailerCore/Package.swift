// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "FileMailerCore",
    platforms: [.macOS("26.0")],
    products: [
        .library(name: "FileMailerDomain", targets: ["FileMailerDomain"]),
        .library(name: "FileMailerIPC", targets: ["FileMailerIPC"]),
        .library(name: "RecipientRanking", targets: ["RecipientRanking"]),
        .library(name: "GmailAuth", targets: ["GmailAuth"]),
        .library(name: "GmailAPI", targets: ["GmailAPI"]),
        .library(name: "GoogleDrive", targets: ["GoogleDrive"]),
        .library(name: "MIME", targets: ["MIME"]),
        .library(name: "FileAnalysis", targets: ["FileAnalysis"]),
        .library(name: "AIComposition", targets: ["AIComposition"]),
        .library(name: "Persistence", targets: ["Persistence"]),
        .library(name: "FileMailerCore", targets: ["FileMailerCore"])
    ],
    dependencies: [
        .package(url: "https://github.com/openid/AppAuth-iOS.git", exact: "2.1.0"),
        .package(url: "https://github.com/weichsel/ZIPFoundation.git", exact: "0.9.20")
    ],
    targets: [
        .target(name: "FileMailerDomain"),
        .target(name: "FileMailerIPC", dependencies: ["FileMailerDomain"]),
        .target(name: "RecipientRanking", dependencies: ["FileMailerDomain"]),
        .target(
            name: "GmailAuth",
            dependencies: [
                "FileMailerDomain",
                .product(name: "AppAuth", package: "AppAuth-iOS")
            ]
        ),
        .target(name: "MIME", dependencies: ["FileMailerDomain"]),
        .target(name: "GmailAPI", dependencies: ["FileMailerDomain", "MIME"]),
        .target(name: "GoogleDrive", dependencies: ["FileMailerDomain"]),
        .target(
            name: "FileAnalysis",
            dependencies: [
                "FileMailerDomain",
                .product(name: "ZIPFoundation", package: "ZIPFoundation")
            ]
        ),
        .target(name: "AIComposition", dependencies: ["FileMailerDomain"]),
        .target(name: "Persistence", dependencies: ["FileMailerDomain"]),
        .target(
            name: "FileMailerCore",
            dependencies: [
                "FileMailerDomain",
                "FileMailerIPC",
                "RecipientRanking",
                "GmailAuth",
                "GmailAPI",
                "GoogleDrive",
                "MIME",
                "FileAnalysis",
                "AIComposition",
                "Persistence"
            ]
        ),
        .testTarget(
            name: "FileMailerCoreTests",
            dependencies: [
                "FileMailerDomain",
                "FileMailerIPC",
                "RecipientRanking",
                "GmailAuth",
                "MIME",
                "GmailAPI",
                "GoogleDrive",
                "FileAnalysis",
                "AIComposition",
                "Persistence"
            ],
            resources: [.copy("Fixtures")]
        )
    ]
)
