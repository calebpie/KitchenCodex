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
| 1 | Decided | iPad landscape shows two stacked left columns: the tab sidebar (Recipes · Pantry · Plan · Cook · Search) and, inside it, the Recipes sidebar (All Recipes, Smart Collections, Collections, Books). Two nested navs for one screen. | `RecipeCodex/RootTabView.swift` (`.tabViewStyle(.sidebarAdaptable)`) and `RecipeCodex/Tabs/RecipesView.swift` (`NavigationSplitView`) | Show the tabs as the floating Liquid Glass tab bar at the top on iPad instead of a sidebar, so the Recipes split view's own sidebar is the only left column. Keep `sidebarAdaptable` only if the tab sidebar can be collapsed by default and stays collapsed; otherwise use `.tabBarOnly`. Collections and Books stay in the Recipes sidebar. Check the same on Pantry (its panes) once that tab has content. | Caleb, Oct 17, 2026 |
| 2 | Decided | iPhone Pantry tab shows its six panes as a horizontal row of filter chips under the title; the sixth (Kitchens, Profile) scrolls off screen, and chips read as filters, not destinations. | `RecipeCodex/Tabs/PantryView.swift` (`Pane` enum already has `icon` and `description`; selector is the horizontal `ScrollView` at line ~60) | Make the tab root a hub: an inset grouped list with one row per pane (icon, name, a live summary such as "142 staples · 3 low" or "12 bottles" instead of static copy), Profile as a card at the top in the Settings style, each row pushing its pane. On iPad the same rows are the Pantry sidebar sections (see row 1), so the hub and the sidebar are one list. Rename the first pane "Staples" so the root "Pantry" does not list a row called "Pantry". Caleb's alternative: tall vertical cards with name, icon and description. | Caleb, Oct 17, 2026 (rows with live summaries, Profile card on top, first pane renamed Staples; 04 §5.1 "Pantry hub") |
| 3 | Decided | iPhone tab bar shows Search as a fifth equal tab that opens its own page. Caleb's idea: a separate bubble beside a four-tab bar that expands leftward into a text field and searches the page you are on (on Recipes, filters the recipes) instead of opening a new page. | `RecipeCodex/RootTabView.swift` (the tab already has `role: .search`, which iOS 26+ draws as a separate bubble that morphs into the field; find out why it renders inline here, likely the `.sidebarAdaptable` style, while doing row 1) and `RecipeCodex/Tabs/SearchView.swift` | Keep the system search tab for the bubble and the morph, never a custom control. Make the search view context-aware: a scope control under the field (All · Recipes · Pantry · Plan) that defaults to the tab you came from, suggestions drawn from that tab, results in that tab's own cell style so it reads as filtering the page. Keep the dedicated results surface for cross-library and natural-language queries (03 §3.18). For search inside a single screen (Books, a Pantry pane, Sources) use `.searchable` with `.searchToolbarBehavior(.minimize)`, which gives a bubble-to-field in that screen. | Caleb, Oct 17, 2026 (system search tab as the bubble, scopes defaulting to the current tab; 04 §5.1 "Search tab") |

## Done

| # | Moved from Open | Commit | Note |
|---|---|---|---|
