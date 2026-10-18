# UX notes between slices

*Started Oct 17, 2026. A running list of UX observations and decisions gathered while a Phase 1 slice is in flight, so nothing has to interrupt a running session. The next slice brief carries everything under **Open**; the slice session that acts on an item moves it to **Done** with its commit. Anything that changes a product decision also gets a row in [04-Execution-Plan](../Planning/04-Execution-Plan.md) §5.1 when it is folded in.*

## How to use this file

- **Add freely.** Caleb adds notes here between slices or while one runs; Claude adds notes from verification. Screenshots stay out of the repo; describe what the screen showed.
- **One item per row:** what was seen, where it is in the code, what to do instead, and who decided. Mark a row **Decided** when Caleb has chosen; leave it **Proposed** when it still needs his call.
- **Batched, not live.** A running slice is not redirected for notes here unless a note changes one of its own items. The next brief lists the Open rows it should take.
- **Slice sessions** may edit this file only to move rows into Done (with the commit) or to add findings under Open; they do not reword decisions.

## Open (goes into the next slice brief)

| # | Status | Seen | Where | Do instead | Decided by |
|---|---|---|---|---|---|
| 17 | Proposed | The Recipes Filter menu closes after each choice, so checking two courses takes two trips. With `.menuActionDismissBehavior(.disabled)` it stays open, but on the iOS 27 simulator the open menu does not redraw its checkmarks, so a just-checked course looks unchecked until the menu is reopened (slice 6). | `RecipeCodex/Tabs/RecipesView.swift` (`filterMenu`) | Keep closing after each choice (as shipped) until an open menu redraws its toggles; then keep it open for Course. Alternative: a Course submenu that stays open. | Proposed by Claude, slice 6 |
| 18 | Proposed | Recipes More still shows a disabled **Select**, and the Books view's More holds only a disabled **Sort**. Row 11 settled that methods not yet shipped are hidden, not disabled; these two predate it. | `RecipeCodex/Tabs/RecipesView.swift` (More menu) | Hide Select until Select mode ships (slice 7) and hide Books' More until the shelf has something to sort. | Proposed by Claude, slice 6 |
| 19 | Proposed | Step text is now selectable (row 13), so long-press selects a word and As Written for a temperature moved into the edit menu: "As Written: 450°F (230°C) or 400°F (200°…", truncated, and only when the selection touches the pill. | `RecipeCodex/Library/StepText.swift` (`StepTextLayout.Coordinator`) | Make the pill itself a button (03 §3.3: "highlighted times are buttons") that shows the original in a small popover; keep the edit-menu item for selections. | Proposed by Claude, slice 6 |
| 20 | Proposed | A note that came from a closing clause, or that holds parentheses, reads with nested parentheses on detail: "all-purpose flour (plus extra (for kneading))" (the lasagne). | `RecipeCodex/Library/RecipeDetailView.swift` (`IngredientLine.detail`), `Packages/Capture/Sources/Capture/RecipeExporter.swift` (`description`) | Show clause notes after a comma ("all-purpose flour, plus extra (for kneading)") and keep parentheses for parenthetical notes; the parser would record which form the note had. | Proposed by Claude, slice 6 |

## Done

| # | Moved from Open | Commit | Note |
|---|---|---|---|
| 1 | iPad tabs (04 §5.1 "iPad tabs") | `8b20606` | `.tabBarOnly`: the floating tab bar at the top on iPad; each tab's split-view sidebar is the only left column. |
| 2 | Pantry hub (04 §5.1 "Pantry hub") | `ffd5021` | Inset grouped hub with live summaries; Pantry pane renamed Staples; same rows as the iPad sidebar. Profile card superseded by row 15. |
| 3 | Search tab (04 §5.1 "Search tab") | `8b20606` | The bubble needed `.tabViewSearchActivation(.searchTabSelection)` on iOS 27 (not the tab style). Scopes All · Recipes · Pantry · Plan from the tab the cook came from, suggestions per scope, the tab's own cells. `.searchable` inside Books, a Pantry pane and Sources waits for those screens' content. |
| 4 | Recipes filters (04 §5.1 "Recipes filters") | `0d5c2f9` | Group By in More (default Course), Filter button with sections and Clear, removable tokens as content. |
| 5 | Detail units (04 §5.1 "Detail units") | `c8bc9f1` | More → Units (Preferred · US · Metric · As Written); long-press a line for As Written; Profile footer updated. |
| 6 | Detail scale (04 §5.1 "Detail scale") | `c8bc9f1` | "Ingredients · 4 servings ⌄" with a popover (stepper or multiplier, Reset); "6 servings · scaled from 4". |
| 7 | Kitchens (04 §5.1 "Kitchens") | `ffd5021` | Kitchens pane removed; the `Kitchen` model stays, no UI. |
| 8 | Proficiency (04 §5.1 "Proficiency") | `9235d42` | Expert tier; `concurrencyLimit` computed from the tier, stored attribute dropped; no Juggling section. |
| 9 | Review prompt (04 §5.1 "Review prompt") | `0d5c2f9` | The row moved from Cook to the top of Recipes, opening Needs a Look; also a Filter entry. |
| 10 | Ingredient lines (04 §5.1 "Ingredient lines") | `0a4d9bf`, `d1c55de`, `c8bc9f1` | Note and produce equivalent in schema v1 and the parser, filled on import, edit and export; secondary colour on detail; one-time re-read of stored lines (liquid ounces and note splits). Nested parentheses: row 20. |
| 11 | Add menu (04 §5.1 "Add menu") | `0d5c2f9` | Import from Web, Enter Manually (⌘N), Import from Paprika or Mela…; disabled Scan Page and Add Book removed. Disabled Select and Sort: row 18. |
| 12 | Detail share (04 §5.1 "Detail share") | `c8bc9f1` | Share in More with the same submenu; Cook alone in the bottom bar. |
| 13 | Step photos (04 §5.1 "Step photos") | `a043ec4` | TextKit 2 wrap around a 160 × 120 thumbnail; stacked at accessibility sizes. As Written in the edit menu: row 19. |
| 14 | Floating headers (04 §5.1 "Floating headers") | `0d5c2f9`, `c8bc9f1` | Switch, review row and tokens scroll with the content; hard scroll edge on detail. |
| 15 | Pantry hub, amended (04 §5.1 "Pantry hub") | `ffd5021` | Profile as the hub's toolbar button (sidebar toolbar on iPad); order Staples · Tools · Cellar & Bar · Sources. |
| 16 | Edit glyph (04 §5.1 "Edit glyph") | `c8bc9f1` | `pencil` with the label "Edit" on recipe detail. |
