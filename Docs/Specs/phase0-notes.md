# Phase 0 — Foundations: scaffold notes

*Oct 17, 2026. What the Phase 0 scaffold contains, what was verified, and what still needs Caleb before the exit criteria in [04-Execution-Plan](../Planning/04-Execution-Plan.md) §2 ("empty app with tabs, syncing store, CI green") are fully met. Updated the same evening after Caleb's review of the planning docs (see "Review changes" at the end).*

## What exists

| Piece | Where | Notes |
|---|---|---|
| Xcode 27 project | `RecipeCodex.xcodeproj` | Three targets, Swift 6 language mode, iOS 27.0 minimum, iPhone + iPad. Uses Xcode's synchronized folders, so new files under a target folder join the target automatically. |
| App target | `RecipeCodex/` | Five-tab shell (Recipes with a Recipes · Books view switch, Pantry with a pane selector, Plan, Cook, trailing Search) with `.sidebarAdaptable`, empty-state views only; contextual Add and More toolbar menus, disabled until their flows exist. Opens the SwiftData store from `RecipeStore`. `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`. |
| Share Extension | `RecipeCodexShare/` | `com.apple.share-services`, accepts one web URL or page. Phase 0 shows the URL and dismisses; Phase 1 parses through Capture. |
| Widget extension | `RecipeCodexWidgets/` | WidgetKit bundle with a placeholder "Tonight" widget and a Live Activity (`CookActivityWidget`). App Info.plist has `NSSupportsLiveActivities`. |
| Shared sources | `Shared/` | `CookActivityAttributes`, compiled into app and widget targets. |
| Packages | `Packages/*` | RecipeModel, Units, Capture, Intelligence, KnowledgeBase, Scheduler, Nutrition. Each has a Swift Testing target and a small real API (see below). Tools version 6.2, platforms iOS 27 / macOS 27, so `swift test` runs on the Mac and (for the pure ones) on Linux. |
| Schema v1 | `Packages/RecipeModel/Sources/RecipeModel/Models/` | 29 models: 02 §4.2's entities plus `RecipeImage` for page scans and cook photos, and `Source`, `BeverageItem` and `Pairing` from the review. Nested in `RecipeSchemaV1: VersionedSchema` with top-level typealiases; `RecipeMigrationPlan` is empty until v2. |
| Shared scheme | `RecipeCodex.xcodeproj/xcshareddata/xcschemes/RecipeCodex.xcscheme` | Builds the app and embeds both extensions. Its Test action is empty: `xcodebuild` could not resolve package test bundles added to a project scheme by hand, so package tests run with `swift test` or with `xcodebuild test` from inside a package folder (see commands below). |

### Package stubs

- **Units**: `Rational` (exact fractions, lowest terms, mixed-number description), `CookingUnit`, `Quantity.scaled(by:)`.
- **KnowledgeBase**: `StoreSection`, `ComponentType` + `HoldRule.default(for:)`, `TemperatureTable` (doneness targets and USDA minimums).
- **Scheduler**: `SchedulableTask`, `SchedulingProblem`, `Scheduler.schedule` doing dependency-respecting backward list scheduling (no concurrency limit yet), cycle detection.
- **Intelligence**: `ModelTier`, `ModelAvailability.onDevice()` (FoundationModels behind `canImport`), `RecipeStructuring` protocol with `DeterministicRecipeStructurer` as the non-model path.
- **Capture**: `JSONLDRecipeParser` for schema.org Recipe (bare, array, `@graph`, HowToSection), `ImportedRecipe`, ISO 8601 durations.
- **Nutrition**: `NutrientProfile`, `NutritionEstimator` (per-serving math with confidence from matched mass), `FoodDataCentralClient` placeholder that throws until an API key exists.

### Naming deviations from 02 §4.2

Two entity names collide with types every view file imports, so the Swift classes differ from the doc:

| Doc name | Swift class | Reason |
|---|---|---|
| `Menu` | `EventMenu` | SwiftUI has `Menu`. |
| `Task` | `ScheduleTask` | Swift concurrency has `Task`. |

Ingredient quantities are stored as `quantityNumerator` / `quantityDenominator` (`Int?`) rather than a `Rational` so RecipeModel keeps no dependency on Units; `unit` is the raw string of `Units.CookingUnit`.

### CloudKit rules, enforced by a test

`SchemaTests.followsCloudKitRules` walks the built `Schema` and asserts: every relationship is optional, has an inverse and never uses `.deny`; no attribute is unique; every non-optional attribute has a default; every `*ImageData` attribute uses `.externalStorage`. `insertsOneOfEachModel` builds an in-memory container and saves one instance of every model; `pairingLinksSlotAndCellar` round-trips a pairing between a menu slot and a bottle.

## Verified on this Mac

- `swift test` passes in all seven packages (macOS 27.0.1, Xcode 27.0, Swift 6.4).
- RecipeModel's schema tests also pass on the iPhone 17 Pro simulator (iOS 27.0) via `xcodebuild test` from the package folder, so the in-memory container, one-of-each insert and CloudKit-rules check hold on the real target OS.
- `xcodebuild build -scheme RecipeCodex` for the iPhone 17 Pro simulator (iOS 27.0): BUILD SUCCEEDED with no warnings; both extensions are embedded in `RecipeCodex.app/PlugIns` and all three binaries carry the App Group entitlement. The iPhone 17 Pro simulator did not exist and was created with `xcrun simctl create`.
- Nothing was signed for a device and no iCloud capability is enabled.

## Still needs Caleb

| Item | Why | Where to change |
|---|---|---|
| **Sync proof** | 04 §2 Phase 0 asks to prove sync between iPhone and iPad with a throwaway record. The iPhone build is installed (below); the iPad has not been connected yet, and there is no UI to enter a record until Phase 1. | Install on the iPad Pro once Phase 1's manual entry exists; add a recipe on one device and watch it appear on the other. |
| **GitHub remote and Claude GitHub App** | Repo is local only. Caleb decided on a **public** repository (04 §5.1); `gh` is already logged in as `calebpie`. Create it, push `main`, install the Claude GitHub App so cloud sessions can run the pure-Swift packages. Copyrighted fixtures (photographed cookbook pages) must stay out: `Docs/Fixtures/Private/` is gitignored for them. | `gh repo create RecipeCodex --public --source=. --remote=origin --push` |
| **Design tokens and app icon** | Asset catalog has empty `AppIcon` and `AccentColor`. Icon Composer file and accent colour are Phase 0 items not covered here. | `RecipeCodex/Assets.xcassets`. |
| **AlarmKit usage description** | AlarmKit needs `NSAlarmKitUsageDescription` in the app Info.plist before the first timer (Phase 3). App Intents need no capability. Neither is added yet. | `INFOPLIST_KEY_NSAlarmKitUsageDescription` in `project.pbxproj`. |

## Useful commands

```bash
xcodebuild build -project RecipeCodex.xcodeproj -scheme RecipeCodex -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=27.0'
```

```bash
for p in Packages/*; do (cd "$p" && swift test); done
```

Run one package's tests on the iOS simulator instead of the Mac (from inside the package folder):

```bash
cd Packages/RecipeModel && xcodebuild test -scheme RecipeModel -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=27.0'
```

## Review changes (Oct 17, 2026, evening)

Caleb's review of the planning docs changed the scaffold as follows; the decisions themselves are recorded in [04-Execution-Plan](../Planning/04-Execution-Plan.md) §5.1.

- **Team.** `DEVELOPMENT_TEAM = BXSW6MRVTR` (Caleb's individual team) is set at the project level for all configurations, so all three targets inherit it. Nothing is signed for a device yet and no capability was added; the simulator build is unchanged.
- **Tabs.** Order is now Recipes · Pantry · Plan · Cook · Search (`AppTab`). `BooksView` is gone; `RecipesView` has a segmented Recipes · Books switch with a contextual Add menu (Import, Scan Page, New Recipe vs Add Book) and a More menu. `PantryView` is new, with a chip-style pane selector for Pantry, Tools, Sources, Cellar & Bar, Kitchens and Profile. The app launches on Recipes.
- **Schema v1 (still unshipped, so edited in place rather than migrated).** New models `Source` (supplier directory and frequented stores; optional `book` and `kitchen`, inverse of `ShoppingItem.source`), `BeverageItem` (cellar and bar, cascade-owned by `Kitchen`) and `Pairing` (on `Slot`, optional `beverage`). New attributes `Book.reviewedLayouts`, `RecipeVersion.captureConfidence` and `RecipeVersion.needsReview` for the scan-review policy. `UserProfile.knuckleModeEnabled` became `kitchenThemeEnabled`. New enums `SourceKind`, `SourceCategory`, `BeverageKind`, `PairingRole`.
- **Verified.** `swift test` passes in RecipeModel (5 tests, CloudKit rules included) and `xcodebuild build` for the iPhone 17 Pro simulator succeeds.

## Second review round (Oct 17, 2026, later that evening)

Caleb answered the remaining questions (04 §5.1). Changes:

- **Signing and portal.** `xcodebuild build -destination 'generic/platform=iOS' -allowProvisioningUpdates` with automatic signing and Caleb's Apple account registered the three App IDs with their capabilities, the App Group, the iCloud container `iCloud.com.calebpietrafesa.RecipeCodex` and push, and created "iOS Team Provisioning Profile" profiles for all three bundle IDs (signing identity `Apple Development: cep93@cornell.edu`). The embedded profile carries the iCloud, App Group and `aps-environment` entitlements.
- **Entitlements.** The app target now has `com.apple.developer.icloud-services` (CloudKit), `com.apple.developer.icloud-container-identifiers` and `aps-environment` (development), plus `UIBackgroundModes = remote-notification` so CloudKit pushes wake the mirroring. The extensions keep App Groups only.
- **Store.** `RecipeStore.makeContainer(inMemory:syncsWithCloudKit:)`; the app passes `syncsWithCloudKit: true` (`.private("iCloud.com.calebpietrafesa.RecipeCodex")`), falls back to a local store, then to in-memory. Extensions open the same file without mirroring; persistent history carries their writes to the app, which exports them. The CloudKit development schema is created by SwiftData on first run with an iCloud account; it must be deployed to production from CloudKit Console before any App Store or TestFlight build.
- **Model routing.** `Intelligence.ModelRouting.tier(for:preferredHeavyReasoning:)`: extraction always on device, heavy reasoning `appleCloud` by default, `claude` when chosen. `UserProfile.heavyReasoningModel` stores the choice as a raw string.
- **Installed on the iPhone 17 Pro** (`devicectl device install app`); launch from here was refused because the phone was locked, so the first run (and the iCloud schema creation) happens when Caleb opens it. Also run on the iPhone 17 Pro simulator: the CloudKit store opened without falling back; mirroring reports "No account" there, as expected.
- **Verified.** Package tests pass (Intelligence 5, RecipeModel 5); simulator and signed device builds succeed.
