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
- Step photos: `RecipeImage.step` and the `stepPhoto` role; the importer downloads `HowToStep.image` and per-step photos; thumbnails on detail steps, tap to enlarge.
- Paprika/Mela import.
- Recipe detail with scaling, friendly rounding, unit toggle (US/metric), provenance. Temperatures shown in the preferred unit (°F or °C, Pantry → Profile) with the original kept; ingredient groups shown as sections.
- Recipes tab with the Recipes · Books view switch (Books empty until Phase 2), filters, collections, smart collections, favorites, recents; Pantry tab shell with the Profile pane (proficiency, units, intelligence); Search tab.
- PDF, text and Markdown export.
- iPad: adaptable tab bar/sidebar, three-column split, keyboard shortcuts, drag and drop into collections.
- Spotlight indexing of recipes.

Exit: you move your web recipes in and stop using the old app.

### Phase 2 — Capture (4 to 5 weeks)

Goal: the cookbook shelf and the whole-book flow.

- ISBN scan and book metadata; Books view inside Recipes; book detail with sections and completeness; Sources page capture into Pantry → Sources.
- Page scan with quality gate; OCR → structured recipe; review screen with region assignment (tap on iPhone, Pencil lasso on iPad); per-book layout confirmation and confidence scoring so review is forced only for the first recipe, new layouts and low-confidence results; multi-page stitching. A "Step photo" region in review attaches a printed process photo to the adjacent step.
- Cross-reference detection and sub-recipe linking. Also for a single web page whose ingredient and step groups line up (a main dish plus its pickles): the import preview offers "Split into N recipes", user-confirmed, creating linked component recipes the parent inlines at cook time.
- Reference capture: an article or technique chapter saved as a `Reference` (02 §4.2) with its source, linked to recipes and its book; the importer offers it when a page has Article markup and no recipe.
- Whole-book session: contents and index extraction → punchlist → capture loop → background queue → review queue.
- Photo cleanup and cover selection; PDF and photo-library import through the same pipeline.
- Measure extraction accuracy on the fixture set; iterate prompts and region heuristics until the review step averages under a minute per recipe.

Exit: one real cookbook fully captured.

### Phase 3 — Cook (3 weeks)

Goal: cooking one recipe is better in Codex than from the book.

- Cook mode: step view, ingredient highlighting, tappable times → AlarmKit timers, multiple named timers, keep-awake, kitchen theme toggle; standard control sizes throughout. Step photo under the step with tap to enlarge and a "Show me" phrase; a camera button saves your own photo of the step, shown beside the source's on later cooks.
- Now Cooking accessory; Live Activity for Dynamic Island, Lock Screen, StandBy, Watch Smart Stack.
- Hands-free: App Shortcuts (Next, Back, Timer, What's next), Action button setup, optional in-app voice phrases; Snippets for Siri results.
- Post-cook flow: rating, notes, photo, observed time and yield, location; cook log; "never cooked" state; learned times.
- Auto-metadata (dietary and allergen rules, course/cuisine/complexity suggestions), equipment extraction, practicality tags.
- Nutrition estimate via FoodData Central with offline subset.

Exit: a weeknight dinner cooked entirely from cook mode, hands-free at least once.

### Phase 4 — Plan and Shop (4 to 5 weeks)

Goal: a dinner party planned and shopped in the app, without the scheduler yet.

- Pantry tab: staples, tools, sources (frequented stores as shopping stops), cellar and bar, profile; no kitchens list (§5.1 "Kitchens"); guest profiles under Plan.
- Events; menu builder with slots, candidates, finalize; sub-recipe auto-add; balance panel and inline warnings; menu-wide scaling; doneness targets with temperature table; inputs for parameterized steps (bird weight for "20 mins per kg") asked when the recipe joins the menu; pairings per course (manual, from the cellar or typed) with "to buy" bottles on the shopping list.
- Shopping list: aggregation, normalization, pantry subtraction, sections, stops, check-off sync, share to text and Reminders.
- Menu card PDF; test-cook scheduling; calendar entries via EventKit.

Exit: your next dinner party is planned and shopped in Codex.

### Phase 5 — Schedule and Service (5 to 7 weeks)

Goal: the feature nobody else has.

- Step annotation UX (active/passive/lead, attention, waits, equipment, component, hold rule, formula durations) with deterministic phrase rules first, model-proposed defaults for the rest, and the component knowledge base. Steps stay as written; a step yields one or more tasks. Annotation test set from the saved pages: Barefoot Contessa's orzo (preheat, meanwhile, dressing component), Food.com's boeuf bourguignon (44 fine-grained steps, early preheat), Alison Roman's shallot pasta (stirring constantly), BBC Good Food's goose (per-kg formula with doneness), VICE's short ribs (three components on one page).
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
| Tabs | Recipes · Pantry · Plan · Cook · Search, in the order the work happens. Books is a view switch inside Recipes. Pantry replaces the profile button (the only one left is on Pantry's own hub, §5.1 "Pantry hub") and adds Sources and Cellar & Bar. Top toolbars are contextual: Add (+) and More (⋯). |
| Cook-mode controls | Standard HIG sizes with generous spacing; no enlarged "knuckle mode." |
| Scan review | Forced for the first recipe from each book and for any new page layout; afterwards surfaced only on low confidence. |
| Late menu swaps | Allowed after Finalize, with a preview of the schedule diff. |
| Kitchen theme | A toggle (cook mode More and Pantry → Profile), never automatic. |
| Wine pairings | Live on the menu, per course, with a non-alcoholic alternative; bottles from Cellar & Bar. |
| Heavy-reasoning model | Apple's Private Cloud Compute model by default; Claude available as a setting (Pantry → Profile → Intelligence). Extraction and classification stay on device. |
| Bundle ID | `com.calebpietrafesa.RecipeCodex` kept; extensions `.Share` and `.Widgets`; iCloud container `iCloud.com.calebpietrafesa.RecipeCodex`; App Group `group.com.calebpietrafesa.RecipeCodex`. |
| Portal registration | Xcode automatic signing with Caleb's Apple account; identifiers registered from a signed device build (see phase0-notes). |
| GitHub | Public repository. Scanned cookbook pages and any other copyrighted fixtures stay out of it. |
| Capture device | iPhone 17 Pro for capture quality; iPad for review and the scanning session UI. Both supported. |
| Event dates | Set while planning and editable until service starts (event status `inService`); fixed after that, with actual times recorded by the debrief. |
| Now Cooking accessory on iPad | Window only; the accessory is an iPhone surface. |
| Step granularity | Steps are stored as the source wrote them, never split or merged on import (Food.com's 44 one-sentence steps stay 44). Scheduling derives one or more annotated tasks per step; presentation problems are solved in cook mode. |
| Make-ahead | Whether a component can be made ahead is its hold rule (KnowledgeBase, by component type, overridable per recipe), not its position among the steps. |
| Parameterized steps | Steps like "20 mins per kg for medium-rare" carry a duration formula with inputs (weight, doneness); inputs are asked in Plan when the recipe joins a menu. A probe temperature outranks the time estimate for proteins. |
| Temperatures | Shown in the preferred unit (°F or °C, part of the units preference), original kept and reachable; "240C/fan 220C/gas 9" forms parsed. |
| Units preference | An amount written in the other system is shown in the preferred one, except metric weights (g, kg), which stay as written under the US preference so precise recipes keep their grams; spoons and counts stay as written. The US/Metric control on detail still converts every amount on tap. |
| Liquid ounces | Ounces of a liquid ingredient (juice, milk, cream, stock, water, oil, wine, syrup…) are always fluid ounces, never weight, whether or not the line says "fl"; a metric volume in parentheses ("5 ounces (142 ml)") confirms it. |
| Sub-recipes on one page | A web page or book spread that carries several components is offered as a split into linked recipes at import, always user-confirmed; the parent inlines them at cook time and each is searchable on its own. |
| iPad tabs | On iPad the five tabs show as the floating Liquid Glass tab bar at the top, never as a tab sidebar; each tab's own `NavigationSplitView` sidebar (Recipes: All Recipes, Smart Collections, Collections, Books) is the only left column. Replaces "top tab bar convertible to sidebar" (03 §4). Tracked in `Docs/Specs/ux-notes.md` row 1. |
| Pantry hub | The Pantry tab's root on iPhone is a hub, not a chip selector: an inset grouped list with one row per pane in the order **Staples · Tools · Cellar & Bar · Sources** (icon, name, a live summary such as "142 staples · 3 low" or "12 bottles"), each row pushing its pane, so Back returns to the hub. The first pane is renamed Staples so the hub does not list a row called Pantry. **Profile** is the trailing toolbar button on the hub (the standard account glyph), not a card or a row; it is the only profile button in the app. On iPad the same rows in the same order are the Pantry sidebar, with the Profile button in its toolbar. Tracked in `Docs/Specs/ux-notes.md` rows 2 and 15. |
| Search tab | Search stays the system search tab (`Tab(role: .search)`): on iPhone the separate Liquid Glass bubble beside the four tabs that morphs into the field, never a custom control. The search view is context-aware: a scope control under the field (All · Recipes · Pantry · Plan) defaults to the tab the cook came from, suggestions before typing come from that tab, and results use that tab's own cell style, so it reads as filtering the page while cross-library and natural-language search keep their dedicated surface (03 §3.18). Search inside one screen (Books, a Pantry pane, Sources) uses `.searchable` with the minimizing toolbar behavior. Tracked in `Docs/Specs/ux-notes.md` row 3. |
| Recipes filters | No always-visible filter chips. **Group By** is a submenu of More (⋯) beside View As and Sort By (None · Course · Book · Collection), persisted, default Course; a single resulting section hides its header. **Filter** is its own toolbar button next to More (the funnel symbol, tinted while active) whose menu has checkable sections (Course, several allowed; Cooked; Favorites; Collection; Book; Tag) and Clear Filters. While a filter is active, a row under the title shows one removable token per filter and Clear, scrolling with the content. On iPad the sidebar still selects a collection and that choice is not repeated as a chip. Tracked in `Docs/Specs/ux-notes.md` row 4. |
| Detail units | Recipe detail has no US · Metric control row. More (⋯) holds a **Units** submenu with a checkmark on the current choice: Preferred (the Profile setting, default), US, Metric, As Written; the choice is transient. Long-press on an ingredient line shows **As Written**, the line's original text, as temperatures already do. Tracked in `Docs/Specs/ux-notes.md` row 5. |
| Detail scale | The servings stepper row is gone. The Ingredients header reads "Ingredients · 4 servings ▾" ("× 1 ▾" for yield-only recipes); tapping it opens a popover with the stepper or multiplier and Reset, and while scaled it reads "6 servings · scaled from 4". On detail the scale is transient and never changes the stored recipe (servings change only in the editor). The same control's value belongs to the cook session in cook mode (Phase 3) and to the event slot in Plan (Phase 4), where it feeds the shopping list. Tracked in `Docs/Specs/ux-notes.md` row 6. |
| Kitchens | No Kitchens pane and no list of kitchens. The schema keeps one implicit Home `Kitchen`, created with the profile, as the parent of tools, staples, sources, bottles and events; it is never shown as a list. Cooking away from home is a property of the event (Phase 4): a **Where** field, Home or Away with a place name; Away raises a soft warning that the plan assumes your own tools and staples, and an on-arrival check sets ovens, burners and missing tools for that event only, widens the estimates and lists tools the menu needs as "bring or check". Cook history takes its place from the cook session. Tracked in `Docs/Specs/ux-notes.md` row 7. |
| Proficiency | Four tiers, Learning · Confident · Advanced · **Expert**, each with a sentence. Hands-on concurrency is derived from the tier (1 · 2 · 3 · 4) and never shown as a setting; `UserProfile.concurrencyLimit` becomes computed and the stored attribute is dropped from schema v1 in place. A per-event override ("extra hands tonight") belongs to the event in Plan (Phase 4). First run shows the same four tiers. Tracked in `Docs/Specs/ux-notes.md` row 8. |
| Review prompt | Low-confidence imports are surfaced in Recipes, not Cook: an inset "2 new recipes need a look ›" row at the top of the library while the count is above zero, opening the Needs a Look smart collection (the iPad sidebar item); Needs a Look is also a Filter entry. The per-recipe "Check N ingredients" banner on detail stays. Cook shows only what is cooking. Replaces 02 Flow A step 5. Tracked in `Docs/Specs/ux-notes.md` row 9. |
| Ingredient lines | On detail the amount is bold, the item is in the primary color, and preparation, notes and "(optional)" follow in the secondary color at the same size and weight; never italics. The parser splits a trailing parenthetical that is not a unit equivalent into a **note**, and a produce equivalent ("about 3 oranges", "from 2 lemons") also into an **equivalent** (count and produce item); `Ingredient` gains `note` and the equivalent fields in schema v1 in place, filled at import and on edit, shown in the editor's Reads As preview. Shopping (Phase 4) aggregates by produce where equivalents exist and uses KnowledgeBase yields where they don't ("5–6 oranges", with each use under it). A one-time re-read of saved "ounce" lines whose item is a liquid corrects recipes imported before the liquid-ounce fix. Tracked in `Docs/Specs/ux-notes.md` row 10. |
| Add menu | The Recipes Add (+) menu names the ways in, never the outcome: **Import from Web**, **Scan Page** (Phase 2), **From Photo** (Phase 2), **Paste Text** (Phase 2), **Enter Manually** (the editor), then a separator and **Import from Paprika or Mela…**, moved here from More. "New Recipe" is gone. Methods that have not shipped are hidden, not disabled. The Books view keeps Add Book and gains Scan Sources Page in Phase 2. ⌘N on iPad is Enter Manually. Tracked in `Docs/Specs/ux-notes.md` row 11. |
| Detail share | Recipe detail has no Share bubble. Share is an item in More (⋯) with the standard symbol and the same submenu (Recipe Codex file, text, print); the bottom bar holds only the prominent Cook button on iPhone and iPad. Share stays in the long-press menu and in Select mode. Tracked in `Docs/Specs/ux-notes.md` row 12. |
| Step photos | A step's thumbnail (4:3, about 120 pt tall, first photo with a count badge, tap to open the viewer) stays inline at the trailing edge and the step text wraps around it: narrow beside the thumbnail, full width below it. Rendered with TextKit 2 exclusion paths so Dynamic Type, selection, VoiceOver, temperature pills and As Written carry over; at accessibility type sizes the thumbnail moves above the text instead. Same on iPad. Cook mode (Phase 3) shows the step photo large on its own screen. Tracked in `Docs/Specs/ux-notes.md` row 13. |
| Floating headers | Only the navigation bar floats. On Recipes the Recipes · Books switch and the active-filter tokens are the first items of the scrolling content, never a pinned inset under the bar. On recipe detail the top edge uses the hard scroll-edge style, so the title bar has a defined edge over step text while the hero still extends under it at the top of the page. Tracked in `Docs/Specs/ux-notes.md` row 14. |

### 5.2 Still needed from you

| Decision | What it means | Recommendation |
|---|---|---|
| First dinner fixture | A real upcoming dinner (date, guest count, the actual menu you intend to cook) that becomes the scenario the scheduler is built and tested against in Phases 4 and 5: its recipes get step annotations first, and its timeline is the one judged against what really happened. | Name one when you have it on the calendar; needed by the start of Phase 4, not before. |
| Where References live | A third view in Recipes (Recipes · Books · References), or a section inside the Books view. Search covers them either way; the choice only affects the library's top-level switch and how a scanned chapter sits next to its book. | Third view in Recipes; decide when the first article is captured in Phase 2. |

## 6. Risks to the plan

| Risk | Signal | Response |
|---|---|---|
| Phase 2 accuracy stalls | Review step over 2 minutes per recipe after prompt iteration | Add the model's image-input second pass; simplify the region model; accept more manual assignment. |
| Scheduler over-engineering | Phase 5 slips past 7 weeks | Ship with manual annotation and a simpler greedy scheduler; keep the objective and constraints, drop local search. |
| CloudKit surprises | Sync divergence between devices | Freeze schema changes to one per phase with a migration test. |
| Apple API churn in 27.x | Deprecation warnings or behavior changes in point releases | Pin to shipped APIs; avoid beta-only features until GA. |
| Motivation dip in the long middle | Phases 4 and 5 are the longest | Each phase has a dinner at the end. |
