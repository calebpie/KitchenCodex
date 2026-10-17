# Recipe Codex — Product Vision and Feature Map

*Prepared Oct 17, 2026 from `Docs/Input/InitialProposal.md`, Apple's developer and design documentation as of iOS 27 / Xcode 27, and a survey of the recipe-app market. Companion documents: [01-Feasibility](01-Feasibility.md), [02-Flows-and-Architecture](02-Flows-and-Architecture.md), [03-UX-Proposals](03-UX-Proposals.md), [04-Execution-Plan](04-Execution-Plan.md), and the rendered wireframes in [wireframes.html](wireframes.html).*

## 1. The one-sentence pitch

Recipe Codex is a personal kitchen system for a serious home cook who hosts: it captures every recipe you own (cookbooks, web, apps, your own), understands them well enough to plan a multi-course menu, and then runs the event with you so the cooking looks effortless to your guests.

## 2. What makes it different

Every recipe manager on the market stops at "store, scale, shop, show one recipe at a time." Paprika, Mela and Crouton all do that well. None of them understands a *menu* as a unit of work, and none of them plans *time*. The dinner-party timing apps that do exist (CookingTimer, Dinner Ninja, MultiCook Timer+) are dumb countdown stackers with no recipe knowledge.

Recipe Codex's wedge is the gap between those two categories:

1. **Whole-cookbook capture.** Scan an ISBN, scan the index, then photograph pages; the app builds the book's table of contents and tracks which recipes are captured. Mela and Crouton scan a page; nobody owns the book.
2. **Menu as the unit.** Events, guests, dietary needs, course slots with candidates, sub-recipe auto-inclusion, balance checks, and scaling across the whole menu.
3. **The workback schedule.** A dependency-aware, resource-aware plan across days that knows a 24-hour fridge rest can't happen at noon the day of, that pasta can't be cooked an hour early, and that the kitchen should be clean before the doorbell rings.
4. **Service mode.** Cook mode that spans recipes, tracks lateness against guest arrival, manages timers and temperature checks, and is operable by voice, Action button, or a knuckle.
5. **Host-centric optimization.** The schedule's objective is not just "everything lands together," it is "the host spends as little time in the kitchen as possible after guests arrive." This comes straight from your hosting philosophy and is the design principle the whole app inherits.

## 3. Design principles (derived from how you host)

| Principle | What it means in the product |
|---|---|
| **Effortless to the guest, planned to the minute** | Everything that can be done ahead is scheduled ahead. The plan front-loads prep and cleaning so the final hour is assembly, not cooking. |
| **Always know the next three steps** | Cook mode shows the current step and a glance of what is coming, across recipes, in one timeline. |
| **Nothing untested reaches the table** | Recipes carry a "never cooked" state; adding one to an event triggers a warning and an offer to schedule a test cook. |
| **Keep half a mind on the stove** | Live Activities, timers that break through Silent/Focus, and proactive "check the roast" prompts carry the stove's state to the Lock Screen and Dynamic Island so you can be with people. |
| **Anticipate every reasonable need** | Guest profiles remember restrictions and preferences across events. The menu builder checks them. A "reserve tasks" list exists for the guest who insists on helping. |
| **Excellence is a standard, not a mood** | Doneness is a temperature, not a feeling. Carryover and resting are modeled. Food-safety minimums are enforced. Post-cook notes feed version history. |

## 4. Feature map

Legend for *Source*: **P** = in your proposal, **M** = market parity (competitors do it, we must too), **N** = new proposal from this review. *Phase* refers to the delivery plan in [04-Execution-Plan](04-Execution-Plan.md).

### 4.1 Capture

| Feature | Source | Phase | Notes |
|---|---|---|---|
| Share-sheet import from Safari and apps (NYT Cooking, etc.) | P, M | 1 | Share Extension; parse schema.org Recipe JSON-LD; fall back to on-device language model extraction. |
| In-app browser import with your own logins | M (Mela) | 1 | Needed for paywalled sites whose JSON-LD is behind auth. |
| Manual step-by-step entry, blanks allowed | P | 1 | Unknown fields auto-fill from cook history (actual time, actual yield). |
| Single page scan with quality gate | P | 2 | VisionKit document camera, Vision `RecognizeDocumentsRequest`, `DetectLensSmudgeRequest`, sharpness check. |
| Structured OCR review (assign blocks: title, ingredients, steps, headnote) | M (Mela), P | 2 | Apple Pencil lasso on iPad; tap-to-assign on iPhone. |
| Sub-recipe detection ("see page 84") and linking | P | 2 | Regex plus model; separate record, inlined at cook time. |
| ISBN scan → book metadata and cover | P | 2 | VisionKit barcode scanner; Open Library (keyless) with Google Books fallback. |
| Whole-book ingestion session with index-derived punchlist | P | 2 | The flagship capture flow. Background OCR queue; completeness tracking. |
| Multi-page recipe stitching | N | 2 | Cookbook recipes routinely span two pages; the session must merge them. |
| Printed-photo capture and cleanup for cover image | P | 2 | Deskew, crop, auto-levels, sharpen. Honest about limits (moiré, gloss glare). |
| Your own dish photo, optionally replacing cover | P | 3 | Taken from the post-cook flow. |
| Headnote/story captured but collapsed by default | P | 2 | |
| Import Paprika / Mela / Crouton libraries | M | 1 | Migration is a one-time win; Paprika's `.paprikarecipes` is gzipped JSON. |
| PDF recipe import (publisher PDFs, printed handouts) | N | 2 | Same pipeline as page scan using PDFKit page images. |
| Screenshot and photo-library import (Instagram/TikTok screenshots) | M (ReciMe) | 2 | Same OCR pipeline. Video import deliberately out of scope. |

### 4.2 Understanding the recipe

| Feature | Source | Phase | Notes |
|---|---|---|---|
| Structured ingredients: quantity, unit, item, prep note, optional flag | P | 1 | Parsed, editable, never a blob of text. |
| Unit system: US customary, metric volume/weight, counts, "pinch" | P | 1 | Foundation `Measurement` plus custom units; density table for volume↔weight. |
| Scaling with friendly rounding (4 tbsp → ¼ cup) | P | 1 | Rule engine; warnings where scaling is non-linear (leavening, salt, pan size, bake time). |
| Provenance: source, date added, author, source rating, link back | P | 1 | |
| Reader-comment summary ("most people halve the sugar") | P | 6 | Rendered-page extraction then model summary; brittle, so late. |
| Auto-tags: dietary, course, cuisine, complexity, time | P | 3 | Allergens rule-based for safety; the rest model-assisted and editable. |
| Inferred practicality tags ("needs a full kitchen", "weeknight") | P | 3 | From tools, time, step count. |
| Equipment extraction and gap check against your tools | P | 3 | |
| Nutrition estimate per serving | P | 3 | USDA FoodData Central; clearly labeled as an estimate. |
| Version history with cook notes per version | P | 3 | |
| "Never cooked" state, cook count, last cooked, where cooked | P | 3 | Location via CoreLocation at cook time (city-level). |
| Learned actual times refine stated times | P | 3 | |
| Task annotation: active vs passive time, hold windows, dependencies | N | 5 | The data the scheduler needs. Model-assisted, confirmed by you once per recipe. |
| Technique glossary and inline explanations | N | 7 | "What does *monter au beurre* mean?" without leaving cook mode. |

### 4.3 Browse and search

| Feature | Source | Phase | Notes |
|---|---|---|---|
| Recipe library with filters (metadata, tags, book, cooked state) | P | 1 | |
| Cookbook shelf with sort/filter by cuisine, author | P | 2 | |
| Book detail: by section or index, completeness callouts | P | 2 | |
| Keyword search in a single place (search tab) | P | 1 | HIG: search as a dedicated tab on iPhone. |
| Natural-language search over cook history ("that veg dish I made in Seattle") | P | 6 | Model turns the phrase into a structured query; semantic ranking. |
| Spotlight and Siri indexing of recipes (`IndexedEntity`) | N | 6 | "Show my braises in Recipe Codex." |
| Collections (manual) and Smart Collections (saved filters) | M | 1 | Cheap and heavily used in every competitor. |
| Favorites, recently viewed, recently cooked | M | 1 | |

### 4.4 Kitchen profile

| Feature | Source | Phase | Notes |
|---|---|---|---|
| Pantry library with in/out of stock and add-to-list | P | 4 | |
| Tools library (ovens and count, burners, mixers, circulator, etc.) | P | 4 | Also informs scheduler resource limits. |
| Proficiency setting drives concurrency and technique warnings | P | 4 | |
| Multiple kitchens (home, a rental) with their own tools | N | 4 | Solves your "Airbnb kitchen" case directly: plan against the kitchen you'll be in. |
| Guest profiles: restrictions, dislikes, drink preferences, history | N | 4 | Remembered across events. |

### 4.5 Events and menus

| Feature | Source | Phase | Notes |
|---|---|---|---|
| Event: date, arrival time, seating time, guest count, restrictions, notes | P | 4 | |
| Menu with course slots, multiple candidates per slot, finalize later | P | 4 | |
| Balance suggestions (missing veg, not enough food, too many complex dishes) | P | 4 | Rule-based first; model-assisted later. |
| Never-cooked and complexity-load warnings | P | 4 | |
| Sub-recipes auto-added | P | 4 | |
| Menu-wide scaling to guest count | P | 4 | |
| Doneness targets → pull temperatures with carryover and rest | P | 4 | Per protein and cut; USDA minimums enforced. |
| Conversational menu builder | P | 6 | Tool-calling over your library; swappable model (on-device, Private Cloud Compute, Claude). |
| Wine and drink pairing notes, including a non-alcoholic option per course | N | 6 | Directly from your hosting notes. |
| Printable menu card and guest-facing menu share | N | 4 | PDF; nice for the table, and it needs no app. |
| Post-event debrief: ratings, notes, what to change | N | 5 | Feeds recipe versions and guest profiles. |
| Test-cook scheduling for untested recipes | N | 4 | Puts a rehearsal on the calendar before the event. |

### 4.6 Shopping

| Feature | Source | Phase | Notes |
|---|---|---|---|
| Aggregated list across menu, net of pantry | P | 4 | Ingredient normalization plus unit conversion. |
| Store-section grouping, specialty items separated | P | 4 | Taxonomy that learns from your corrections. |
| Stops (Whole Foods, butcher, fishmonger) with auto-assignment | P | 4 | |
| Add single recipe to list | P | 4 | |
| Check-off that survives across devices | M | 4 | CloudKit sync. |
| Export to Reminders / share as text | M | 4 | For a partner without the app. |
| Instacart handoff link; Kroger cart add | P (optional) | 7 | Both are "build the list, user checks out." Whole Foods has no public API. |

### 4.7 Scheduling and cook mode

| Feature | Source | Phase | Notes |
|---|---|---|---|
| Workback schedule across days from serve time | P | 5 | Deterministic scheduler; model only annotates recipes. |
| Editable timeline with overload and feasibility warnings | P | 5 | "Noon on the day is too late for a 24-hour rest." |
| Task batching (mise en place), clean-as-you-go, pre-arrival emphasis | P | 5 | Scheduler heuristics with a "host presence" objective. |
| Hold-window knowledge ("pasta: serve within 3 min") | P | 5 | Curated component knowledge base. |
| Single-recipe cook mode with step view, ingredient highlighting | P, M | 3 | |
| Timers from highlighted times; multiple named timers | P, M | 3 | AlarmKit so they alert through Silent/Focus. |
| Live Activity: Dynamic Island, Lock Screen, StandBy, Apple Watch Smart Stack | N | 3 | Free Watch presence without a Watch app. |
| Hands-free: Siri, Action button, big-target "knuckle mode", voice phrases | P | 3 | |
| Service mode across recipes with lateness tracking and replan | P | 5 | |
| Proactive checks ("roast should be near 120°F, check it") | P | 5 | |
| Temperature guidance from your readings (time-to-target estimate) | P | 5 | Physics-lite model fit to the readings you enter. |
| Food-safety minimum checks | P | 5 | |
| Pot/pan size suggestion from volume | P | 5 | Vessels come from your tools library. |
| Bluetooth probe integration (Combustion Inc., open MIT SDK) | N | 7 | Live temps and their prediction engine; MEATER has no public API. |
| Reserve tasks for helpers | N | 5 | Simple, safe tasks pre-selected for a guest who wants to help. |
| iPad as kitchen display, iPhone as remote | N | 7 | Local network link; same session on both. |
| Keep screen awake in cook mode; high-contrast kitchen theme | M | 3 | |

### 4.8 Sharing, sync, platforms

| Feature | Source | Phase | Notes |
|---|---|---|---|
| iPhone ↔ iPad sync | P | 1 | SwiftData + CloudKit private database. |
| Export recipe as PDF, text, Markdown; menu with schedule as PDF | P | 1, 4 | Recipient needs nothing installed. |
| Export in Paprika and Cooklang formats | N | 7 | Portability; the market punishes lock-in. |
| Mac app | P (later) | 7 | SwiftUI multiplatform; iPhone Mirroring and "Designed for iPad" cover the gap meanwhile. |
| Household sharing (a partner's device) | M | 7 | CloudKit shared database. Design the data model for it now. |
| Market readiness: onboarding, App Store, privacy, copyright policy | P (optional) | 7 | Scanned book content must stay private to the user's account. |

## 5. Explicitly out of scope (for now)

- Recipe discovery feeds, RSS, or social features (Mela, Crouton Discover). Codex is for recipes you already chose.
- Video-to-recipe import from TikTok/Instagram reels.
- Cook-together over FaceTime (Pestle's SharePlay).
- Full nutrition logging or diet tracking.
- Android or web.
