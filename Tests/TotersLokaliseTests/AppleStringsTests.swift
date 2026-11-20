import CryptoKit
import Foundation
import XCTest

@testable import TotersLokalise

/// Expected values come from the Lingo Rider backend's iOS export
/// (convertEntry with target ios, Arguments: auto), so OTA text and the
/// .strings files read the same.
final class AppleStringsTests: XCTestCase {

  func testPlaceholdersMatchTheStringsExport() {
    let cases: [(String, String)] = [
      ("Hello {0}", "Hello %@"),
      ("{1} then {0}", "%2$@ then %1$@"),
      ("You have {0:number} items", "You have %d items"),
      ("Total {0:decimal:2}", "Total %.2f"),
      ("50% off {0}", "50%% off %@"),
      ("No placeholders 50%", "No placeholders 50%"),
      ("Hi {name}, {0}", "Hi %2$@, %1$@"),
      ("{{literal}} {0}", "{literal} %@"),
      ("{bad token!} {0}", "{bad token!} {0}"),
      ("{0} and {2}", "%1$@ and %3$@"),
      ("كم {0} عنصر", "كم %@ عنصر"),
      ("{0}% done", "%@%% done"),
      ("Already iOS %@", "Already iOS %@"),
      ("${applicationName} orders", "${applicationName} orders"),
      ("${app}: {0}% off", "${app}: %@%% off"),
    ]
    for (text, expected) in cases {
      XCTAssertEqual(appleStringsValue(text), expected, text)
    }
  }

  func testPluralsReadLikeTheFlatExport() {
    let artifact = makeArtifact(
      namespaces: ["default": ["title": "Hello {0}", "empty": ""]],
      plurals: [
        "default": [
          "days_full": OTAPluralMessage(
            variable: "count",
            forms: ["one": "a day", "few": "{count} days", "other": "{count} days"]),
          "label_items": OTAPluralMessage(
            variable: "count",
            forms: ["zero": "{1} item", "one": "{1} item", "other": "{1} items"]),
          "in_store": OTAPluralMessage(
            variable: "count",
            forms: ["one": "{count} item in {0}", "other": "{count} items in {0}"]),
        ]
      ])
    let look = { (key: String) in resolveAppleString(key: key, namespaces: ["default"], artifact: artifact) }
    XCTAssertEqual(look("days_full"), "%1$d days")
    XCTAssertEqual(look("days_full.one"), "a day")
    XCTAssertEqual(look("days_full.few"), "%1$d days")
    XCTAssertNil(look("days_full.two"), "a form the plural lacks is not there, like in the export")
    XCTAssertEqual(look("label_items.zero"), "%2$@ item")
    XCTAssertEqual(look("label_items"), "%2$@ items")
    XCTAssertEqual(look("in_store.one"), "%1$d item in %2$@")
    XCTAssertEqual(look("title"), "Hello %@")
    XCTAssertEqual(look("empty"), "", "an empty published value stays empty")
    XCTAssertNil(look("missing"))
    XCTAssertNil(look("title.few"), "only plurals have forms")
    XCTAssertNil(look("version.2"))
  }

  func testNamespacesAreSearchedInOrder() {
    let artifact = makeArtifact(
      namespaces: [
        "Common": ["label_place_order": "Place order"],
        "default": ["label_place_order": "Place your order", "only_default": "Default"],
      ],
      plurals: [:])
    XCTAssertEqual(
      resolveAppleString(key: "label_place_order", namespaces: ["Common", "default"], artifact: artifact),
      "Place order")
    XCTAssertEqual(
      resolveAppleString(key: "label_place_order", namespaces: ["default", "Common"], artifact: artifact),
      "Place your order")
    XCTAssertEqual(
      resolveAppleString(key: "only_default", namespaces: ["Common", "default"], artifact: artifact),
      "Default")
    XCTAssertNil(resolveAppleString(key: "only_default", namespaces: ["Common"], artifact: artifact))
  }

  func testClientLookupUsesTheInstalledReleaseAndForgetsItOnLocaleChange() async throws {
    let english = makeArtifact(namespaces: ["default": ["greeting": "Hi {0}"]], plurals: [:], locale: "en-US")
    let arabic = makeArtifact(namespaces: ["default": ["greeting": "مرحبا {0}"]], plurals: [:], locale: "ar-LB")
    let transport = ReleaseTransport(artifacts: ["en-US": english, "ar-LB": arabic])
    let client = TotersLokaliseClient(
      configuration: try TotersLokaliseConfiguration(
        baseURL: URL(string: "https://ota.example/api")!,
        token: "gl_sdk_public_reference_token_abcdefghijklmnopqrstuvwxyz",
        projectId: "project",
        environment: "production",
        locale: "en-US",
        transport: transport))

    XCTAssertNil(client.appleString(forKey: "greeting", namespaces: ["default"]), "nothing installed yet")
    let initialized = await client.initialize()
    XCTAssertEqual(initialized, .updated(release: 1))
    XCTAssertEqual(client.appleString(forKey: "greeting", namespaces: ["default"]), "Hi %@")
    XCTAssertEqual(client.appleString(forKey: "greeting", namespaces: ["default"]), "Hi %@", "cached")
    let switched = await client.setLocale("ar-LB")
    XCTAssertEqual(switched, .updated(release: 1))
    XCTAssertEqual(client.appleString(forKey: "greeting", namespaces: ["default"]), "مرحبا %@")
  }

  private func makeArtifact(
    namespaces: [String: [String: String]],
    plurals: [String: [String: OTAPluralMessage]],
    locale: String = "en-US"
  ) -> OTAArtifact {
    var texts = namespaces
    for (namespace, entries) in plurals {
      for (key, plural) in entries { texts[namespace, default: [:]][key] = plural.forms["other"] }
    }
    return OTAArtifact(
      protocolVersion: 1, projectId: "project", environment: "production", release: 1,
      locale: locale, namespaces: texts, pluralMessages: plurals)
  }
}

/// Serves release 1 of each locale's artifact.
private struct ReleaseTransport: OTATransport {
  let artifacts: [String: OTAArtifact]

  private func encode(_ artifact: OTAArtifact) throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = .sortedKeys
    return try encoder.encode(artifact)
  }

  func get(url: URL, headers _: [String: String], timeout _: TimeInterval) async throws -> OTAHTTPResponse {
    let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
    if url.lastPathComponent == "manifest" {
      let locale = components?.queryItems?.first { $0.name == "locale" }?.value ?? ""
      guard let artifact = artifacts[locale] else { return OTAHTTPResponse(status: 404, body: Data()) }
      let data = try encode(artifact)
      let manifest = OTAManifest(
        protocolVersion: 1, projectId: "project", environment: "production", release: 1,
        generatedAt: "2026-11-19T00:00:00Z",
        locales: [
          locale: OTAManifestLocale(
            hash: "sha256:" + SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined(),
            url: "/api/artifacts/\(locale).json", size: data.count)
        ])
      return OTAHTTPResponse(status: 200, body: try JSONEncoder().encode(manifest))
    }
    let locale = url.deletingPathExtension().lastPathComponent
    guard let artifact = artifacts[locale] else { return OTAHTTPResponse(status: 404, body: Data()) }
    return OTAHTTPResponse(status: 200, body: try encode(artifact))
  }
}
