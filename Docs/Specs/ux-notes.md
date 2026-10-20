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
| 39 | Proposed | The PDF's ingredients column never hugs: on US Letter and A4 a third of the text width (2.33 in, 2.26 in) is narrower than the 2.4 in floor, so slice 10's rule, built as written with the floor winning, gives 2.4 in on both papers. | `RecipeCodex/Export/RecipePrintLayout.swift` (`RecipePDFRenderer.layout`) | Pick the cap: a third of the page width (2.83 in on Letter, 2.76 in on A4) lets long-lined recipes widen the column; or keep a fixed 2.4 in. | Claude (slice 10), for Caleb |
| 40 | Proposed | The PDF keeps slice 3's 210 pt cover between the metadata and the columns on page 1, which leaves the lasagne's first page room for one step; the brief's order (title, source, metadata, then ingredients beside steps) does not name it. | `RecipePrintLayout.swift` (`PrintHeader`) | Keep it, make it smaller, or leave it out of the printout. | Claude (slice 10), for Caleb |
| 41 | Proposed | The menu bar's View → Filter is a submenu holding the toolbar Filter's items, not "Filter…": an ellipsis item would open a filter sheet, which no planning doc describes. | `RecipeCodex/RecipeCodexCommands.swift` | Keep the submenu, or design a Filter sheet for the menu bar. | Claude (slice 10), for Caleb |
| 42 | Proposed | File → New Recipe (⌘N) opens Enter Manually; 04 §5.1 "Add menu" retired "New Recipe" from the Add menu, while the slice brief named the File item New Recipe. | `RecipeCodexCommands.swift` | Keep "New Recipe" in the File menu (the menu bar's convention), or call it Enter Manually there too. | Claude (slice 10), for Caleb |
| 43 | Proposed | Escape from a hardware keyboard (sent with XCTest on the iPad simulator) did not close the Import from Web sheet; the sheets' cancel (×) buttons carry no Escape shortcut. | `RecipeCodex/Import/WebImportView.swift`, the editor and the other sheets | Give each sheet's cancel button `.keyboardShortcut(.cancelAction)` so Escape cancels, after a check on a device with a keyboard. | Claude (slice 10), for Caleb |
| 44 | Proposed | For a complete page-text reading without headings the app shows the reading and lets the model refine it in place, but the Share Extension, out of slice 10's scope, still waits on "Reading ingredients…" with Use Page Reading. Every saved page shows at once in both. | `RecipeCodexShare/ShareViewController.swift` | The same in the extension: show the reading at once with the Reading row. | Claude (slice 10), for Caleb |
| 45 | Proposed | Selecting Search in the iPad sidebar shows Search with its field unfocused (the system's behavior for a sidebar search tab); ⌘F now also focuses it. | `RecipeCodex/Tabs/SearchView.swift` | Focus the field whenever the sidebar's Search is selected, or keep the system's behavior. | Claude (slice 10), for Caleb |

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
| 18 | Recipes More (04 §5.1 "Add menu") | `bde8ce2`, `c842663` | Select works (More → Select, shown once there are recipes); the Books view has no More until the shelf has something to sort. |
| 19 | Step pills (04 §5.1 "Step pills") | `230cd14` | A quick tap on a pill opens a popover anchored to it (value shown, then As Written); a held touch still selects text and the edit menu keeps As Written; VoiceOver As Written action. The same pills in the headnote, notes and ingredient lines. Time pills wait for a duration parser in Units. |
| 20 | Ingredient lines (04 §5.1 "Ingredient lines") | `bb5bd7d` | `NoteForm` (clause · parenthetical) from the parser, `Ingredient.noteForm` in schema v1; a clause note after a comma, a parenthetical in parentheses, any note holding parentheses after a comma; second one-time re-read for stored notes. |
| 21 | Title switch (04 §5.1 "Title switch") | `c842663` | Large-title "Recipes  Books" as the first scrolling item, 20 pt apart, stacked at accessibility sizes; bar title removed with `toolbar(removing: .title)`, `navigationTitle` kept, so Back reads "Recipes" (long-press shows it). |
| 17 | Recipes filters, amended (04 §5.1 "Recipes filters") | — | Kept as shipped: the Filter menu closes after each choice until an open iOS menu redraws its toggles. No code change. |
| 23 | Collections pinning (04 §5.1 "Collections") | — | No pinning: the sidebar lists every collection and Edit reorders them; 03 §4's "user collections pinnable" dropped. No code change. |
| 24 | Detail units, amended (04 §5.1 "Detail units") | — | Kept: temperatures on steps, headnote, notes and ingredient lines follow More → Units, as slice 7 shipped. No code change. |
| 25 | Detail share, amended (04 §5.1 "Detail share") | — | Accepted for now: several recipes share as one file each in one sheet whose header is the system's. No code change. |
| 22 | Pantry hub (04 §5.1 "Pantry hub") | `48b39fe` | Each row's second line is the pane's purpose while it is empty and the live summary after; "Nothing yet" gone; sentences shortened to two lines in the iPad sidebar. Phase 4 sections not built. |
| 26 | Ingredient lines (04 §5.1 "Ingredient lines") | `68d956f` | Third one-time re-read (`ingredients.reread.approximateEquivalents`); the roast potatoes read "4 lb russet or Yukon Gold potatoes" on both stores. |
| 27 | Pantry hub (04 §5.1 "Pantry hub") | `c55f66c` | Profile at the iPad sidebar's foot (bottom bar, filled while shown); no white band in landscape; Plan and Cook have none. Portrait unchecked (headless simulator). |
| 28 | iPad columns (04 §5.1 "iPad columns", "Search tab") | `93ff769`, `b150b6c` | Two columns; a recipe pushes over the grid (Spotlight too); ingredients beside steps on the wide detail, staying under the bar when they fit; book route set up; search tab unchanged. |
| 29 | Step pills (04 §5.1 "Step pills") | `63cfba3` | The pill covers `DurationMention.valueRange` and the qualifying words stay as text ("Salt up to [2 days] ahead"); As Written quotes the whole mention and VoiceOver reads the qualifier with the value spelled out. |
| 31 | Ingredient lines (04 §5.1 "Ingredient lines") | `144bd40` | Fourth one-time re-read (`ingredients.reread.leadingPreparations`); both stores swapped 2 lines, the lasagne's spinach in both versions, which reads "1 cup fresh spinach leaves, packed (3.5 ounces)". Capture unchanged. |
| 33 | iPad columns (04 §5.1 "iPad columns") | `9b20838` | The ingredients column hugs its longest line between 280 pt and a third of the two columns (≈ 331 pt beside the system sidebar); the header does not widen it; steps capped at a 660 pt measure; pinned ingredients unchanged. |
| 34 | Bookshelf, Title switch (04 §5.1 "Bookshelf", "Title switch") | `c1a1c6c`, `3745cec` | Cookbooks everywhere the cook sees it; Bookshelf → All Cookbooks in the sidebar, no book rows; "Recipes  Cookbooks" fits at the default size and stacks when it does not. |
| 35 | iPad tabs (04 §5.1 "iPad tabs") | `c1a1c6c`, `b0bfa8c` | `.sidebarAdaptable` with sidebar-only sections in regular width, Profile in the sidebar's bottom bar, drops onto collection tabs, More → Collections on iPad for reordering. The system sidebar is a flat full-height column on the simulator, not an inset island. |
| 30 | Step pills (04 §5.1 "Step pills") | `c946f56` | Units reads "1 hr. 15 min." with periods as one compound (PR 6); the app shows "[1 hr 15 min]" as one pill. |
| 32 | iPad tabs, superseded (04 §5.1 "iPad tabs") | — | Kept as the system drew it, then made moot by row 35's sidebar. No code change. |
| 36 | iPad tabs (04 §5.1 "iPad tabs") | — | Kept: a section with no tabs is not drawn; the first collection comes from More → New Collection…. No code change. |
| 37 | iPad tabs (04 §5.1 "iPad tabs") | — | Kept: only Needs a Look carries a count, which the collapsed bar shows as a red badge. No code change. |
| 38 | iPad tabs, Search tab (04 §5.1 "iPad tabs", "Search tab") | — | Planning docs folded Oct 19, 2026: the Recipes tab is the whole library with no All Recipes row; the sections exist in regular width only; Search sits at the sidebar's top. No code change. |
