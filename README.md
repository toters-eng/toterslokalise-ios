# Lingo Rider iOS SDK

> Lingo Rider keeps its technical name `toterslokalise` in packages, modules, classes and settings.

The Swift Package implements the frozen Lingo Rider OTA protocol v1 for iOS 15+
and macOS 12+.

```swift
import TotersLokalise

let bundled = DictionaryBundledTranslations([
    "en": ["common": ["welcome": "Welcome"]],
    "ar": ["common": ["welcome": "مرحباً"]],
])

let client = TotersLokaliseClient(configuration: try TotersLokaliseConfiguration(
    baseURL: URL(string: "https://arcade.stage.toters-api.com/toters-lokalise/api")!,
    token: "gl_sdk_your_public_read_token",
    projectId: "your-project-id",
    environment: "production",
    locale: "ar",
    cache: try FileCacheAdapter(
        directory: FileManager.default.urls(
            for: .cachesDirectory,
            in: .userDomainMask
        )[0].appendingPathComponent("TotersLokalise")
    ),
    bundled: bundled
))

Task { await client.initialize() }

// Always synchronous: OTA memory → bundled value → fallback → key.
let title = client.translation(
    for: "welcome",
    namespace: "common",
    fallback: "Welcome"
)
```

`initialize()`, `refresh()`, and `setLocale(_:)` are asynchronous. Translation
lookup never performs network access. Refresh validates scope, protocol, same
origin, byte size, and SHA-256 before atomically replacing cache. Every failure
keeps the last-known-good cache and bundled fallback available.

The SwiftUI demo source is in `Examples/SwiftUIExample`. It is a configuration-
driven, read-only client with release status, supported-locale switching, search,
namespace filtering, pull-to-refresh, large-list rendering, and RTL support.

## Installation

### Swift Package Manager

Add the Lingo Rider SDK (`toterslokalise-ios`) to your project using Swift Package Manager:

```swift
dependencies: [
    .package(
        url: "https://github.com/toters-eng/toterslokalise-ios.git",
        from: "1.3.3"
    )
]
```

Then add `TotersLokalise` as a dependency to your target.

You can also add the package directly in Xcode using:

**File → Add Package Dependencies**

and enter:

```text
https://github.com/toters-eng/toterslokalise-ios.git
```

## Build-only namespaces

Namespaces marked **Build only** in Lingo Rider are left out of OTA releases.
Download them in your CI/CD pipeline (one `<namespace>.json` per namespace, from
`GET /api/v1/projects/{projectId}/translations?environment=production&namespace=<name>&format=json`;
ready-made Bitbucket and GitHub Actions steps are on the Developer Hub) and bundle them
with the app. Lookups fall back to these bundled strings.

Add the `TotersLokalise` folder to the app target as a folder reference, then:

```swift
let bundled = ExportedBundledTranslations(bundle: .main, subdirectory: "TotersLokalise")
```

## Apps that already use `Localizable.strings`

An app that reads its text with `NSLocalizedString` and formats it with
`String(format:)` can put OTA in front of its `.strings` files without changing
its screens. `appleString(forKey:namespaces:)` returns a key's text exactly as
the Lingo Rider iOS `.strings` export writes it, or `nil` when the current release
doesn't have the key:

- Placeholders in iOS form: `{0}` is `%@` (`%1$@` when the arguments aren't in
  order), `{0:number}` is `%d`, `{0:decimal:2}` is `%.2f`, and a literal `%` is `%%`.
- Plurals as in the export with **Plurals: in the .strings file**: `key` is the
  "other" text and `key.one`, `key.few`… are its forms.
- Namespaces are searched in the order given. For the same result as an export
  that merges several namespaces into one file, pass them in byte order
  (`["Chat-Keys", "Common", "VoIP-Keys", "default"]`).

```swift
// For example in a Bundle.localizedString(forKey:value:table:) override:
if let text = client.appleString(forKey: key, namespaces: namespaces), !text.isEmpty {
    return text
}
return bundledLookup(key)
```

The lookup never touches the network and is cached per release.

## Releasing

Xcode reads versions straight from this repository's git tags; there is nothing to
publish. Merge to `main`, then `git tag 1.0.1 && git push origin 1.0.1`. The
Release workflow runs the tests and creates the GitHub release.
