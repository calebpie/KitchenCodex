# Kitchen Codex — Feasibility Assessment

*Oct 17, 2026. Target platforms: iOS 27 and iPadOS 27 on iPhone 17 Pro and 13-inch iPad Pro; macOS 27 later. Your Mac already has Xcode 27.0 (27A266a) and the iOS 27.0 simulator runtime, so there is no toolchain gap.*

## 1. Bottom line

Everything in the proposal is buildable on Apple's current stack without a server of your own. About two-thirds of it is routine engineering on mature frameworks (SwiftUI, SwiftData, CloudKit, VisionKit, Vision, ActivityKit, AlarmKit, App Intents). The remaining third carries real uncertainty, in this order:

1. **OCR accuracy on cookbook typography and layout** is good but not perfect; the product must assume a review step and design it to be fast rather than hoping to skip it.
2. **The workback scheduler** is the hardest piece of original engineering and the piece no competitor has. It is a constraint-based scheduling problem, which is well understood, but the data it needs (active vs passive time, hold windows, dependencies) is not in any recipe. We will have to infer it, confirm it with you once per recipe, and build a small curated knowledge base of component behaviors.
3. **Apple's on-device model is useful but small.** It is the right tool for extraction, classification, normalization and short summaries. It is the wrong tool for conversational menu planning over a whole library. Apple's framework now lets us swap in a server model (Apple's own on Private Cloud Compute, or Claude) behind the same Swift API, so the architecture decision is easy; the cost and privacy decision is yours.

No part of the proposal requires you to run a backend. The optional grocery integrations are "hand off a list" rather than "place an order," which is all their APIs allow.

## 2. Apple technologies this app stands on

Verified against Apple's WWDC26 developer guide, the Foundation Models framework page, the HIG change log through Oct 13, 2026, and Apple's documentation, unless noted as secondary.

### 2.1 UI and app structure

| Need | Technology | Status and notes |
|---|---|---|
| App UI | SwiftUI (iOS 27) | Liquid Glass is mandatory for apps built with Xcode 27; the iOS 26 opt-out key no longer works. Standard components get the material for free. iOS 27 added reorderable containers, lazy prefetching stacks, and document-app improvements. |
| iPhone navigation | `TabView` with a trailing search tab, `TabBarMinimizeBehavior`, `tabViewBottomAccessory` | The bottom accessory is the Music MiniPlayer pattern; we use it for the active cook session. |
| iPad navigation | `TabView` with `.sidebarAdaptable`, `NavigationSplitView` | HIG recommends the tab bar first, converting to a sidebar for deeper structure. |
| iPad windowing and menu bar | iPadOS 26+ resizable windows; app menu bar via SwiftUI commands | Cook mode can open in its own window; keyboard shortcuts come with the commands. |
| Widgets | WidgetKit (configurable through App Intents in iOS 27) | "Tonight's plan," "Next event," timers. |
| Live Activities | ActivityKit | Dynamic Island, Lock Screen, StandBy, Mac menu bar via iPhone Mirroring, Apple Watch Smart Stack and CarPlay with no extra app. Max 8-hour sessions; limited-width layout guidance added Oct 2026. |
| Design kits | iOS/iPadOS 27 UI Kit for Figma (Sept 17, 2026), Icon Composer 2, SF Symbols 8 | The Figma link in your proposal is this kit. Figma blocks automated fetches, so open it in a browser. |

### 2.2 Data and sync

| Need | Technology | Status and notes |
|---|---|---|
| Persistence | SwiftData | iOS 26 added model inheritance; iOS 27 added `ResultsObserver` and `HistoryObserver` for change tracking outside views (useful for the Share Extension writing into the same store). |
| Sync | SwiftData + CloudKit private database | Constraints: all relationships optional, no `@Attribute(.unique)`, default values required. Photos go in `.externalStorage` and sync as assets. Household sharing later uses the CloudKit shared database, so model ownership now. |
| Shared store with extensions | App Group container | Share Extension and widgets need the same `ModelContainer` URL. |
| Local full-text and semantic search | Core Spotlight (`CSSearchableItem`, `CSUserQuery`), NaturalLanguage (`NLContextualEmbedding`) | Core Spotlight has supported semantic queries since iOS 18; WWDC26 added a session on LLM-driven search over Core Spotlight. |
| Background work | `BGProcessingTask` | OCR backlog from a book-scanning session finishes while the phone charges. |

### 2.3 Capture and vision

| Need | Technology | Status and notes |
|---|---|---|
| Page capture with edge detection and deskew | VisionKit `VNDocumentCameraViewController` | Multi-page, perspective corrected. Fast path for a first version. A custom AVFoundation camera is the upgrade path if we want live quality feedback. |
| ISBN barcode | VisionKit `DataScannerViewController` (EAN-13) | Live scanning UI, no code of our own. |
| Structured OCR | Vision `RecognizeDocumentsRequest` (iOS 26+) | Returns paragraphs, lines, lists and tables with structure; 26 languages. Lists map cleanly onto ingredient lists. One `DocumentObservation` per image. |
| Blurry or smudged capture warning | Vision `DetectLensSmudgeRequest` (iOS 26+) plus a Laplacian-variance sharpness score | Smudge detection returns a confidence; Apple's sample uses ~0.9 as the threshold. Motion blur is better caught by the sharpness score. |
| Image quality scoring | Vision `CalculateImageAestheticScoresRequest` | Useful for picking the best of several cover-photo candidates. |
| Photo cleanup | Core Image (`autoAdjustmentFilters`, `CIPerspectiveCorrection`, sharpen), Vision rectangle detection and foreground mask | Deskew, crop, levels and sharpen are reliable. Moiré from halftone printing and gloss glare are not solvable in software; the UI should set that expectation and prefer your own dish photo when you have one. |
| Live Text everywhere | VisionKit `ImageAnalyzer` | Lets ingredients in a photo be selected and copied. |

### 2.4 Intelligence

| Need | Technology | Status and notes |
|---|---|---|
| Extraction, classification, normalization, short summaries | Foundation Models framework, on-device model, guided generation (`@Generable`) | Works offline, no cost, private. **Context window is 4,096 tokens per session** (Apple technote TN3193; iOS 26.4 added `contextSize` and `tokenCount(for:)` so we never hard-code it). Verified for iOS 26; no source confirms a change in iOS 27. Design every on-device prompt to fit a single recipe or a chunk. |
| Image input to the model | Foundation Models (iOS 27) multimodal prompts; built-in Vision `OCRTool` and `BarcodeReaderTool` | Lets the model read a page image directly as a second opinion to Vision OCR. |
| Tool calling | Foundation Models `Tool`, `GenerationOptions.toolCallingMode` (iOS 27, secondary source) | The menu builder calls `searchRecipes`, `getRecipeSummary`, `checkGuestRestrictions` tools instead of being handed the library. |
| Switching models and instructions mid-session | Dynamic Profiles (iOS 27) | "Planner" and "critic" profiles share one transcript. |
| Larger model, still private | Apple Foundation Models on Private Cloud Compute | Free with no cloud API cost for App Store Small Business Program members under 2M first-time downloads, subject to daily usage limits; paid expansion promised later. Requires enrolling in the paid developer program and the Small Business Program. |
| Frontier model | Claude via `ClaudeForFoundationModels` (Anthropic, Apache 2.0) | Same `LanguageModelSession` API; supports streaming, guided generation, tool calling, images, server-side web search. Auth via App Attest (no key in the app; bills your Anthropic workspace), API key for simulator only, or your own proxy. Requires iOS 27 and a physical device for App Attest. |
| Prompt testing | Evaluations framework, `fm` CLI on macOS 27, AppIntentsTesting | Lets us regression-test extraction prompts against a fixture set of scanned pages. |
| Caveat from your own testing | Oct 8, 2026 probe of the on-device model for another project | You found it weak on receipts and voice-derived text and only adequate on structured lines; Vision OCR beat it. That matches Apple's positioning. Plan: Vision does the reading, the model does the structuring, and anything conversational goes to a bigger model. |

### 2.5 Siri, hands-free and system integration

| Need | Technology | Status and notes |
|---|---|---|
| Voice control of cook mode | App Intents + App Shortcuts ("Next step," "Start a timer for the roast," "What's next") | iOS 27 Siri AI can act on app intents and entities from natural language without preset phrases when the app adopts schemas; there is no cooking schema domain, so we use App Shortcuts with phrase variants. Secondary sources describe multi-turn follow-ups in iOS 27; treat as a bonus. |
| Recipes findable by Siri and Spotlight | `IndexedEntity`, `EntityStringQuery` | "Show my braises" or "that vegetable dish I made in Seattle" become semantic index queries with cook-history properties. |
| On-screen awareness | View annotations (`.appEntityIdentifier`), `NSUserActivity` | "Add this to Saturday's menu" while a recipe is on screen. |
| Result and confirmation UI in Siri | Snippets (new HIG page, June 2026) | A "Next step" result snippet shows the step without opening the app. |
| In-app wake phrase | Speech framework `SpeechAnalyzer` / `DictationTranscriber` (iOS 26+) | On-device, no custom vocabulary yet. For a short command grammar ("next," "back," "timer ten minutes") that is fine. Pestle ships exactly this. |
| Physical control | Action button (iPhone 17 Pro) → App Shortcut; Camera Control not usable for this | One press advances the step with a dirty hand. |
| Timers that break through Silent and Focus | AlarmKit (iOS 26+) with a countdown Live Activity | Apple names cooking timers as the intended use. Requires `NSAlarmKitUsageDescription` and authorization. |
| Where you cooked | CoreLocation one-shot at cook start, reverse geocoded to city | Powers "in Seattle" search. |
| Calendar and reminders | EventKit | Put the event and test-cook on the calendar; export the shopping list to Reminders. |
| Visual Intelligence | App Intents `IntentValueQuery` with `SemanticContentDescriptor` | Point the camera at a dish or a cookbook page and get "you have this recipe." A later delight. |

### 2.6 External services (no backend required)

| Need | Service | Status and notes |
|---|---|---|
| Book metadata and covers | Open Library (keyless, covers by ISBN in S/M/L) with Google Books (free key) as fallback | Coverage is good for trade cookbooks; allow manual entry. |
| Nutrition | USDA FoodData Central API | Free key, 1,000 requests/hour, public domain (CC0). Bundle a compact subset of Foundation Foods for offline use. The hard part is matching "1 large shallot, minced" to a food entry; the on-device model normalizes the ingredient name first. |
| Grocery | Instacart Developer Platform (create shopping list / recipe page links); Kroger Public API (OAuth, add to cart) | Neither offers checkout; both end in their app. Whole Foods / Amazon has no public cart API. Instacart does not serve Whole Foods. Treat as optional phase 7. |
| Probe thermometer | Combustion Inc. `combustion-ios-ble` (Swift Package, MIT) | Open BLE protocol, live temps, prediction. MEATER and ThermoWorks have no public APIs. |
| Food safety reference | USDA FSIS safe minimum internal temperature chart | Encode as data: poultry 165°F; ground meats 160°F; whole cuts of beef, pork, lamb, veal 145°F with a 3-minute rest; fish 145°F; eggs 160°F; reheated leftovers 165°F. |

## 3. Feature-by-feature feasibility

Scale: **High** = standard engineering on mature APIs; **Medium** = works but needs iteration or has accuracy limits; **Hard** = original engineering or research-grade uncertainty.

### Capture

| Feature | Rating | Approach | Risks and mitigations |
|---|---|---|---|
| Share-sheet import | High | Share Extension receives the URL and, from Safari, the page DOM via a JavaScript preprocessing file. Parse schema.org Recipe JSON-LD (NYT Cooking, Serious Eats, Bon Appétit and most food blogs publish it). If absent, render in `WKWebView` and ask the on-device model for a `@Generable Recipe` from the visible text. | Paywalled pages from the NYT Cooking *app* share only a URL; fetching it may hit the paywall. Mitigation: an in-app browser with your login (Mela's approach) and a "Import from this page" button. |
| Manual entry | High | Form with structured ingredient rows and step editor; blanks allowed. | None. |
| Single page scan | Medium-High | VisionKit document camera → `RecognizeDocumentsRequest` → paragraphs/lists → model structures into `Recipe` → review screen with block assignment. Quality gate rejects smudged or soft captures before OCR. | Cookbook design: drop caps, two-column layouts, fraction glyphs (½ vs 1/2), hyphenation, ingredients set in a sidebar, instructions continuing on the next page. Mitigations: feed Vision's paragraph geometry to the model; normalize fractions; always offer "add next page." |
| Sub-recipe references | Medium | Regex for "see page N," "(page N)," "recipe follows," plus the model flagging ingredients that are themselves recipes ("pasta dough," "pie crust"). Link to an existing record or create a stub on the book's punchlist. | False positives; keep it a suggestion you confirm. |
| ISBN and book metadata | High | `DataScannerViewController` → Open Library → Google Books fallback → manual. | Older or small-press books missing; manual entry path. |
| Whole-book session | Medium-High (engineering), Medium (accuracy) | ISBN → scan contents/index pages → model extracts `[title, page]` → punchlist → page-by-page capture with the current recipe pre-selected by page number → background OCR queue → review queue. | Battery and heat on a 300-page book; process in background, show progress. Legal: fine for personal use; a marketed version must keep scanned content private to the account and never share it. |
| Photo cleanup | Medium | Deskew + crop + auto levels + sharpen; subject lift for plated-food photos on busy pages. | Halftone moiré and glare are not fixable; prefer your own photo. |
| Units and scaling | High | Ingredient quantities stored as rationals, `Measurement` for conversions, density table for volume↔weight, rounding rules to friendly fractions. | Scaling baked goods is non-linear; add scaling warnings (leavening, pan size, time). |
| Provenance and comment summaries | High / Medium | Provenance trivial. Comments require rendering the page (client-side loaded), extracting comment text, chunking to fit 4k tokens, summarizing with guided output ("tips," "common substitutions," "warnings"). | Every site differs; start with the three or four you actually use. |

### Understanding

| Feature | Rating | Approach | Risks and mitigations |
|---|---|---|---|
| Auto metadata | High | Allergens and dietary flags from an ingredient keyword taxonomy (deterministic, safety-relevant). Course, cuisine, complexity via on-device model with enum-constrained guided generation. All editable. | Model occasionally wrong on cuisine; show as suggestions. |
| Nutrition | Medium | Normalize ingredient → FDC search → portion weight → per-serving totals. Cache results. Label "Estimate." | Matching quality; volume→weight for odd items. Allow manual overrides. |
| Versioning | High | `RecipeVersion` records; current pointer; cook notes attach to the version cooked. | None. |
| Inferred practicality tags | High | Rules over equipment, total time, step count, passive time. | None. |
| Natural-language cook-history search | Medium | Model converts the phrase into a `@Generable SearchQuery` (keywords, course, cuisine, place, date range, cooked-state), then SwiftData predicate + Spotlight semantic ranking. | Ambiguity; show the interpreted filters as removable tokens so you can correct them (HIG scope bars and tokens). |

### Planning

| Feature | Rating | Approach | Risks and mitigations |
|---|---|---|---|
| Events, menus, slots, candidates | High | Straight data modeling. | None. |
| Balance and warnings | High | Rules: course coverage, protein/veg/starch balance, servings vs guests, complexity load, never-cooked, duplicate techniques, oven contention. Model-written explanations later. | Keep rules transparent and editable. |
| Doneness → temperature | High | Table: protein × cut × doneness → target, pull temp (target minus carryover by cut thickness), rest time; USDA minimum floor. | Carryover varies with oven temp and mass; expose the assumption. |
| Shopping aggregation and grouping | High | Ingredient normalization (model-assisted, cached), unit conversion, pantry subtraction, store-section taxonomy that learns from your edits, stop assignment by category with overrides. | Normalization misses; make merging items a two-tap action. |
| Conversational menu builder | Medium | Tool-calling session: model gets a compact library index through tools, proposes a `@Generable MenuProposal` with reasons, you refine in chat. Dynamic Profiles switch between planner and critic. Model is a runtime choice: on-device (limited), Apple PCC (free, limits), Claude (billed). | On-device model will underperform here. Treat on-device as the fallback, not the default. |
| Grocery APIs | Medium, optional | Instacart link handoff; Kroger OAuth cart add. | Store coverage; no checkout anywhere. |

### Scheduling and cooking

| Feature | Rating | Approach | Risks and mitigations |
|---|---|---|---|
| Task graph from recipes | Medium | Each step becomes a task with: active duration, passive duration, dependencies, equipment, min/max wait before the next step ("rest 24h in fridge" = min 24h; "serve immediately" = max 3 min), hold rules (component type, max hold, quality decay). Model proposes; you confirm once per recipe; curated knowledge base supplies defaults by component type. | This is the data problem. Mitigation: start with your own recipes, build the knowledge base from real menus, keep the confirm step light. |
| Scheduler | Hard (original), feasible | Backward list scheduling from serve time with resource constraints (ovens, burners, your concurrency limit from proficiency), precedence, time windows, and an objective that minimizes post-arrival active time and penalizes hot items finished early. Heuristic (critical-path priority + local search) rather than exact; menus are small (tens to low hundreds of tasks). Validate edits by re-running and diffing. | Explainability: every warning must name the constraint it violates. Deterministic engine, fully unit-testable. |
| Cook mode (single recipe) | High | Step view, ingredient highlighting, tap-a-time-to-start-timer, AlarmKit timers, Live Activity, idle timer disabled, large targets. | None beyond polish. |
| Service mode (menu) | Medium | Scheduler output rendered as "now / next / later" across recipes; lateness computed against guest arrival and seating; replan on demand from the current time. | UX complexity; wireframes in doc 03 address it. |
| Hands-free | High / Medium | Siri App Shortcuts, Action button, well-spaced standard controls: High. In-app wake-word listening via `SpeechAnalyzer`: Medium (microphone indicator, battery, false triggers). | Start with Siri + Action button + well-spaced standard buttons; add always-listening as an option. |
| Temperature guidance | Medium | Newton-style heating model per protein and cut, fit to the readings you enter (two readings give a rate), to estimate minutes to pull temp; prompts to re-check at the estimate. Probe integration later replaces manual readings. | Oven and shape variance; present as "about 12 more minutes," never precise. |
| Pot size suggestion | High | Sum ingredient volumes (density table) plus headspace rules; pick from your vessels. | Approximate; fine. |
| Sync, export, Mac | High | CloudKit; `ImageRenderer` → PDF; SwiftUI multiplatform or Mac Catalyst for Mac. | CloudKit schema discipline. |

## 4. Where your proposal should bend

- **"Automatically fill cook time once cooked."** Yes, but record *observed* time separately from *stated* time and show both; a slow first attempt should not overwrite the book.
- **"OCR should create a clean text version."** Vision does the reading; the model does the structuring. Keep the original page image attached forever so you can check the source.
- **"Scan the index to create a punchlist."** Many cookbooks have unhelpful indexes (by ingredient). The table of contents and chapter openers are the better punchlist source; offer both.
- **"Clean up and enhance photos from the book."** Expect deskew, crop and color correction, not a studio image. Your own plated photo will beat it every time; the post-cook flow makes taking one a one-tap step.
- **"Scrape comments."** Worth doing for the two or three sites you use, late, and labeled as a reader summary.
- **"Grocery store APIs."** Build the list and hand off. No API lets an app check out on your behalf.
- **"Apple foundation models for the menu experience."** Use Apple's framework, but plan for the model behind it to be Apple's cloud model or Claude. The on-device model is for extraction, not conversation.

## 5. Prerequisites and accounts

| Item | Why | Cost |
|---|---|---|
| Apple Developer Program | CloudKit, App Groups, AlarmKit, App Intents on device beyond 7-day signing, TestFlight | $99/yr |
| App Store Small Business Program enrollment | Unlocks Apple's Private Cloud Compute model at no API cost | Free once in the program |
| Anthropic console app registration (optional) | Claude via App Attest for the menu builder | Usage billing; a single user's use is small |
| data.gov API key | USDA FoodData Central | Free |
| Google Cloud API key (optional) | Google Books fallback | Free tier |
| GitHub repository | Version control; also the precondition for Claude Code cloud sessions | Free |

## 6. Principal risks

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| OCR structuring quality on real cookbooks | High | Medium | Design review UI for speed; keep page images; measure on a 30-page fixture set from your own shelf before building the whole-book flow. |
| Scheduler data quality (durations, hold rules) | High | High | Confirm-once-per-recipe UX; knowledge base; start with your actual next dinner as the test case. |
| On-device model limits (4k context, quality) | Certain | Medium | Chunking; tool calling; model abstraction so PCC or Claude slot in. |
| SwiftData + CloudKit edge cases (migrations, relationship rules) | Medium | Medium | Lock schema rules early; test on two devices from week one; avoid unique constraints. |
| Apple Intelligence availability (region, settings, device heat) | Low for you | Low | Fall back to rules; HIG requires a non-AI path anyway. |
| Battery and thermal during book scans | Medium | Low | Background processing, batch OCR, pause when hot. |
| Copyright if marketed | Low now | High later | Scanned content private per account; sharing limited to recipes you authored or links back to sources. |
| Scope | Certain | High | The phased plan in doc 04 ships a Paprika replacement first, the scanner second, and the scheduler only once the library is real. |

## Sources

Apple: [WWDC26 iOS guide](https://developer.apple.com/wwdc26/guides/ios/) · [Newsroom, June 8 2026](https://www.apple.com/newsroom/2026/06/apple-aids-app-development-with-new-intelligence-frameworks-and-advanced-tools/) · [Foundation Models framework](https://developer.apple.com/foundation-models-framework/) · [TN3193 context window](https://developer.apple.com/documentation/technotes/tn3193-managing-the-on-device-foundation-model-s-context-window) · [RecognizeDocumentsRequest](https://developer.apple.com/documentation/vision/recognizedocumentsrequest) · [DetectLensSmudgeRequest](https://developer.apple.com/documentation/vision/detectlenssmudgerequest) · [AlarmKit](https://developer.apple.com/documentation/alarmkit/scheduling-an-alarm-with-alarmkit) · [WWDC26 240: App Schemas](https://developer.apple.com/videos/play/wwdc2026/240/) · [Visual Intelligence schema](https://developer.apple.com/documentation/appintents/app-schema-domain-visual-intelligence) · [HIG What's New](https://developer.apple.com/design/whats-new/) · HIG pages: Generative AI, Snippets, Siri, Live Activities, Tab bars, Toolbars, Sidebars, Materials, Layout, Searching, Multitasking.
Third party: [ClaudeForFoundationModels](https://github.com/anthropics/ClaudeForFoundationModels) · [Liquid Glass in iOS 27 (MacRumors)](https://www.macrumors.com/2026/06/10/how-liquid-glass-is-changing-in-ios-27/) · [SwiftData 27 (InfoQ)](https://infoq.com/news/2026/07/swiftdata-27-whats-new/) · [Instacart Developer Platform](https://docs.instacart.com/developer_platform_api/) · [Kroger API summary](https://jentic.com/apis/kroger) · [USDA FoodData Central API](https://fdc.nal.usda.gov/api-guide) · [Combustion iOS BLE SDK](https://github.com/combustion-inc/combustion-ios-ble) · [SpeechAnalyzer guide](https://antongubarenko.substack.com/p/ios-26-speechanalyzer-guide) · [Recipe app survey (cooklang.org)](https://cooklang.org/blog/48-best-recipe-management-software/) · [Pestle review (MacStories)](https://www.macstories.net/reviews/pestle-1-2-the-macstories-review/) · [Crouton review](https://iphonesoft.fr/2026/05/24/crouton-app-iphone-parfaite-gerer-recettes-cuisine) · [Mela review](https://toolsandtoys.net/mela-recipe-app-silvio-rizzi/).
