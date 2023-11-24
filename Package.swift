// swift-tools-version: 5.7
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
	name: "OpenAIKit",
    platforms: [
        .iOS(.v13)
    ],
	products: [
		.library(
			name: "OpenAIKit",
			targets: ["OpenAIKit"]),
	],
	targets: [
		.target(
			name: "OpenAIKit",
			dependencies: [],
			path: "Sources"),
		.testTarget(
			name: "OpenAIKitTests",
			dependencies: ["OpenAIKit"]),
	])
