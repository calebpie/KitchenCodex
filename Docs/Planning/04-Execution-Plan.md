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

- Enroll in the Apple Developer Program; create the App ID, iCloud container, App Group, AlarmKit and App Intents capabilities.
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
- Recipes tab with filters, collections, smart collections, favorites, recents; Search tab.
- PDF, text and Markdown export.
- iPad: adaptable tab bar/sidebar, three-column split, keyboard shortcuts, drag and drop into collections.
- Spotlight indexing of recipes.

Exit: you move your web recipes in and stop using the old app.

### Phase 2 — Capture (4 to 5 weeks)

Goal: the cookbook shelf and the whole-book flow.

- ISBN scan and book metadata; Books tab; book detail with sections and completeness.
- Page scan with quality gate; OCR → structured recipe; review screen with region assignment (tap on iPhone, Pencil lasso on iPad); multi-page stitching.
- Cross-reference detection and sub-recipe linking.
- Whole-book session: contents and index extraction → punchlist → capture loop → background queue → review queue.
- Photo cleanup and cover selection; PDF and photo-library import through the same pipeline.
- Measure extraction accuracy on the fixture set; iterate prompts and region heuristics until the review step averages under a minute per recipe.

Exit: one real cookbook fully captured.

### Phase 3 — Cook (3 weeks)

Goal: cooking one recipe is better in Codex than from the book.

- Cook mode: step view, ingredient highlighting, tappable times → AlarmKit timers, multiple named timers, keep-awake, knuckle mode.
- Now Cooking accessory; Live Activity for Dynamic Island, Lock Screen, StandBy, Watch Smart Stack.
- Hands-free: App Shortcuts (Next, Back, Timer, What's next), Action button setup, optional in-app voice phrases; Snippets for Siri results.
- Post-cook flow: rating, notes, photo, observed time and yield, location; cook log; "never cooked" state; learned times.
- Auto-metadata (dietary and allergen rules, course/cuisine/complexity suggestions), equipment extraction, practicality tags.
- Nutrition estimate via FoodData Central with offline subset.

Exit: a weeknight dinner cooked entirely from cook mode, hands-free at least once.

### Phase 4 — Plan and Shop (4 to 5 weeks)

Goal: a dinner party planned and shopped in the app, without the scheduler yet.

- Kitchen: tools, multiple kitchens, pantry, proficiency; guest profiles.
- Events; menu builder with slots, candidates, finalize; sub-recipe auto-add; balance panel and inline warnings; menu-wide scaling; doneness targets with temperature table.
- Shopping list: aggregation, normalization, pantry subtraction, sections, stops, check-off sync, share to text and Reminders.
- Menu card PDF; test-cook scheduling; calendar entries via EventKit.

Exit: your next dinner party is planned and shopped in Codex.

### Phase 5 — Schedule and Service (5 to 7 weeks)

Goal: the feature nobody else has.

- Step annotation UX (active/passive, waits, equipment, hold rule) with model-proposed defaults and the component knowledge base.
- Scheduler engine: task graph, constraints, backward list scheduling, host-presence objective, explanations. Property tests and scenario fixtures built from your real menus.
- Timeline editor across days with drag, snap, warnings, overload bars, reserve tasks, daily checklist on Cook.
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

## 5. Decisions needed from you

| Decision | Options | Recommendation |
|---|---|---|
| Minimum OS | iOS 27 only vs iOS 26 compatibility | iOS 27 only. You run it, and it unlocks image input, Dynamic Profiles, server models and the new App Intents APIs. |
| Heavy-reasoning model | Apple cloud (free with limits), Claude (billed, strongest), on-device only | Build the abstraction; default to Apple cloud once enrolled, with Claude as a setting. |
| Developer Program | Enroll now vs later | Now; CloudKit sync is Phase 0. |
| Capture device | iPhone camera vs iPad | iPhone 17 Pro for capture quality; iPad for the review and session UI. Support both. |
| Name and bundle ID | Recipe Codex vs other | Keep Recipe Codex; register the bundle ID in Phase 0. |
| Scope of first dinner test | Which event becomes the Phase 4/5 fixture | Pick one on the calendar now; the scheduler is built against it. |

## 6. Risks to the plan

| Risk | Signal | Response |
|---|---|---|
| Phase 2 accuracy stalls | Review step over 2 minutes per recipe after prompt iteration | Add the model's image-input second pass; simplify the region model; accept more manual assignment. |
| Scheduler over-engineering | Phase 5 slips past 7 weeks | Ship with manual annotation and a simpler greedy scheduler; keep the objective and constraints, drop local search. |
| CloudKit surprises | Sync divergence between devices | Freeze schema changes to one per phase with a migration test. |
| Apple API churn in 27.x | Deprecation warnings or behavior changes in point releases | Pin to shipped APIs; avoid beta-only features until GA. |
| Motivation dip in the long middle | Phases 4 and 5 are the longest | Each phase has a dinner at the end. |
