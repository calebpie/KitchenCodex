# Recipe Codex — UX Proposals for iPhone and iPad

*Oct 17, 2026. Screen-level proposals for the core pages and flows, written against the Human Interface Guidelines as updated through October 13, 2026 (Liquid Glass, iOS/iPadOS 27 tab bar and search conventions, Snippets, Generative AI, Live Activities). Rendered low-fidelity wireframes are in [wireframes.html](wireframes.html); open it in a browser or on the iPad.*

## 1. Design principles

1. **Content first, glass for controls.** Liquid Glass is used only where the system puts it: tab bar, toolbars, sidebar, search field, the Now Cooking accessory. Recipe pages, cards, lists and the schedule live in the content layer on standard materials. No custom glass in content (HIG Materials).
2. **Kitchen-proof.** Cook and service mode use large type, standard-size controls (the HIG 44-point minimum) with generous spacing so a knuckle lands cleanly, bottom-anchored primary actions, and never hide the current step. An optional high-contrast kitchen theme is a toggle. Screen stays awake.
3. **Progressive disclosure.** Headnotes, nutrition, version history, provenance and balance details sit behind disclosures. The schedule shows a summary before the timeline. Warnings are inline notes, not alerts.
4. **Trustworthy intelligence.** Anything a model produced is labeled, shows its confidence when low, is one tap from the source (the page image, the web page), and can be edited, retried or undone (HIG Generative AI: refine, revert, acknowledge).
5. **Effortless hosting.** The planner's visible objective is time away from guests. The schedule shows "work after arrival" as a number and tries to drive it down.

## 2. System conventions adopted

| Element | HIG guidance | How Recipe Codex uses it |
|---|---|---|
| Tab bar (iPhone) | Few tabs; search as a trailing search tab; floats on Liquid Glass; can minimize on scroll with an accessory | Recipes, Pantry, Plan, Cook + Search tab, in the order the work happens. Minimizes on scroll only when the Now Cooking accessory is present. |
| Tab bar (iPad) | Top of screen; optionally converts to a sidebar; let people customize tabs | `.sidebarAdaptable`; sidebar sections per tab; Collections are user-addable to the sidebar. |
| Toolbars | Group by function; at most three groups; symbols not text; one `.prominent` action on the trailing edge; large titles on iPhone | Every top-level screen: leading = sidebar toggle (iPad), center = title, trailing = Add (+) where the screen creates something, and More (⋯) for screen-level actions (view switch, sort, select, import and export). No profile button on any tab except Pantry, whose hub carries the account button at its trailing edge; profile and settings are a pane of Pantry (04 §5.1 "Pantry hub"). Detail screens: Back · title · Edit (the `pencil` glyph, 04 §5.1 "Edit glyph") · More (Share is an item inside it, 04 §5.1 "Detail share"); prominent Cook/Finalize/Done alone in the bottom bar where applicable. |
| Search | One clearly identified place; show scope; suggestions; tokens for filters | Search tab searches everything; interpreted natural-language filters appear as removable tokens. Local filter chips on Recipes act as a view filter, not a second search. |
| Sheets | Use for self-contained tasks; standard Close | Import preview, Add recipe to menu, Ask Codex, post-cook flow. |
| Full-screen covers | For immersive, distraction-free tasks | Camera, scanning session, cook mode, service mode. Toolbars hidden by default with a reliable reveal (tap). |
| Snippets | Compact result or confirmation after a Siri action, under 400 pt | "Next step" result snippet; "Start service?" confirmation snippet with the menu summary. |
| Live Activities | Compact, minimal, expanded and Lock Screen presentations; heavy text; concentric margins; limited-width variant | Timer and step in compact; next step and up to three timers in expanded; progress in Lock Screen. |
| Widgets | Glanceable, configurable via App Intents | Tonight's plan, Next event, Timers, Cook something new. |
| Menus and context menus | Icons in menu items; actions at point of use | Long-press a recipe: Cook, Add to menu, Add to list, Favorite, Share. |
| Generative AI | Communicate where AI is used; specific progress text; refine/undo; non-AI fallback | "Reading ingredients…" style progress; "Suggested" labels; every suggestion editable; rules-based fallback everywhere. |
| Accessibility | Dynamic Type, VoiceOver, Reduce Transparency, Increase Contrast, Reduce Motion | All text styles semantic; custom controls labeled; glass falls back automatically; the kitchen theme (a toggle) is tested at AX sizes; cook mode keeps standard control sizes with wide spacing rather than an enlarged-button mode. |

## 3. Screen proposals

Each entry gives purpose, layout on both devices, key interactions, states, and the HIG notes that shaped it. Numbers in brackets refer to the callouts in the wireframes. Sections keep their original numbering so cross-references stay valid; the tab order is Recipes · Pantry · Plan · Cook · Search (02 §1.1), Books (3.7) is a view inside Recipes, and Pantry (3.17) is the second tab.

### 3.1 Cook (Today)

**Purpose.** What is happening today in the kitchen, and only that: review prompts for imported recipes live in Recipes (04 §5.1 "Review prompt"). Fourth tab, to the right of Plan: by the time you reach it the menu is planned and shopped, so it opens on the active session, tonight's plan or today's prep tasks. The app launches on Cook when a session is active or an event is today, otherwise on Recipes.

**iPhone.** Large title "Cook." Top card: today's event (name, guests, seating time, "Start service" prominent) or, when none, "Nothing planned. Cook something new?" with three suggestions from never-cooked recipes that fit a weeknight. Below: today's prep tasks from any upcoming schedule as a checklist, running timers, and recently cooked. The Now Cooking accessory appears above the tab bar when a session is active.

**iPad.** Two columns: left the event and tasks, right suggestions and recents. Sidebar section "Today."

**States.** Empty (no events, no history): a warm first-run card linking to Import, Scan, and Pantry setup. Active session: the whole top is the session summary.

**HIG notes.** One primary action per card. No glass in cards. Suggestions labeled "Suggested" with a refresh action.

### 3.2 Recipes (library)

**Purpose.** Browse and filter the collection.

**iPhone.** Large title "Recipes," trailing Add (+) and More (⋯). The large title is itself the view switch: **Recipes** and **Books** side by side in large-title type a fixed gap apart, the shown view in the primary color and the other in secondary, each a button (decided Oct 17, 2026, 04 §5.1 "Title switch"; the two-segment control under the title is gone). It scrolls away with the content along with any active-filter tokens; only the navigation bar floats (decided Oct 17, 2026, 04 §5.1 "Floating headers"). The Recipes view is the library described here; the Books view is the shelf (3.7). Add is contextual and names the way in (04 §5.1 "Add menu"): Import from Web, Scan Page, From Photo, Paste Text, Enter Manually, then Import from Paprika or Mela in the Recipes view, unshipped methods hidden until they land; Add Book (ISBN) and, in Phase 2, Scan Sources Page in the Books view. More holds View As (Grid/List), Sort By, **Group By** (None · Course · Book · Collection; default Course, persisted; a lone section hides its header) and Select. A **Filter** button sits beside More (the funnel symbol, tinted while active); its menu has checkable sections (Course, several allowed; Cooked state; Favorites; Collection; Book; Tag; later Cuisine, Time and Dietary) and Clear Filters. Nothing shows under the title until a filter is active; then a row of removable tokens, one per filter, plus Clear, scrolls with the content (decided Oct 17, 2026, 04 §5.1 "Recipes filters"; replaces the always-visible chip row). Content toggles between a two-column card grid (image-led) and a list (text-led). Cards show image, title, time, and a small badge for "Never cooked" or the book icon.

**iPad.** Three columns: sidebar (collections, smart collections, tags), list with filters, detail. Drag a recipe from the list onto a collection in the sidebar or into a menu in a second window.

**Interactions.** Long-press for context menu. Pull down to reveal the search field? No: search is the Search tab; the Recipes screen has a filter, not a search, to honor the "one place to search" guidance. Swipe actions: Favorite, Add to list.

**HIG notes.** Filter is a toolbar action, as in Mail, and Group By a View Options submenu, as in Files; active filters read as tokens, never as controls, and never hide the content. Grid cells have concentric corner radii. Images extend under the floating bars with a scroll edge effect; the view switch and filter tokens are content, not a pinned header.

### 3.3 Recipe detail

**Purpose.** Read, scale, and start cooking.

**iPhone.** Hero image extends under the navigation bar. Title, source badge (book cover thumbnail + "p. 112" or site favicon + name), author. Metadata row: stated time / observed time, yield, difficulty, cooked count with "last: Seattle, Mar 2026" or "Never cooked" badge. Scaling is compact (decided Oct 17, 2026, 04 §5.1 "Detail scale"): the Ingredients header reads "Ingredients · 4 servings ▾"; tapping opens a popover with the stepper (or a multiplier for yield-only recipes) and Reset, amounts rescale live with friendly rounding, and while scaled the header reads "6 servings · scaled from 4". The scale is transient here and never edits the recipe; cook mode and event slots own their own. Units are a More (⋯) submenu, Preferred · US · Metric · As Written, with a checkmark on the current choice; long-press on an ingredient line shows it as written (04 §5.1 "Detail units"). No stepper row and no segmented control above the list. Ingredients list with checkboxes (for shopping and for mise en place), grouped by component (sub-recipes inline with a link to their own page); each line shows the amount bold, the item in the primary color, and preparation, notes and "(optional)" in the secondary color at the same size, never italics (decided Oct 17, 2026, 04 §5.1 "Ingredient lines"). Steps numbered, with times and temperatures highlighted; a step with photos shows a 4:3 thumbnail about 120 pt tall at its trailing edge (first photo, count badge when there are several) and the text wraps around it, narrow beside the picture and full width below it; tap to enlarge, swipe between the source's photo and your own (decided Oct 17, 2026, 04 §5.1 "Step photos"). At accessibility type sizes the thumbnail sits above the text instead. Collapsed sections: Headnote, Reader tips, Nutrition (Estimate), Versions, Cook log. Bottom toolbar: Share · Add to menu · **Cook** (prominent).

**iPad.** Same content in the detail column with ingredients and steps side by side when the width allows; the hero is smaller. A background extension effect carries the hero under the sidebar.

**States.** Imported with low confidence: a yellow "Check 2 ingredients" row at the top that scrolls to the suspect items. Scanned: a "View page" button opens the original image.

**HIG notes.** One prominent action (Cook). Large title collapses on scroll; the top edge uses the hard scroll-edge style so step text does not ghost under the title bar (04 §5.1 "Floating headers"). Highlighted times are buttons, not just color.

### 3.4 Add menu and import preview

**Purpose.** One entry point for every capture method.

Add (+) presents a menu whose items name the source, never the outcome (decided Oct 17, 2026, 04 §5.1 "Add menu"): Import from Web, Scan Page, From Photo (a page or a recipe card; PDF later), Paste Text, Enter Manually, then Import from Paprika or Mela. Methods not yet shipped are hidden rather than disabled. Scan Book lives in the Books view as Add Book. The Share Extension and the in-app browser show the same import preview sheet: image, title, source, detected yield and times, "Save" prominent, "Edit first" secondary, and a one-line status such as "Found a recipe on this page" or "No recipe data; read the page instead."

### 3.5 Scan page

**Purpose.** Fast, accurate capture with honest quality feedback.

**iPhone.** Full-screen camera. Detected page outline drawn live. A quality pill at the top: "Sharp" (green), "Hold still" (amber), "Clean the lens" (amber). Shutter at the bottom center, "Add next page" to its right once a page exists, captured-page thumbnails stack bottom left with a count. Flash and auto-capture toggles in a small top group.

**iPad.** Same, or split: camera left, running preview of recognized text right, so you can see a bad capture before moving on.

**HIG notes.** Camera is a full-screen cover with a Close button. Controls on clear Liquid Glass over the viewfinder with a dim layer for legibility.

### 3.6 Scan review

**Purpose.** Make fixing the structure faster than retyping, and ask for it only when it is needed.

**When it appears.** Always for the first recipe captured from a book, and again when a page's layout differs from one already confirmed for that book (the structurer compares column count, block order and typographic cues against the book's confirmed layouts). After that, scans save straight to the library with a quiet "Accepted automatically" line in their provenance, and review is surfaced only on low confidence: OCR confidence below threshold, ingredient lines that did not parse into quantity and item, a step count that disagrees with the page, or an unassigned region. In the book's scanning session these show as "2 need review"; in the Books view they are a filter. Every scanned recipe keeps Review in More.

**iPhone.** Two stacked panes with a draggable divider: structured recipe on top (title, yield, ingredients, steps), page image below with colored translucent regions (blue ingredients, green steps, purple title, gray headnote). Tap a region: a floating segmented control assigns it (Title · Yield · Ingredients · Step · Headnote · Ignore). Tap a structured item: it flashes its source region. A banner lists detected cross-references with Link / Add to book list / Ignore. Save is prominent; "Rescan page" lives in More.

**iPad.** Side by side: page image left, structured recipe right. Apple Pencil lasso selects a region; a popover assigns it. Pencil hover previews the region's text.

**HIG notes.** Colors are semantic (type of block), not decorative; they are reinforced by labels for color-blind users. Undo is available. The forced first review is explained once, in a sentence ("Check this one so Codex learns how this book lays out a recipe").

### 3.7 Books view and Book detail

**Books view.** The Books view of the Recipes tab (3.2); the title switch reads **Books** in the primary color with Recipes dimmed beside it (04 §5.1 "Title switch"). Grid of covers with a thin completeness bar under each (47/112). Filters: cuisine, author, completeness, needs review. Add (+) scans an ISBN.

**Book detail.** Cover, title, author, year, ISBN, completeness ring with "47 of 112 captured, 3 need review." Segmented control: Sections · Index · Missing. Sections list shows chapters with "8 of 12" counts; tapping a recipe opens it or, if not captured, offers "Scan now" with the page number. Primary action: **Continue scanning** (prominent). More: Edit book info, Export list, Scan sources page (each supplier on the book's Sources page becomes a Source in Pantry, linked to this book).

### 3.8 Book scanning session (iPad-first, works on iPhone)

**Purpose.** Capture a whole book in one sitting without losing your place.

**iPad.** Three regions: left, the punchlist with status dots and page numbers, current item highlighted; center, the camera with the quality pill; right, the last capture's recognized structure and a "Needs review" toggle. A status strip at the bottom: "12 captured · 9 processed · 2 need review · battery 64%." Pausing is one tap; the session resumes exactly here.

**iPhone.** The punchlist collapses to a compact header ("Now: Braised Short Ribs, p. 114 · 12 of 112") with a tap to open it as a sheet; camera fills the rest.

**HIG notes.** Full-screen, immersive, but with a persistent Close and a reliable way back to the list. Progress text is specific.

### 3.9 Event and menu builder

**Purpose.** Compose a balanced menu for real people.

**iPhone.** Event header card (date, arrival, seating, guests with restriction chips, Where: Home or Away with a place name; Away shows the soft kitchen warning and an on-arrival check, 04 §5.1 "Kitchens"). Date and times are set here and stay editable until service starts; once the event is in service they are fixed, and the debrief records the actual times. Slots listed as sections: Starter, Main, Sides, Dessert, Drinks, plus Add slot. Each slot shows candidate cards (image, name, servings stepper, finalize checkmark) and an Add button that opens a library picker sheet. Sub-recipes appear indented under their parent with a link icon. Inline notes under cards: "Never cooked," "Contains flour (Rosa)," "Oven conflict with the gratin." A Balance card summarizes coverage, servings vs guests, complexity load, and work after arrival. Bottom toolbar: Ask Codex · Shopping · **Finalize** (prominent, enabled when every slot has exactly one finalized candidate or is marked optional).

**Pairings.** Pairings live on the menu. Each course slot has a Pairings row under its finalized candidate: a wine or other drink and a non-alcoholic alternative, each typed or picked from Cellar & Bar (3.17). A picked bottle shows "on hand"; a pairing without one shows "to buy" and flows to the shopping list under a Wine & drinks stop. Ask Codex can propose pairings with a one-line reason, labeled Suggested. The menu card PDF prints the pairings under each course.

**iPad.** Menu on the left two-thirds; a right panel toggles between Balance and Ask Codex. Drag recipes from a second Recipes window into slots.

**Ask Codex (sheet or panel).** A short prompt field with starter suggestions ("Cozy fall dinner for six, one vegetarian"), a model badge showing which model will be used and what is shared, streaming proposal cards you can accept or swap individually, and thumbs up/down. Every proposed dish is a recipe from your library, shown with its cooked count.

**HIG notes.** Warnings are notes, not modal alerts. Generative features are labeled and have a non-AI path (the balance rules). Confirmation before an action with consequences: Finalize regenerates the list and schedule, and a finalized menu is not locked. Swapping a candidate after Finalize opens a sheet with the schedule diff (tasks added, removed and moved, the new total hours, the new "work after arrival") and applies only on confirm.

### 3.10 Shopping list

**iPhone.** Title with the event name. Grouped by stop (Whole Foods · Butcher · Fishmonger · Anywhere) and within a stop by section (Produce, Dairy, Pantry, …). Rows: checkbox, quantity, item, a small count badge when multiple recipes contribute (tap to see which). "Have at home (8)" collapsed at the bottom; swipe to move an item back to the list. Toolbar: Share, More (Reorder stops, Add item, Instacart link).

**iPad.** Two columns: stops as a sidebar, items on the right; good on a stand in the kitchen while packing.

### 3.11 Schedule (workback timeline)

**Purpose.** See and adjust the plan across days.

**iPhone.** A summary card first: "Fri · Sat · Sun; 6 h 40 m total; 35 m after guests arrive." Then a day segmented control and a vertical hour timeline. Task cards carry the recipe color stripe, name, duration, and an icon for passive tasks (clock) or oven (flame). Dragging a card shows a live feasibility state: snaps and turns neutral when valid; turns amber with an in-place reason when not ("Dough needs 24 h chilled; latest start Fri 6 PM"). A thin density bar at the left shows load per hour against your concurrency limit. A Reserve tasks section lists helper-safe tasks. Toolbar: Replan · Add task · Share.

**iPad.** Days as columns (Fri, Sat, Sun) with hour rows, a right inspector showing the selected task's dependencies, constraints and reasons, plus the reserve tasks. Keyboard: arrow keys nudge a task by 15 minutes.

**HIG notes.** Explanations at the point of the problem. Drag and drop with clear drop targets. Reduce Motion disables the snapping animation.

### 3.12 Cook mode (single recipe)

**iPhone.** Full-screen cover. Top: recipe name and step 4 of 11 with a thin progress bar; a Close and a More (kitchen theme, voice, timers). Center: the current step in large type (Title 2 or larger), with this step's ingredients listed beneath in a compact card and any time or temperature rendered as a tappable pill ("12 min" → starts a timer; "165°F" → opens the doneness card; temperatures shown in your preferred unit, long-press for the original). When the step has a photo it sits under the ingredients card at a fixed height, tap to enlarge; a camera button in the same row saves your own photo of this step to the cook session, and later cooks show both. Next step in smaller gray type below. Bottom: a wide **Done** button and a smaller Back button at standard control sizes (the HIG 44 pt minimum), separated by at least 16 pt so a knuckle lands on one or the other; active timers as pills above them.

**iPad.** Two columns: ingredients and all steps as a scrollable list on the left with the current step highlighted; the current step in very large type on the right with timers. Readable from a counter at arm's length.

**Hands-free.** Siri App Shortcuts (Next step, Back, Start timer, What's next), Action button mapped to Next step, optional voice phrases shown as a hint on first use, and swipe anywhere on the step to advance. There is no enlarged-button mode; standard targets with generous spacing are enough for a knuckle. The kitchen theme (high contrast, larger step type, opaque surfaces behind text) is a toggle in More and in Pantry → Profile, never automatic.

### 3.13 Service mode (event)

**iPhone.** Status line: "Sunday Supper · seating 7:30 · On plan" or "12 min behind." Three lanes as stacked sections: **Now** (one big task card with its recipe step and Done), **Next** (two cards), **Watch** (passive tasks with countdowns: "Short ribs in oven, 42:10," "Dough resting, until 5:15"). A proactive prompt appears as a card in Now when due ("Roast should be near 118°F. Check it." with a temperature entry field). Bottom: Done, Skip, Replan. Pre-arrival checkpoint and course plating steps appear as highlighted cards.

**iPad.** Three columns: left the compressed timeline with the current time marker, center the current task in large type, right the Watch lane with timers and the ingredients for the current task.

**HIG notes.** Lateness is a number with a color, never a nagging alert. Replan, like a late menu swap, asks for confirmation and previews the change as a diff.

### 3.14 Now Cooking accessory

iPhone only. Above the tab bar while a session runs: recipe or event name, current step truncated, next timer, a Next button. Scrolling a list minimizes the tab bar into the accessory. Tap expands to the full session. Ends when the session ends (HIG: end activities promptly). On iPad there is no accessory: the session opens in its own window (§4).

### 3.15 Live Activity

- **Compact (Dynamic Island):** leading = timer countdown; trailing = step number or a flame glyph when an oven task is active.
- **Minimal:** the soonest timer.
- **Expanded:** current step text (two lines), up to three timers, a Next button.
- **Lock Screen / StandBy:** event name, "On plan" state, current step, timers, Next.
- **Limited width (landscape):** timer only, inside the 28 pt circle.

### 3.16 Post-cook and debrief

A sheet with a five-star rating, a one-line "how did it go," optional photo (offered as the new cover), observed total time (auto, editable), yield confirmation, place (auto). Everything optional; Done is prominent. The event debrief repeats this per dish and adds an event note and a "next time" checklist.

### 3.17 Pantry

**Purpose.** Everything you have to cook with, in one tab: staples, tools, suppliers, bottles and your own settings. Planning and shopping read from it.

**iPhone.** Large title "Pantry." The root is a hub (decided Oct 17, 2026, 04 §5.1 "Pantry hub"): an inset grouped list with one row per pane in the order Staples · Tools · Cellar & Bar · Sources, each with its symbol, name and a live summary line ("142 staples · 3 low", "two ovens, five burners", "12 bottles", "4 stores"); Profile is the trailing toolbar button on the hub (the standard account glyph), not a card, because it is set once and rarely touched (amended Oct 17, 2026, ux-notes row 15). Tapping a row pushes the pane; Add (+) and More (⋯) appear on the pane, contextual to it. An earlier proposal of filter-style chips under the title was dropped: six chips do not fit the width and chips read as filters, not destinations. Each pane is a grouped list:

- **Staples** (first; the pane formerly named Pantry). Ingredients grouped by store section, each with an in-stock toggle and a staple flag; swipe to add to the current shopping list. "Used up" marks from cook mode land here. Low staples show a dot.
- **Tools.** Checklist with counts and capacities (two ovens, five burners, a 7-quart Dutch oven), per kitchen. Feeds the scheduler's resource limits and the recipe "needs" badges.
- **Sources.** Stores you frequent and specialty suppliers, grouped Equipment · Food · Drink the way cookbooks print them: name, what they carry, phone, website, address. Added by hand, from a URL, or by scanning a book's Sources page (3.7), in which case the book is shown as the origin. A **Frequented** toggle makes a store a shopping stop (3.10); an ingredient can name a preferred source. Row actions: Call, Website, Directions, Add to stops.
- **Cellar & Bar.** Two segments. Cellar: wine by color, region and vintage with bottle counts, a drink-by note and an "open" state. Bar: spirits, liqueurs, mixers and bitters. Add by hand or from a label photo (Vision reads producer and vintage; you confirm). Pairings in the menu builder (3.9) pick from here and show "on hand" or "to buy."
- **Kitchens: none.** There is one implicit Home kitchen behind Staples and Tools, never shown as a list (decided Oct 17, 2026, 04 §5.1 "Kitchens"). Cooking away from home is a property of the event (3.9): a Where field, Home or Away with a place name, a soft warning that the plan assumes your own tools and staples, and an on-arrival check of ovens, burners and missing tools for that event only.
- **Profile.** Proficiency (four tiers, Learning · Confident · Advanced · Expert, a sentence each; hands-on concurrency is derived from the tier and never shown, 04 §5.1 "Proficiency"), units, voice and hands-free, kitchen theme (toggle), intelligence (model choice and what is shared), export and backup. Guests stay under Plan, where they are used.

**iPad.** The hub rows are the Pantry sidebar, in the same order with the same symbols, with the Profile button in the sidebar's toolbar, so hub and sidebar are one list; three columns for Sources and Cellar & Bar (group, list, detail), two for the rest.

**HIG notes.** Toggles for state that is read elsewhere (in stock, frequented, open), never buttons. Phone numbers and websites are tappable detail rows, not raw text. The hub is navigation: a pane is pushed, and Back returns to the hub. The hub is the HIG list-hub idiom (Health Browse, Files Browse, Settings); each row's summary is live data, never static copy.

### 3.18 Search

The system search tab (`Tab(role: .search)`): on iPhone a separate Liquid Glass bubble beside the four tabs that morphs into the field, never a custom control (decided Oct 17, 2026, 04 §5.1 "Search tab"). The view is context-aware: a scope control under the field (All · Recipes · Pantry · Plan) defaults to the tab you came from, suggestions before typing come from that tab (recent, "Never cooked," "Cooked in Seattle," books), and results use that tab's own cell style so searching from Recipes reads as filtering the recipes; under All, results are grouped by Recipes, Books, Events, Ingredients, Sources. Search inside one screen (Books, a Pantry pane, Sources) is a `.searchable` field with the minimizing toolbar behavior, a small bubble that expands in place. A natural-language phrase shows its interpretation as tokens above the results ("vegetable · side · Seattle · Jan–Apr 2026") that you can remove individually. On iPad the field is top trailing.

### 3.19 First run

Three skippable screens (tools, proficiency, pantry), then the Recipes tab, whose empty state leads to Import, Scan or New recipe. No account creation; iCloud is already there. Everything from first run is editable later in Pantry.

## 4. iPad specifics

- **Navigation.** Floating Liquid Glass tab bar at the top, never a tab sidebar (decided Oct 17, 2026, 04 §5.1 "iPad tabs"); each tab's own split-view sidebar is the only left column, with sections per tab; user collections pinnable. Three-column `NavigationSplitView` for Recipes (both views) and for Pantry's Sources and Cellar & Bar; two-column for Plan.
- **Windows.** Recipes, Plan and Cook mode can each open in their own window. Cook mode window is useful on a stand while the planner stays open on the Mac via iPhone Mirroring or Sidecar later.
- **Menu bar and keyboard.** File (New recipe, Import, Scan), Edit, View (Recipes/Books, Grid/List, Filters), Recipe (Cook, Scale, Add to menu), Plan (New event, Finalize, Replan), Window. Shortcuts: ⌘N new, ⌘I import, ⌘F search, ⌘⇧C cook, space to advance in cook mode, ⌘R replan.
- **Pointer.** Hover effects on cards and timeline tasks; pointer changes over resizable timeline edges.
- **Apple Pencil.** Lasso to assign regions in scan review; handwriting into notes via Scribble; hover to preview region text.
- **Drag and drop.** Recipes into collections, menu slots, shopping lists; tasks within the timeline; images from Photos into a recipe as the cover.
- **Stage and size classes.** Layout decided by size class, not device. Compact width (narrow window) falls back to the iPhone layouts.

## 5. Hands-free and accessibility

- Voice phrases (in-app, on-device): "next," "back," "repeat," "timer N minutes," "how long on the [name]," "done." Shown once as a hint; always available in More.
- Siri App Shortcuts carry the same actions with several phrasings each and return Snippets.
- Action button: "Next step" when a session is active; otherwise "Start a timer."
- Standard control sizes everywhere, including cook and service mode: the HIG 44 pt minimum with at least 16 pt between primary controls, which a knuckle hits reliably. No enlarged-button mode. Swipe anywhere advances; tap-and-hold the screen goes back.
- Dynamic Type through AX5 in cook mode; VoiceOver labels for every custom control, including region colors in scan review ("Ingredients region, 6 lines").
- Reduce Transparency and Increase Contrast are honored by the system materials; the kitchen theme is a toggle (cook mode More, Pantry → Profile) and is tested under both.
- Timers use AlarmKit so they alert through Silent and Focus, with haptics.

## 6. Visual language

- **Color.** Monochrome bars and tab bar (recipe photos are already colorful; HIG advises against tinting bars over colorful content). One accent for interactive elements. Semantic colors for state: green on plan, amber warning, red behind or food-safety. Recipe colors in the schedule come from a fixed, distinguishable palette of eight.
- **Type.** San Francisco with semantic text styles; large titles on top-level screens; cook mode uses Title 1 to Large Title for the current step. Serif (New York) only for headnotes to signal "from the book."
- **Imagery.** Covers and dish photos lead the library; placeholders are a quiet monogram, not a stock photo.
- **Symbols.** SF Symbols 8: `book.closed` (Recipes), `books.vertical` (Books view), `cabinet` (Pantry), `storefront` (Sources), `wineglass` (Cellar & Bar), `calendar` (Plan), `frying.pan` (Cook), `magnifyingglass` (Search), `barcode.viewfinder` (ISBN), `text.viewfinder` (Scan), `cart`, `timer`, `oven`, `stove`, `thermometer.medium`, `person.crop.circle`, `checklist`, `waveform`.
- **App icon.** Layered Liquid Glass icon from Icon Composer 2: an open book with a pan silhouette; test in light, dark, clear and tinted variants.

## 7. Design questions

Resolved Oct 17, 2026, from your review:

1. **Scan review.** Forced for the first recipe from each book and for any new page layout; after that only on low confidence (3.6). Replaces the earlier "auto-accept with a 24-hour banner" idea.
2. **Late menu swaps.** Allowed after Finalize, with a preview of the schedule diff before it applies (3.9).
3. **Wine pairings.** Live on the menu, per course slot, with a non-alcoholic alternative; bottles come from Cellar & Bar (3.9, 3.17).
4. **Kitchen theme.** A toggle, never automatic (3.12).
5. **Cook-mode targets.** Standard control sizes with generous spacing; the enlarged "knuckle mode" is dropped (3.12, §5).
6. **Tabs.** Recipes · Pantry · Plan · Cook · Search; Books is a view inside Recipes; Pantry absorbs the profile and adds Sources and Cellar & Bar (02 §1.1).

7. **Now Cooking accessory on iPad.** Window only; the accessory is an iPhone surface (3.14).
8. **Heavy-reasoning model.** Apple cloud by default, Claude as a setting in Profile → Intelligence.
9. **Event dates.** Set in Plan and editable until service starts (3.9).
10. **iPad tabs.** Floating Liquid Glass tab bar at the top, never a tab sidebar; each tab's split-view sidebar is the only left column (§4, 04 §5.1). Added Oct 17, 2026 from `Docs/Specs/ux-notes.md` row 1.
11. **Pantry hub.** The Pantry tab root on iPhone is a Profile card plus an inset grouped list of panes with live summaries, each pushing its pane; the first pane is renamed Staples; the same rows are the iPad sidebar (3.17). Replaces the chip selector. Added Oct 17, 2026 from `Docs/Specs/ux-notes.md` row 2.
12. **Search tab.** The system search tab as the bubble beside four tabs, with scopes defaulting to the current tab and results in that tab's cell style; in-screen search uses minimizing `.searchable` fields (3.18). Added Oct 17, 2026 from `Docs/Specs/ux-notes.md` row 3.
13. **Recipes filters.** Group By in More (default Course), a Filter toolbar button with checkable sections, and tokens under the title only while a filter is active; the always-visible chip row is dropped (3.2). Added Oct 17, 2026 from `Docs/Specs/ux-notes.md` row 4.
14. **Detail units.** US/Metric leaves the detail page for a Units submenu in More (Preferred · US · Metric · As Written); long-press an ingredient line for As Written (3.3). Added Oct 17, 2026 from `Docs/Specs/ux-notes.md` row 5.
15. **Detail scale.** The servings stepper row becomes a compact control in the Ingredients header, transient on detail; cook sessions and event slots own persisted scales (3.3). Added Oct 17, 2026 from `Docs/Specs/ux-notes.md` row 6.
16. **Kitchens.** No Kitchens pane or list; one implicit Home kitchen; cooking away is a Where field on the event with a soft warning and an on-arrival check (3.9, 3.17). Added Oct 17, 2026 from `Docs/Specs/ux-notes.md` row 7.
17. **Proficiency.** Four tiers ending in Expert; concurrency derived from the tier, the Tasks at Once control removed (3.17, §5). Added Oct 17, 2026 from `Docs/Specs/ux-notes.md` row 8.
18. **Review prompt.** "N new recipes need a look" moves from Cook to the top of Recipes and opens the Needs a Look smart collection; Cook shows only what is cooking (3.2, 3.11). Added Oct 17, 2026 from `Docs/Specs/ux-notes.md` row 9.
19. **Ingredient lines.** Amount bold, item primary, preparation and notes secondary (not italic); notes and produce equivalents are parsed and stored so the shopping list can aggregate "about 3 oranges" with "about 2 oranges" (3.3, 3.10). Added Oct 17, 2026 from `Docs/Specs/ux-notes.md` row 10.
20. **Add menu.** Items name the way in (Import from Web, Scan Page, From Photo, Paste Text, Enter Manually, Import from Paprika or Mela); "New Recipe" is dropped and unshipped methods are hidden (3.2, 3.4). Added Oct 17, 2026 from `Docs/Specs/ux-notes.md` row 11.
21. **Detail share.** Share leaves the detail bottom bar for More; Cook floats alone (§2, 3.3). Added Oct 17, 2026 from `Docs/Specs/ux-notes.md` row 12.
22. **Step photos.** The step text wraps around the inline trailing thumbnail (narrow beside it, full width below), via TextKit 2 exclusion paths; stacked only at accessibility type sizes (3.3). Added Oct 17, 2026 from `Docs/Specs/ux-notes.md` row 13.
23. **Floating headers.** The Recipes view switch and filter tokens scroll with the content instead of pinning under the bar; recipe detail uses the hard scroll-edge style (3.2, 3.3). Added Oct 17, 2026 from `Docs/Specs/ux-notes.md` row 14.
24. **Pantry profile and order.** Profile is the trailing toolbar button on the Pantry hub, not a card; panes run Staples · Tools · Cellar & Bar · Sources (3.17, §2). Added Oct 17, 2026 from `Docs/Specs/ux-notes.md` row 15, amending 11.
25. **Edit glyph.** Toolbar buttons that open an editor use the pencil symbol, not the word Edit (§2). Added Oct 17, 2026 from `Docs/Specs/ux-notes.md` row 16.
26. **Title switch.** The Recipes large title is the Recipes · Books switch itself, the other view dimmed beside it; the segmented control goes (3.2, 3.7). Added Oct 17, 2026 from `Docs/Specs/ux-notes.md` row 21.

Still open: nothing from this document. UX notes gathered between Phase 1 slices live in `Docs/Specs/ux-notes.md`.
