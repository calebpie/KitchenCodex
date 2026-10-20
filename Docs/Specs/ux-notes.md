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
| 29 | Decided | Time pills drop the words that qualify a time: "marinate at least 6 hours" reads "[6 hr]", "cook another 10–30 minutes" "[10–30 min]", "30 to 40 minutes longer" "[30–40 min]", "about 5 minutes more" "[5 min]", and the roast chicken's "Salt up to 2 days ahead" "Salt [2 days] ahead". The words are one tap away (As Written) and VoiceOver reads "6 hours" (iPhone, slice 8 build, the short ribs, duck, potatoes, cranberry sauce and roast chicken). | `RecipeCodex/Library/StepText.swift` (`parts`); `Packages/Units/…/DurationParser.swift` takes the qualifier into the mention and `ParsedDuration.formatted()` leaves it out | The pill covers the value only and every other word stays as text: "Salt up to [2 days] ahead", "marinate at least [6 hr]", "another [10–30 min]", "[30–40 min] longer", "about [5 min] more". **Units (by PR, not a slice):** `DurationMention` exposes where the number-and-unit run sits inside the mention (`valueRange`: the whole "10–30 minutes" of a range and the whole "1 hr 15 min" of a compound, never a qualifier). **App (next slice):** `StepText` draws the pill over that range and leaves the rest of the mention as plain words; the popover's As Written and VoiceOver's full reading are unchanged. | Caleb, Oct 19, 2026 (04 §5.1 "Step pills") |
| 30 | Decided | "cook 1 hr. 15 min. at 300°F" with periods reads as two pills, "[1 hr]. [15 min].", where "1 hr 15 min" reads one "[1 hr 15 min]"; a timer started from it in cook mode would count one hour (Pill Test on iPhone, slice 8 build; no imported recipe has it in a step). | `Packages/Units/…/DurationParser.swift` (compounds) | Units reads an abbreviated unit with a period followed by a number and the next smaller unit as one compound ("1 hr. 15 min." is 1 hr 15 min), under the same rule as without periods, so "Cook 1 hr. Then stir." stays one hour. By PR with row 29's Units change; the app pills whatever the parser returns. | Caleb, Oct 19, 2026 (04 §5.1 "Step pills") |
| 31 | Decided | After PR 5 (`7c20df5`) the parser reads a preparation written before the comma: "1 cup packed, fresh spinach leaves" is the item "fresh spinach leaves" with the preparation "packed". Three lines on the 19 saved pages change (the lasagne's spinach, "peeled, grated fresh ginger", "blanched, finely ground almond flour"), but a stored line keeps its reading until edited or imported again (slice 5's rule), so stored copies of those lines still show the preparation word as the item, which Phase 4's shopping list and pantry matching would use. | `RecipeCodex/Library/IngredientReread.swift` | A fourth one-time pass under its own flag (`ingredients.reread.leadingPreparations`), as the three before it: re-parse the stored raw text and take the fresh item and preparation only where the stored item is the fresh preparation and the fresh item is the stored preparation's first clause, with everything else on the line reading the same; logged. Next slice. | Caleb, Oct 19, 2026 (04 §5.1 "Ingredient lines") |

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
