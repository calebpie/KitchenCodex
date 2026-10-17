# Recipe Codex — Execution and Delivery Plan

*Oct 17, 2026. A phased plan that ships something useful early, builds the library before the planner, and leaves the hardest original engineering (the scheduler) for when there is real data to schedule.*

## 1. Approach

- **One developer plus Claude Code.** Estimates assume part-time evenings and weekends, roughly 10 to 15 focused hours a week, and are given as calendar ranges. Full-time would roughly halve them.
- **Ship to your own devices every phase.** Each phase ends with a TestFlight build on the iPhone and iPad and a real-world test (a recipe imported, a book scanned, a dinner cooked).
- **Deterministic first, model second.** Every feature works with rules before a model improves it. This matches the HIG requirement for a non-AI path and keeps the app usable when Apple Intelligence is unavailable or slow.
- **Design before code for the three novel screens**: the scanning session, the schedule timeline, and service mode. Everything else follows system components and needs little custom design.

## 2. Phase plan

### Phase 0 — Foundations (1 to 2 weeks)

Goal: a project that builds, syncs, and tests, with the design system decided.

- Apple Developer Program: enrolled (individual team `BXSW6MRVTR`, set in the project Oct 17, 2026). Still to do: register the App ID and App Group, create the iCloud container, add the AlarmKit and App Intents capabilities.
- Create the Xcode 27 workspace: app target, Share Extension, Widget/Live Activity extension, and the Swift packages listed in doc 02 (RecipeModel, Units, Capture, Intelligence, KnowledgeBase, Scheduler, Nutrition).
- Initialize git; push to a private GitHub repository; install the Claude GitHub App so cloud sessions can run the pure-Swift packages later.
- SwiftData schema v1 with CloudKit rules enforced by a test. Prove sync between iPhone and iPad with a throwaway record.
- Design tokens: app accent, kitchen high-contrast theme, type scale, iconography from SF Symbols 8. Icon Composer 2 for the layered app icon.
- Test strategy: Swift Testing for packages; a fixture set of 30 cookbook pages photographed from your shelf and 20 saved HTML recipe pages; Evaluations framework harness for prompts.

Exit: empty app with tabs, syncing store, CI green.

### Phase 1 — Library (3 to 4 weeks)

Goal: replaces Paprika for web and manual recipes.

- Recipe, version, ingredient and step models; manual entry; structured ingredient parser.
- Share Extension with JSON-LD parsing and on-device model fallback; in-app browser import.
- Paprika/Mela import.
- Recipe detail with scaling, friendly rounding, unit toggle (US/metric), provenance.
- Recipes tab with the Recipes · Books view switch (Books empty until Phase 2), filters, collections, smart collections, favorites, recents; Pantry tab shell with the Profile pane (proficiency, units, intelligence); Search tab.
- PDF, text and Markdown export.
- iPad: adaptable tab bar/sidebar, three-column split, keyboard shortcuts, drag and drop into collections.
- Spotlight indexing of recipes.

Exit: you move your web recipes in and stop using the old app.

### Phase 2 — Capture (4 to 5 weeks)

Goal: the cookbook shelf and the whole-book flow.

- ISBN scan and book metadata; Books view inside Recipes; book detail with sections and completeness; Sources page capture into Pantry → Sources.
- Page scan with quality gate; OCR → structured recipe; review screen with region assignment (tap on iPhone, Pencil lasso on iPad); per-book layout confirmation and confidence scoring so review is forced only for the first recipe, new layouts and low-confidence results; multi-page stitching.
- Cross-reference detection and sub-recipe linking.
- Whole-book session: contents and index extraction → punchlist → capture loop → background queue → review queue.
- Photo cleanup and cover selection; PDF and photo-library import through the same pipeline.
- Measure extraction accuracy on the fixture set; iterate prompts and region heuristics until the review step averages under a minute per recipe.

Exit: one real cookbook fully captured.

### Phase 3 — Cook (3 weeks)

Goal: cooking one recipe is better in Codex than from the book.

- Cook mode: step view, ingredient highlighting, tappable times → AlarmKit timers, multiple named timers, keep-awake, kitchen theme toggle; standard control sizes throughout.
- Now Cooking accessory; Live Activity for Dynamic Island, Lock Screen, StandBy, Watch Smart Stack.
- Hands-free: App Shortcuts (Next, Back, Timer, What's next), Action button setup, optional in-app voice phrases; Snippets for Siri results.
- Post-cook flow: rating, notes, photo, observed time and yield, location; cook log; "never cooked" state; learned times.
- Auto-metadata (dietary and allergen rules, course/cuisine/complexity suggestions), equipment extraction, practicality tags.
- Nutrition estimate via FoodData Central with offline subset.

Exit: a weeknight dinner cooked entirely from cook mode, hands-free at least once.

### Phase 4 — Plan and Shop (4 to 5 weeks)

Goal: a dinner party planned and shopped in the app, without the scheduler yet.

- Pantry tab: pantry, tools, sources (frequented stores as shopping stops), cellar and bar, multiple kitchens, profile; guest profiles under Plan.
- Events; menu builder with slots, candidates, finalize; sub-recipe auto-add; balance panel and inline warnings; menu-wide scaling; doneness targets with temperature table; pairings per course (manual, from the cellar or typed) with "to buy" bottles on the shopping list.
- Shopping list: aggregation, normalization, pantry subtraction, sections, stops, check-off sync, share to text and Reminders.
- Menu card PDF; test-cook scheduling; calendar entries via EventKit.

Exit: your next dinner party is planned and shopped in Codex.

### Phase 5 — Schedule and Service (5 to 7 weeks)

Goal: the feature nobody else has.

- Step annotation UX (active/passive, waits, equipment, hold rule) with model-proposed defaults and the component knowledge base.
- Scheduler engine: task graph, constraints, backward list scheduling, host-presence objective, explanations. Property tests and scenario fixtures built from your real menus.
- Timeline editor across days with drag, snap, warnings, overload bars, reserve tasks, daily checklist on Cook; schedule diff preview for replans and late menu swaps.
- Service mode: Now/Next/Watch lanes, lateness tracking, replan, proactive checks, temperature guidance from readings, food-safety minimums, pot-size suggestions, plating and hold reminders, debrief.
- Live Activity for service mode.

Exit: a full multi-course dinner run from service mode, with the plan's timing judged against what actually happened.

### Phase 6 — Intelligence (3 to 4 weeks)

Goal: the conversational layer, on top of a library that is now real.

- Model selection setting (on-device, Apple cloud, Claude) behind the Intelligence package; App Attest registration for Claude; Small Business Program enrollment for Apple's cloud model.
- Ask Codex menu builder with tool calling and Dynamic Profiles; wine and drink pairing notes.
- Natural-language search with interpreted-filter tokens; `IndexedEntity` for Siri semantic search; on-screen awareness annotations.
- Reader-comment summaries for your two or three main sites.
- Evaluations suite for every prompt in the app.

Exit: "Plan a cozy fall dinner for six, one vegetarian, nothing I haven't cooked" returns a menu you'd actually serve.

### Phase 7 — Platforms and market (ongoing)

- Mac app (SwiftUI multiplatform), iPad-as-display with iPhone remote, household sharing via CloudKit shared database, Combustion probe integration, Instacart and Kroger handoff, Visual Intelligence, Paprika/Cooklang export, technique glossary.
- Market readiness if you choose it: onboarding, App Store assets, privacy nutrition label, copyright policy for scanned content, accessibility audit, localization scaffolding.

## 3. Timeline at a glance

| Phase | Calendar (part-time) | Cumulative |
|---|---|---|
| 0 Foundations | 1 to 2 weeks | ~2 weeks |
| 1 Library | 3 to 4 weeks | ~6 weeks |
| 2 Capture | 4 to 5 weeks | ~11 weeks |
| 3 Cook | 3 weeks | ~14 weeks |
| 4 Plan and Shop | 4 to 5 weeks | ~19 weeks |
| 5 Schedule and Service | 5 to 7 weeks | ~26 weeks |
| 6 Intelligence | 3 to 4 weeks | ~30 weeks |
| 7 Platforms and market | ongoing | |

Roughly seven months part-time to the full proposal, with a usable library at six weeks and a usable party planner at about four and a half months.

## 4. How we will work

- **Specs before features.** Each phase starts with a short spec in `Docs/Specs/` (screens, data changes, acceptance checks), reviewed by you before code.
- **Fixtures are the contract.** Scanned-page and HTML fixtures live in the repo; extraction changes must not regress them.
- **Two devices from day one.** Sync bugs are cheapest early.
- **Dogfood events.** Phases 4, 5 and 6 each end with a real dinner. The debrief feeds the backlog.
- **Cloud sessions where they fit.** Units, Scheduler, KnowledgeBase and Nutrition are pure Swift and testable on Linux; after Phase 0 pushes to GitHub, their test-heavy work can run in Claude Code cloud sessions in parallel with local UI work. Anything touching Xcode, the simulator or devices stays local.

## 5. Decisions

### 5.1 Decided (Oct 17, 2026)

| Decision | Outcome |
|---|---|
| Minimum OS | iOS 27 only. |
| Developer Program | Enrolled; individual team `BXSW6MRVTR`, set as the development team for all three targets. |
| Tabs | Recipes · Pantry · Plan · Cook · Search, in the order the work happens. Books is a view switch inside Recipes. Pantry replaces the profile button and adds Sources and Cellar & Bar. Top toolbars are contextual: Add (+) and More (⋯). |
| Cook-mode controls | Standard HIG sizes with generous spacing; no enlarged "knuckle mode." |
| Scan review | Forced for the first recipe from each book and for any new page layout; afterwards surfaced only on low confidence. |
| Late menu swaps | Allowed after Finalize, with a preview of the schedule diff. |
| Kitchen theme | A toggle (cook mode More and Pantry → Profile), never automatic. |
| Wine pairings | Live on the menu, per course, with a non-alcoholic alternative; bottles from Cellar & Bar. |

### 5.2 Still needed from you

| Decision | Options | Recommendation |
|---|---|---|
| Heavy-reasoning model | Apple cloud (free with limits), Claude (billed, strongest), on-device only | Build the abstraction; default to Apple cloud, with Claude as a setting. Can wait until Phase 6; `ModelTier` already has all three. |
| Bundle ID | Keep `com.calebpietrafesa.RecipeCodex` (and `iCloud.com.calebpietrafesa.RecipeCodex`) vs another | Keep it; it only has to be registered once, before the first device build. |
| Portal registration | Let Xcode's automatic signing create the App ID, App Group and iCloud container, or create them yourself in the developer portal | Automatic signing with your Apple account signed in to Xcode; one device build does it. Can be run from here on your say-so. |
| GitHub remote | Private repository now vs later | Now; cloud sessions and backups both need it. Needs your GitHub login (`gh auth login`) or a repository you create and share the URL of. |
| Capture device | iPhone camera vs iPad | iPhone 17 Pro for capture quality; iPad for the review and session UI. Support both. Assumed unless you object. |
| First dinner fixture | Which event becomes the Phase 4/5 scheduler fixture | Pick one on the calendar; the scheduler is built against it. Needed by Phase 4. |
| Now Cooking accessory on iPad | Accessory above the tab bar vs the dedicated cook-mode window only | Window only; revisit after Phase 3 (03 §7). |

## 6. Risks to the plan

| Risk | Signal | Response |
|---|---|---|
| Phase 2 accuracy stalls | Review step over 2 minutes per recipe after prompt iteration | Add the model's image-input second pass; simplify the region model; accept more manual assignment. |
| Scheduler over-engineering | Phase 5 slips past 7 weeks | Ship with manual annotation and a simpler greedy scheduler; keep the objective and constraints, drop local search. |
| CloudKit surprises | Sync divergence between devices | Freeze schema changes to one per phase with a migration test. |
| Apple API churn in 27.x | Deprecation warnings or behavior changes in point releases | Pin to shipped APIs; avoid beta-only features until GA. |
| Motivation dip in the long middle | Phases 4 and 5 are the longest | Each phase has a dinner at the end. |
