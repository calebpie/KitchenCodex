# Layout metrics: iOS 27 and iPadOS 27, measured in RecipeCodex

**Provenance.** Measured Oct 20, 2026 in the iOS 27.0 simulator runtime (27.0, build 24A434) with Xcode 27.0 (27A266a), on **iPad Pro 13-inch (M5)** at **2×** (2064 × 2752 px = 1032 × 1376 pt) and **iPhone 17 Pro** at **3×** (1206 × 2622 px = 402 × 874 pt). Every pixel value in a screenshot was divided by that scale; all numbers below are points. Text size Large (the default), Increase Contrast off, status bar overridden to 09:41. App: RecipeCodex at `27076f3`, built with the working tree as it stood that day (including uncommitted edits to `AddCookbookView.swift`, `RecipeFilterList.swift` and `EscapeKey.swift` from another session), scheme RecipeCodex, Debug.

Apple's iOS and iPadOS 27 Figma kit ships no page templates and the HIG publishes no numbers for these layouts, so these values come from the app running in the Simulator. They describe what the system draws around RecipeCodex's content: sidebar, bars, sheets, lists, safe areas. Where a number is the app's own (a SwiftUI `.padding()`), the table says so.

## How the values were taken

- **Screenshots**: `xcrun simctl io <device> screenshot`, in `LayoutMetrics/`, named `<device>-<orientation>-<state>-<light|dark>.png`. Each table row names the screenshot its value came from.
- **Frames**: each screenshot has a same-named dump in `LayoutMetrics/frames/`, taken with lldb attached to the running app at the moment of the screenshot (`method/frames.lldb`). It lists every UIKit view in window coordinates (points), with corner radii, label fonts, scroll insets, the window's safe area, the status bar frame, the scale and the size classes. For the light captures, `*.vc.txt` (`method/vc.lldb`) lists each view controller's safe area, layout margins and readable-content guide, and `*.radii.txt` (`method/radii.lldb`) lists every view with a corner radius (layer radius or iOS 26+ `UICornerConfiguration`). Run any of them with `xcrun lldb --batch -p <pid> -s <file>`; the pid is the app's, from `xcrun simctl spawn <device> launchctl list`.
- **Pixels**: radii that no view reports (the iPad form sheet, the 44 pt glass groups) and the Dynamic Island were checked on the screenshots with `method/px.swift`, which prints colour runs along a row or column in points.
- **Driving the app**: rotation and taps came from a throwaway UI-test runner (`method/MetricsUITests.swift`), the sidebar was shown and hidden through `UITabBarController.sidebar.isHidden`, and recipes were opened through the app's Spotlight continuation. No app code changed.
- **Content**: the library is filtered to the three synthetic test recipes (a "Layout Metrics" tag added on the measuring simulators only), so no third-party photos or recipe text appear in this public repo. The system layout does not depend on content: an earlier pass with the full library gave the same frame for every system view (bars, sidebar, tab bars, glass groups, sheets, grabbers, safe areas); the one difference was the app's own Profile button in the sidebar's bottom bar (see the iPad landscape table).
- **Light and dark**: every light/dark pair was captured in the same state and the frame dumps diffed. The only differences are content heights from text rendering; **no system metric differs between light and dark**. Colours do, and are in [Colours](#colours-light-vs-dark).

## iPad Pro 13-inch (M5), landscape: 1376 × 1032 pt

| Metric | Value (pt) | Screenshot |
|---|---|---|
| Display corner radius | 30 | ipad13-landscape-sidebar-shown-light |
| Status bar height | 32 | ipad13-landscape-sidebar-shown-light |
| Safe-area insets (window), top / leading / bottom / trailing | 32 / 0 / 20 / 0 | ipad13-landscape-sidebar-hidden-light |
| **Sidebar** frame | x 0, y 0, 280 × 1032 | ipad13-landscape-sidebar-shown-light |
| Sidebar width (regular width) | **280** | ipad13-landscape-sidebar-shown-light |
| Sidebar inset from leading / top / bottom edge | 0 / 0 / 0 (flush, full height; the status bar draws over it) | ipad13-landscape-sidebar-shown-light |
| Sidebar corner radius | 0 (only the display's 30 pt corners clip it) | ipad13-landscape-sidebar-shown-light |
| Sidebar fill | translucent material, no divider at its trailing edge (border view 0 pt wide) | ipad13-landscape-sidebar-shown-light |
| Sidebar top bar | y 32, 280 × 54 | ipad13-landscape-sidebar-shown-light |
| Sidebar toggle button | 44 × 44 glass at x 226, y 32 (10 from the sidebar's trailing edge) | ipad13-landscape-sidebar-shown-light |
| Sidebar list: first row top | y 95 | ipad13-landscape-sidebar-shown-light |
| Sidebar row | 248 × 44 at x 16 (16 inset each side); section headers are 44 pt rows; 10 pt between sections | ipad13-landscape-sidebar-shown-light |
| Sidebar row text | label x 70 (54 from the row's leading edge), 17 pt | ipad13-landscape-sidebar-shown-light |
| Sidebar selected-row fill | 248 × 44 capsule, radius 22 | ipad13-landscape-sidebar-shown-light |
| Sidebar bottom bar (system container) | y 951, 280 × 81 (bottom 20 is the safe area) | ipad13-landscape-sidebar-shown-light |
| Sidebar bottom bar content (app's) | Profile glass button 53 × 53 at x 16, at the container's top (bottom edge 28 above the screen edge, from the app's 8 pt padding + 20 safe area). In these landscape captures, taken after rotating from portrait, the app's bar content measured 61 tall instead of 81 and the button sat 10 higher, at y 941; in portrait and in the full-library landscape pass it sat at the container's top | ipad13-landscape-sidebar-shown-light, ipad13-portrait-sidebar-shown-light |
| **Gap between sidebar and detail** | 0. The detail frame is full-bleed (x 0 to 1376) and runs under the sidebar; its content gets a 280 pt leading safe-area inset | ipad13-landscape-recipe-list-light |
| **Detail layout margins, sidebar shown** | leading **300** (280 + 20), trailing **20**; safe area leading 280 | ipad13-landscape-recipe-list-light |
| Detail readable-content guide, sidebar shown | x 380 to 1276 (896 wide) | ipad13-landscape-recipe-list-light |
| **Detail layout margins, sidebar hidden** | leading **20**, trailing **20**; safe area leading 0 | ipad13-landscape-sidebar-hidden-light |
| Detail readable-content guide, sidebar hidden | x 240 to 1136 (896 wide) | ipad13-landscape-sidebar-hidden-light |
| App grid and list content inset (not system) | 16 from the content edge (SwiftUI `.padding(.horizontal)`), so grid cards start at x 296 / 16, 4 pt left of the 300 / 20 margin | ipad13-landscape-sidebar-shown-light |
| **Navigation bar** | y **32** (directly under the status bar), height **54**, full width 1376 | ipad13-landscape-sidebar-shown-light |
| Large-title row | +52 under the bar (y 86 to 138); title label x 300 (sidebar shown) or 20 (hidden), 34 pt | ipad13-landscape-sidebar-shown-light |
| Content top inset under a large-title bar | 138 (32 + 54 + 52) | ipad13-landscape-sidebar-shown-light |
| Inline title | 17 pt, centred in the 54 pt bar | ipad13-landscape-sheet-light |
| Bar button group (trailing) | glass capsule 44 tall, radius 22; three items 155 wide; 10 from the trailing edge; buttons inside are 36 tall at y 36 (4 pt inset) | ipad13-landscape-sidebar-hidden-light |
| Back button (pushed detail) | 44 × 44 glass at x 290 (sidebar + 10) and y 32 | ipad13-landscape-recipe-detail-light |
| **Toolbar** (bottom bar items) | no bar view: items float. Cook button glass 153 × 44, bottom edge at y 1012 (20 above the screen edge), centred on the content area (x 828) | ipad13-landscape-recipe-detail-light |
| Floating tab bar (sidebar hidden) | y 32, height 44, radius 22; width follows its items: 428.5 for the five tabs, centred (x 473.75); items 36 tall, radius 18, 4 pt inset; sidebar button 56 × 36 at the bar's leading end | ipad13-landscape-sidebar-hidden-light |
| Plain list | rows full width with content from x 280; separators end 20 from the trailing edge; section header rows 40.5; row height follows content (90 here: app thumbnail and two lines) | ipad13-landscape-recipe-list-light |
| **Grouped list (inset grouped) section** | x 300 to 1356 (the layout margins), corner radius **26** | ipad13-landscape-grouped-list-light |
| Grouped list section top, no header | at the content top (y 138) | ipad13-landscape-grouped-list-light |
| Grouped list row height | 52 single line (form sheet rows); 70.5 with a subtitle line | ipad13-landscape-sheet-light, ipad13-landscape-grouped-list-light |
| Grouped list separator | from the text's leading edge to 20 short of the section's trailing edge | ipad13-landscape-grouped-list-light |
| **Sheet** (form sheet, `.sheet` in regular width) | 580 × 640, centred (x 398, y 196), corner radius **32** | ipad13-landscape-sheet-light |
| Sheet top inset | 196 (centred vertically) | ipad13-landscape-sheet-light |
| Sheet grabber | none in a form sheet | ipad13-landscape-sheet-light |
| Sheet navigation bar | 10 below the sheet's top edge, height 54; close and Save glass buttons 44 tall, 10 from the sheet's edges | ipad13-landscape-sheet-light |
| Sheet grouped rows | x 414 to 962 (16 inset from the sheet's edges), 52 tall | ipad13-landscape-sheet-light |
| Dimming behind a sheet | black at 20% in light (white content reads #CCCCCC); black over black in dark | ipad13-landscape-sheet-light |

## iPad Pro 13-inch (M5), portrait: 1032 × 1376 pt

| Metric | Value (pt) | Screenshot |
|---|---|---|
| Display corner radius | 30 | ipad13-portrait-sidebar-hidden-light |
| Status bar height | 32 | ipad13-portrait-sidebar-hidden-light |
| Safe-area insets, top / leading / bottom / trailing | 32 / 0 / 20 / 0 | ipad13-portrait-sidebar-hidden-light |
| Sidebar default | hidden; the tabs sit in the floating tab bar | ipad13-portrait-sidebar-hidden-light |
| Floating tab bar | y 32, height 44, radius 22; 428.5 wide for the five tabs, centred (x 301.75) | ipad13-portrait-sidebar-hidden-light |
| **Sidebar shown** | overlays the detail: 280 × 1376 at x 0, y 0, flush to the leading, top and bottom edges, radius 0; the detail does not move and is dimmed | ipad13-portrait-sidebar-shown-light |
| Sidebar contents | same rows, bars and insets as landscape (rows from y 95, 248 × 44 at x 16; bottom bar from y 1295, 81 tall) | ipad13-portrait-sidebar-shown-light |
| **Detail layout margins**, sidebar hidden or shown | leading **20**, trailing **20** (the overlay adds no safe area) | ipad13-portrait-sidebar-hidden-light, ipad13-portrait-sidebar-shown-light |
| Detail readable-content guide | x 68 to 964 (896 wide) | ipad13-portrait-sidebar-hidden-light |
| Navigation bar | y 32, height 54; large-title row +52; content top 138 | ipad13-portrait-sidebar-hidden-light |
| Bar button group (trailing) | 44 tall, 10 from the trailing edge (x 867 for three items) | ipad13-portrait-sidebar-hidden-light |
| Back button (pushed detail) | 44 × 44 at x 10, y 32 | ipad13-portrait-recipe-detail-light |
| Toolbar item (Cook) | 153 × 44 glass, bottom edge 20 above the screen edge, centred (x 516) | ipad13-portrait-recipe-detail-light |
| Sheet | not captured in portrait | n/a |

## iPhone 17 Pro, portrait: 402 × 874 pt

| Metric | Value (pt) | Screenshot |
|---|---|---|
| Display corner radius | 62 | iphone17pro-portrait-root-light |
| Status bar height | 54 | iphone17pro-portrait-root-light |
| **Dynamic Island** exclusion | about 124 × 37 pill (radius about 18.5) at x 139 to 263 (centred), top edge y about 13.8 (read from the display mask; no API reports it) | iphone17pro-portrait-display-mask |
| Safe-area insets, top / leading / bottom / trailing | 62 / 0 / 34 / 0 | iphone17pro-portrait-root-light |
| Layout margins | 16 / 16; readable-content guide x 16 to 386 | iphone17pro-portrait-root-light |
| **Navigation bar** | y **62** (8 below the status bar), height **54** | iphone17pro-portrait-root-light |
| Large-title row | +52 (y 116 to 168); title label x 16, 34 pt; content top 168 | iphone17pro-portrait-grouped-list-light |
| Content top under an inline bar | 116 (62 + 54) | iphone17pro-portrait-root-light |
| Bar button group (trailing) | glass capsule 44 tall; three items 155.33 wide; 16 from the trailing edge | iphone17pro-portrait-root-light |
| Back button | 44 × 44 glass at x 16, y 62 | iphone17pro-portrait-recipe-detail-light |
| **Tab bar** (bar view) | y 791, 402 × 83 (49 + 34 safe area); content bottom inset 83 | iphone17pro-portrait-root-light |
| Tab bar platter | 290 × 62 glass at x 21, y 791, radius **31**; tab buttons 76 × 54, radius 27, 4 pt inset; labels 10 pt | iphone17pro-portrait-root-light |
| Search tab | separate 62 × 62 glass circle at x 319, y 791, radius 31; 8 from the platter | iphone17pro-portrait-root-light |
| Tab bar insets from the screen edges | 21 leading, 21 trailing, 21 bottom (platter bottom at y 853) | iphone17pro-portrait-root-light |
| **Toolbar** (pushed detail) | the tab bar hides; items float with no bar view. Cook button glass 153 × 48, bottom edge at y 846 (28 above the screen edge); content bottom inset 86 | iphone17pro-portrait-recipe-detail-light |
| Plain list | rows full width; section header rows 40.33; row height follows content (90 here) | iphone17pro-portrait-recipe-list-light |
| **Grouped list section** | x 16 to 386 (16 insets), corner radius **26** | iphone17pro-portrait-grouped-list-light |
| Grouped list row height | 52 single line; 90.33 for these three-line rows | iphone17pro-portrait-sheet-large-light, iphone17pro-portrait-grouped-list-light |
| Grouped list separator | from the text's leading edge to 16 short of the section's trailing edge | iphone17pro-portrait-grouped-list-light |
| **Sheet, large detent** | x 0, y **62** (the safe-area top), 402 × 812, flush to the bottom; top corners radius **38** | iphone17pro-portrait-sheet-large-light |
| **Sheet grabber** | **60 × 4**, radius 2, 6 below the sheet's top edge, centred (x 171) | iphone17pro-portrait-sheet-large-light |
| Sheet navigation bar | 16 below the sheet's top edge, height 54 | iphone17pro-portrait-sheet-large-light |
| Sheet, medium detent | floats: laid out at 402 × 469.67, then scaled by 0.9602 to sit **8** from the leading, trailing and bottom edges (on screen 386 × 450.97, top at y 415.03); corner radii 38 top / 54 bottom in layout points (36.5 / 51.85 on screen); grabber 57.6 × 3.84 on screen | iphone17pro-portrait-sheet-medium-light |
| Dimming behind a sheet | black at 20% in light; black over black in dark | iphone17pro-portrait-sheet-large-light |

## iPhone 17 Pro, landscape: 874 × 402 pt (light only)

| Metric | Value (pt) | Screenshot |
|---|---|---|
| Status bar | hidden (height 0) | iphone17pro-landscape-root-light |
| Safe-area insets, top / leading / bottom / trailing | 0 / 62 / 20 / 62 | iphone17pro-landscape-root-light |
| Layout margins | 78 / 78 (62 + 16); readable-content guide x 78 to 796 | iphone17pro-landscape-root-light |
| Navigation bar | y 24, height 54; content top 78 | iphone17pro-landscape-root-light |
| Bar button group (trailing) | 44 tall, 155.33 wide, trailing edge at x 836 (38 from the screen edge) | iphone17pro-landscape-root-light |
| Tab bar (bar view) | y 338, 874 × 64 (44 + 20); content bottom inset 64 | iphone17pro-landscape-root-light |
| Tab bar platter | 346.67 × 44 at x 38, y 338, radius 22; Search 44 × 44 at x 792, radius 22; 38 from each side, 20 from the bottom | iphone17pro-landscape-root-light |

## Colours, light vs dark

Geometry is the same in both appearances. Sampled sRGB values; materials and glass take on what is behind them, so those samples hold only over a plain background.

| Surface | Light | Dark | Screenshot |
|---|---|---|---|
| Content background | #FFFFFF | #000000 | ipad13-landscape-sidebar-shown, iphone17pro-portrait-recipe-list |
| Sidebar material (over white or black content) | #E6EAEE | #191E21 | ipad13-landscape-sidebar-shown |
| Sidebar selected-row fill | #D1D6DA | #2E3336 | ipad13-landscape-sidebar-shown |
| Grouped background | #F2F2F7 | #000000 | ipad13-landscape-grouped-list, iphone17pro-portrait-grouped-list |
| Grouped cell | #FFFFFF | #1C1C1E | ipad13-landscape-grouped-list, iphone17pro-portrait-grouped-list |
| Grouped separator | #E8E8E8 | #38383B | ipad13-landscape-grouped-list |
| Sheet background (grouped content) | #F2F2F7 | #1C1C1E | ipad13-landscape-sheet, iphone17pro-portrait-sheet-large |
| Grouped cell inside a sheet | #FFFFFF | #2C2C2E | iphone17pro-portrait-sheet-large |
| Glass bar group / floating tab bar (over plain background) | #F9F9F9 | #1F1F1F | ipad13-landscape-sidebar-hidden |
| Floating tab bar selected item | #EBEBEB | #0A0A0A | ipad13-landscape-sidebar-hidden |
| Sheet grabber | #B7B7BF | #626268 | iphone17pro-portrait-sheet-large |
| Dimming | black 20% | black (over black) | ipad13-landscape-sheet, iphone17pro-portrait-sheet-large |

## Not in the app yet

- **Three columns (sidebar + content list + detail).** RecipeCodex has no `NavigationSplitView`: each sidebar tab is one wide column, and a recipe pushes over its grid or list. The width of a content-list column and the detail column beside it could not be measured.
- **Sheet in iPad portrait**, **iPhone landscape in dark**, a **bottom toolbar with several items** and a **search field in a bar** were not captured.
- **Hero image under the bar.** The synthetic recipes have no cached cover thumbnail, so the detail pages here show no hero. In the earlier full-library pass the hero ran full-bleed under the navigation bar (and, on iPad, under the sidebar).

## How to encode this in Figma

All values in points. "Absolute" means absolute positioning inside the parent frame; everything else is auto layout.

### 1. Compact iPhone (iPhone 17 Pro, portrait)

- **Device frame** 402 × 874, corner radius 62, clip content.
  - **Content** (auto layout, vertical), fills the frame: padding top 116 (inline bar) or 168 (large title), leading 16, trailing 16, bottom 83 (tab bar) or 86 (bottom toolbar).
    - Grouped section: full width of the padded area (16 insets), radius 26, rows 52 min, separator inset 16 at the trailing end.
  - **Status bar** (absolute) x 0, y 0, 402 × 54. Dynamic Island 124 × 37 pill at x 139, y 14.
  - **Navigation bar** (absolute) x 0, y 62, 402 × 54, padding leading 16, trailing 16. Back button 44 × 44 glass circle; trailing button group 44 tall, radius 22. Large title (when used) in a 52-tall row at y 116, text x 16, 34 pt.
  - **Tab bar** (absolute, anchored bottom): platter 290 × 62 at x 21, y 791, radius 31, padding 4, tab buttons 76 × 54 radius 27; Search circle 62 × 62 at x 319, y 791.
  - **Bottom toolbar** (replaces the tab bar on a pushed page): glass items 48 tall, bottom edge 28 above the screen edge, centred.
  - **Sheet, large**: frame x 0, y 62, 402 × 812, top corners 38; grabber 60 × 4 radius 2 at y 6 centred; sheet nav bar at y 16, 54 tall. **Sheet, medium**: 386 wide at x 8, 8 from the bottom, corners 36.5 top / 51.85 bottom (or a 402-wide frame with 38 / 54 scaled to 96.02%).

### 2. iPad with the sidebar over a full-bleed detail (iPad Pro 13-inch)

- **Device frame** 1376 × 1032 (landscape) or 1032 × 1376 (portrait), corner radius 30, clip content.
  - **Detail** (auto layout, vertical), x 0, y 0, filling the whole device frame: padding top 138 (32 status bar + 54 bar + 52 large title), trailing 20, bottom 20, leading **300** with the sidebar shown in landscape, **20** with it hidden, and **20** in portrait (the portrait sidebar overlays).
    - Grouped section spans the padded width, radius 26, rows 52 min. App grid and lists in RecipeCodex use 16 instead of 20 from the content edge.
    - **Navigation bar** (absolute in the detail) x 0, y 32, full width × 54. Back button 44 × 44 at x 290 (sidebar shown) or x 10 (hidden); trailing group 44 tall, radius 22, 10 from the trailing edge. Large-title text at x 300 or 20, row y 86 to 138.
    - **Floating tab bar** (absolute, sidebar hidden): y 32, 44 tall, radius 22, centred horizontally, width hugging its items (428.5 for five tabs); items 36 tall radius 18, padding 4.
    - **Toolbar item** (absolute): glass 44 tall, bottom edge 20 above the screen edge, centred on the detail's padded area.
  - **Sidebar** (absolute, above the detail) x 0, y 0, 280 × full height, no corner radius, material fill.
    - Top bar y 32, 54 tall; toggle button 44 × 44 at x 226.
    - List (auto layout, vertical) from y 95, padding 16 each side: rows 248 × 44, section headers 44, 10 between sections, selected-row capsule radius 22, label at 54 from the row edge.
    - Bottom bar (anchored bottom) 81 tall: Profile glass button 53 × 53 at x 16, 28 from the screen bottom.
  - **Form sheet** (absolute, centred): 580 × 640, radius 32; its nav bar 10 from its top, 54 tall, buttons 44 tall 10 from its edges; content padding 16; dimming layer black 20%.

### 3. iPad with sidebar, content list and detail

- **Device frame** 1376 × 1032, corner radius 30, clip content.
  - **Sidebar** (absolute) x 0, y 0, 280 × 1032, no radius, contents as in template 2 (measured).
  - **Content-list column** and **detail column**: widths not measured; RecipeCodex has no split view yet. Per column, the measured single-column values apply where the system sets them: status bar 32, navigation bar at y 32 and 54 tall, system minimum layout margin 20 at each side, bottom safe area 20.
