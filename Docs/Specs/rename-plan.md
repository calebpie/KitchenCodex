# Renaming the app

*Teed up Oct 21, 2026, after Caleb's market pass, and **decided the same day: the app is Kitchen Codex** (04 §5.1 "Name"), both tiers below to run at the Phase 2 slice 5 → 6 boundary. This is the runbook. An unrelated iPad app called "RecipeCodex" is already on the App Store, so the current display name would collide if the app ever ships; a web search on Oct 21 found no app called Kitchen Codex (only a $2.99 ebook of that title).*

## 1. What the name touches

Everything below was inventoried on Oct 21 against `main` at `f7b9391`.

**Tier 1 — the visible name (any time, one commit, no data consequences)**

| Where | What | Count |
|---|---|---|
| `RecipeCodex.xcodeproj/project.pbxproj` | `INFOPLIST_KEY_CFBundleDisplayName = "Recipe Codex"` for the app, the share extension and the widgets, Debug and Release | 6 settings |
| App and package strings | "Recipe Codex" in user-facing text: camera-off messages (`ScanPageView`, `BookScanView`, `AddCookbookView`), the sync strip's sentences (`SyncMonitor`), Scan Cookbook's barcode copy, Import from Web's copy, Search's "Search Recipe Codex", the editor's "before Recipe Codex", the library export's file names (`ProfilePane`: "Recipe Codex Library.zip"), the PDF creator (`RecipePrintLayout`), the Read Fixtures album name (`ReadFixtures.albumName`), `ZipArchive`/`WebRecipeImporter`/`LibraryImporter` messages in `Packages/Capture` | about 25 strings |
| Docs | `Docs/Planning/*` (00, 01, 02, 03, 04, wireframes.html), `Docs/Specs/*` notes and plan, `Docs/Input/InitialProposal.md` (leave the proposal as written) | about 28 mentions |
| GitHub | repository `calebpie/RecipeCodex` → `calebpie/KitchenCodex` (GitHub redirects the old URL; `git remote set-url origin` locally) | 1 |

Not in Tier 1: the local folder `~/Developer/RecipeCodex`. Claude Code keys this project's memory and session history to that path, so renaming the folder orphans both. Keep the folder name until that is worth a deliberate move.

**Tier 2 — identifiers and project names (decide once; best while every store holds only test data)**

| Where | Today | Consequence of changing |
|---|---|---|
| `PRODUCT_BUNDLE_IDENTIFIER` ×3 (app, `.Share`, `.Widgets`) | `com.calebpietrafesa.RecipeCodex…` | A new app as far as iOS is concerned: installs beside the old one on simulators and devices (delete the old); new App IDs registered by automatic signing (`-allowProvisioningUpdates`, team BXSW6MRVTR). Invisible to users. Cannot change after a first App Store upload, so if it changes, it changes before any TestFlight build. |
| `RecipeStore.cloudKitContainerIdentifier` (`Packages/RecipeModel/Sources/RecipeModel/RecipeStore.swift`) and the app's entitlements | `iCloud.com.calebpietrafesa.RecipeCodex` | A fresh, empty CloudKit container; the old container's records stay behind. Today that is test data on two devices and two simulators (which run signed out). After Phase 3 it would be Caleb's real library, and moving it means an export and re-import. The development schema is re-created on first run. |
| `RecipeStore.appGroupIdentifier` and the three entitlements files | `group.com.calebpietrafesa.RecipeCodex` | A new shared container: the local store, the Book Scans folder and anything the share extension and widgets read start empty. Same test-data caveat. |
| `RecipeStore.storeFileName` | `RecipeCodex.store` | Cosmetic once the group changes; leave or rename in the same commit. |
| `RecipeSpotlightIndexer.domainIdentifier` | `com.calebpietrafesa.RecipeCodex.recipe` | Old Spotlight items linger until reindexed; the indexer can delete the old domain once on first launch. |
| `RecipeCollections.prefix` | `recipecodex-recipe:` | A stored link prefix inside collections. Changing it breaks references in existing data; keep it, or migrate in the same commit (test data only, so a clean store is also fine). |
| Logger subsystems, `DispatchQueue` labels, the lookup `User-Agent` | `com.calebpietrafesa.RecipeCodex…`, `RecipeCodex/1.0` | Cosmetic; change for consistency. |
| Targets, products, module, folders, scheme, project file | `RecipeCodex`, `RecipeCodexShare`, `RecipeCodexWidgets`, `RecipeCodex.xcscheme`, `RecipeCodex.xcodeproj`, folders of the same names, `RecipeCodex/RecipeCodex.entitlements` | The largest mechanical change: Xcode's target rename plus folder moves and path fixes in the project file. The app module name changes with the target (nothing imports it). Verified by a clean build of both simulators and both devices. |

Fixture folders under `Docs/Fixtures/Private/` are gitignored and keep their names.

## 2. When and in what order

1. **The name**: Kitchen Codex, decided Oct 21, 2026 and recorded in 04 §5.1 ("Name"), 00 Vision's title and pitch, and the Phase 2 plan (between slices 5 and 6).
2. **Quiet checkout.** No slice session running in this checkout, Caleb's reserialized `project.pbxproj` either committed or discarded (`git checkout -- RecipeCodex.xcodeproj/project.pbxproj`; it is content-identical to HEAD), his `Docs/Design` work left alone. The coordinator does the rename, not a slice: the project file and entitlements are outside any slice's remit.
3. **Tier 1 first, one commit**: display name, strings, docs, then the GitHub rename and the remote URL. Build both simulators; the only behaviour change is the name on the Home Screen, in permission prompts and in copy.
4. **Tier 2 second, one commit series** (decided with the name): in the same project edit, add the "processing" background mode and a `BGTaskSchedulerPermittedIdentifiers` entry on the new bundle id (ux-notes row 92, authorized Oct 21, 2026), which needs an `Info.plist` file beside the generated keys. Then bundle ids and entitlements, `RecipeStore` constants, Spotlight domain, the project/target/folder renames. Then: `swift test` in every package (RecipeModel's constants are not a schema change; its 19 tests must still pass), `xcodebuild build` for both simulators from a fresh derived-data folder, delete the old app from both simulators and both devices, install the new one on both devices (`xcrun devicectl device install app`), confirm iCloud sync on the devices (the new container; simulators are signed out), the share extension saving a web recipe into the new shared store, the Tonight widget reading it, and Scan Cookbook with Gjelina end to end as the smoke test. Re-add the fixture photos to the simulators only if the new install cannot see them (Photos is per simulator, not per app, so they stay).
5. **Timing.** The right slot is the slice 5 → slice 6 boundary, once the review pass has landed, main is pushed and Caleb's slice 5 device check is done: the stores hold nothing but fixture recipes, the exit-book run (slice 8, Gjelina end to end) then happens under the final name and container, and no slice is writing. Tier 1 alone fits any boundary. Tier 2 "later" means after Phase 3 with a real library to move, so the realistic choice is this boundary or never.

## 3. Rollback

Each tier is its own commit (series) on `main`; `git revert` of the range restores the old name, and the old app, container and group are untouched until the old app is deleted from the devices, so nothing is lost by trying.
