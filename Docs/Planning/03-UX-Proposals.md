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
| Toolbars | Group by function; at most three groups; symbols not text; one `.prominent` action on the trailing edge; large titles on iPhone | Every top-level screen: leading = sidebar toggle (iPad), center = title, trailing = Add (+) where the screen creates something, and More (⋯) for screen-level actions (view switch, sort, select, import and export). No profile button; profile and settings are a pane of Pantry. Detail screens: Back · title · Share, More; prominent Cook/Finalize/Done where applicable. |
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

**Purpose.** What is happening today in the kitchen. Fourth tab, to the right of Plan: by the time you reach it the menu is planned and shopped, so it opens on the active session, tonight's plan or today's prep tasks. The app launches on Cook when a session is active or an event is today, otherwise on Recipes.

**iPhone.** Large title "Cook." Top card: today's event (name, guests, seating time, "Start service" prominent) or, when none, "Nothing planned. Cook something new?" with three suggestions from never-cooked recipes that fit a weeknight. Below: today's prep tasks from any upcoming schedule as a checklist, running timers, and recently cooked. The Now Cooking accessory appears above the tab bar when a session is active.

**iPad.** Two columns: left the event and tasks, right suggestions and recents. Sidebar section "Today."

**States.** Empty (no events, no history): a warm first-run card linking to Import, Scan, and Pantry setup. Active session: the whole top is the session summary.

**HIG notes.** One primary action per card. No glass in cards. Suggestions labeled "Suggested" with a refresh action.

### 3.2 Recipes (library)

**Purpose.** Browse and filter the collection.

**iPhone.** Large title "Recipes," trailing Add (+) and More (⋯). Under the title, a two-segment view switch: **Recipes · Books**. The Recipes view is the library described here; the Books view is the shelf (3.7). Add is contextual: Import, Scan page and New recipe in the Recipes view; Add book (ISBN) in the Books view. More holds Grid/List, Sort, Select, and Import from Paprika or Mela. A horizontally scrolling row of filter chips (Course, Cuisine, Time, Dietary, Cooked state, Book, Tags) that open a filter sheet; active filters show as tokens. Content toggles between a two-column card grid (image-led) and a list (text-led). Cards show image, title, time, and a small badge for "Never cooked" or the book icon.

**iPad.** Three columns: sidebar (collections, smart collections, tags), list with filters, detail. Drag a recipe from the list onto a collection in the sidebar or into a menu in a second window.

**Interactions.** Long-press for context menu. Pull down to reveal the search field? No: search is the Search tab; the Recipes screen has a filter, not a search, to honor the "one place to search" guidance. Swipe actions: Favorite, Add to list.

**HIG notes.** Filter chips are a scope bar in spirit; they never hide the content. Grid cells have concentric corner radii. Images extend under the floating bars with a scroll edge effect.

### 3.3 Recipe detail

**Purpose.** Read, scale, and start cooking.

**iPhone.** Hero image extends under the navigation bar. Title, source badge (book cover thumbnail + "p. 112" or site favicon + name), author. Metadata row: stated time / observed time, yield, difficulty, cooked count with "last: Seattle, Mar 2026" or "Never cooked" badge. Servings stepper rescales ingredients live with friendly rounding and a US/metric toggle. Ingredients list with checkboxes (for shopping and for mise en place), grouped by component (sub-recipes inline with a link to their own page). Steps numbered, with times and temperatures highlighted; a step with a photo shows a thumbnail at its trailing edge, tap to enlarge, swipe between the source's photo and your own. Collapsed sections: Headnote, Reader tips, Nutrition (Estimate), Versions, Cook log. Bottom toolbar: Share · Add to menu · **Cook** (prominent).

**iPad.** Same content in the detail column with ingredients and steps side by side when the width allows; the hero is smaller. A background extension effect carries the hero under the sidebar.

**States.** Imported with low confidence: a yellow "Check 2 ingredients" row at the top that scrolls to the suspect items. Scanned: a "View page" button opens the original image.

**HIG notes.** One prominent action (Cook). Large title collapses on scroll. Highlighted times are buttons, not just color.

### 3.4 Add menu and import preview

**Purpose.** One entry point for every capture method.

Add (+) presents a menu: Import from link, Scan page, Scan book, New recipe, From photo or PDF. The Share Extension and the in-app browser show the same import preview sheet: image, title, source, detected yield and times, "Save" prominent, "Edit first" secondary, and a one-line status such as "Found a recipe on this page" or "No recipe data; read the page instead."

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

**Books view.** The Books segment of the Recipes tab (3.2); the large title stays "Recipes" with the view switch beneath it. Grid of covers with a thin completeness bar under each (47/112). Filters: cuisine, author, completeness, needs review. Add (+) scans an ISBN.

**Book detail.** Cover, title, author, year, ISBN, completeness ring with "47 of 112 captured, 3 need review." Segmented control: Sections · Index · Missing. Sections list shows chapters with "8 of 12" counts; tapping a recipe opens it or, if not captured, offers "Scan now" with the page number. Primary action: **Continue scanning** (prominent). More: Edit book info, Export list, Scan sources page (each supplier on the book's Sources page becomes a Source in Pantry, linked to this book).

### 3.8 Book scanning session (iPad-first, works on iPhone)

**Purpose.** Capture a whole book in one sitting without losing your place.

**iPad.** Three regions: left, the punchlist with status dots and page numbers, current item highlighted; center, the camera with the quality pill; right, the last capture's recognized structure and a "Needs review" toggle. A status strip at the bottom: "12 captured · 9 processed · 2 need review · battery 64%." Pausing is one tap; the session resumes exactly here.

**iPhone.** The punchlist collapses to a compact header ("Now: Braised Short Ribs, p. 114 · 12 of 112") with a tap to open it as a sheet; camera fills the rest.

**HIG notes.** Full-screen, immersive, but with a persistent Close and a reliable way back to the list. Progress text is specific.

### 3.9 Event and menu builder

**Purpose.** Compose a balanced menu for real people.

**iPhone.** Event header card (date, arrival, seating, guests with restriction chips, kitchen). Date and times are set here and stay editable until service starts; once the event is in service they are fixed, and the debrief records the actual times. Slots listed as sections: Starter, Main, Sides, Dessert, Drinks, plus Add slot. Each slot shows candidate cards (image, name, servings stepper, finalize checkmark) and an Add button that opens a library picker sheet. Sub-recipes appear indented under their parent with a link icon. Inline notes under cards: "Never cooked," "Contains flour (Rosa)," "Oven conflict with the gratin." A Balance card summarizes coverage, servings vs guests, complexity load, and work after arrival. Bottom toolbar: Ask Codex · Shopping · **Finalize** (prominent, enabled when every slot has exactly one finalized candidate or is marked optional).

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

**Purpose.** Everything you have to cook with, in one tab: ingredients, tools, suppliers, bottles, kitchens and your own settings. Planning and shopping read from it.

**iPhone.** Large title "Pantry," trailing Add (+) and More (⋯), both contextual to the pane. Under the title, a scrolling pane selector (Pantry · Tools · Sources · Cellar & Bar · Kitchens · Profile) in the same chip style as the Recipes filters; it opens on Pantry. Each pane is a grouped list:

- **Pantry.** Ingredients grouped by store section, each with an in-stock toggle and a staple flag; swipe to add to the current shopping list. "Used up" marks from cook mode land here. Low staples show a dot.
- **Tools.** Checklist with counts and capacities (two ovens, five burners, a 7-quart Dutch oven), per kitchen. Feeds the scheduler's resource limits and the recipe "needs" badges.
- **Sources.** Stores you frequent and specialty suppliers, grouped Equipment · Food · Drink the way cookbooks print them: name, what they carry, phone, website, address. Added by hand, from a URL, or by scanning a book's Sources page (3.7), in which case the book is shown as the origin. A **Frequented** toggle makes a store a shopping stop (3.10); an ingredient can name a preferred source. Row actions: Call, Website, Directions, Add to stops.
- **Cellar & Bar.** Two segments. Cellar: wine by color, region and vintage with bottle counts, a drink-by note and an "open" state. Bar: spirits, liqueurs, mixers and bitters. Add by hand or from a label photo (Vision reads producer and vintage; you confirm). Pairings in the menu builder (3.9) pick from here and show "on hand" or "to buy."
- **Kitchens.** Home and others (a rental, a friend's), each with its own tools and pantry; the active kitchen is the default for new events.
- **Profile.** Proficiency (three options with a sentence each), units, voice and hands-free, kitchen theme (toggle), intelligence (model choice and what is shared), export and backup. Guests stay under Plan, where they are used.

**iPad.** The panes are sidebar sections; three columns for Sources and Cellar & Bar (group, list, detail), two for the rest.

**HIG notes.** Toggles for state that is read elsewhere (in stock, frequented, open), never buttons. Phone numbers and websites are tappable detail rows, not raw text. The pane selector is a view filter, not navigation: Back always returns to the previous tab, never the previous pane.

### 3.18 Search

A search field at the bottom on iPhone (search tab), suggestions before typing (recent, "Never cooked," "Cooked in Seattle," books), and results grouped by Recipes, Books, Events, Ingredients, Sources. A natural-language phrase shows its interpretation as tokens above the results ("vegetable · side · Seattle · Jan–Apr 2026") that you can remove individually. On iPad the field is top trailing.

### 3.19 First run

Three skippable screens (tools, proficiency, pantry), then the Recipes tab, whose empty state leads to Import, Scan or New recipe. No account creation; iCloud is already there. Everything from first run is editable later in Pantry.

## 4. iPad specifics

- **Navigation.** Top tab bar convertible to sidebar; sidebar sections per tab; user collections pinnable. Three-column `NavigationSplitView` for Recipes (both views) and for Pantry's Sources and Cellar & Bar; two-column for Plan.
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

Still open:

1. Pantry pane selector on iPhone: chips under the title (proposed), or a segmented control for the four most-used panes with the rest in More?
