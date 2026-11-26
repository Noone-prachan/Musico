---
name: Musico
description: A native personal media archive for Windows and Android
colors:
  primary: "#465A4B"
  primary-soft: "#596C55"
  canvas: "#F3EEE4"
  surface-muted: "#E9E1D4"
  surface: "#EDE5D8"
  paper: "#FBF8F1"
  control-fill: "#FBF8F1"
  control-line: "#D4CABB"
  ink: "#29251F"
  soft-ink: "#4F493F"
  muted: "#71695E"
  line: "#D4CABB"
  secondary: "#98472F"
  category-tint: "#F2DED1"
  playback: "#596C55"
  success: "#546A43"
  subtle-surface: "#E9E1D4"
  error: "#9B3F35"
typography:
  display:
    fontFamily: "Manrope"
    fontSize: "36px"
    fontWeight: 700
    lineHeight: 1.08
    letterSpacing: "-1px"
  headline:
    fontFamily: "Manrope"
    fontSize: "26px"
    fontWeight: 700
    lineHeight: 1.15
    letterSpacing: "-0.55px"
  title:
    fontFamily: "Manrope"
    fontSize: "22px"
    fontWeight: 700
    letterSpacing: "-0.45px"
  body:
    fontFamily: "Manrope"
    fontSize: "14px"
    lineHeight: 1.4
  label:
    fontFamily: "Manrope"
    fontSize: "13px"
    fontWeight: 600
  mono:
    fontFamily: "IBM Plex Mono"
    fontSize: "10px"
rounded:
  sm: "9px"
  md: "11px"
  lg: "14px"
spacing:
  xs: "4px"
  sm: "8px"
  md: "16px"
  lg: "24px"
  xl: "32px"
components:
  button-primary:
    backgroundColor: "{colors.primary}"
    textColor: "#FFFFFF"
    typography: "{typography.label}"
    rounded: "{rounded.sm}"
    padding: "0 18px"
    height: "48px"
  button-secondary:
    backgroundColor: "{colors.paper}"
    textColor: "{colors.secondary}"
    typography: "{typography.label}"
    rounded: "{rounded.sm}"
    padding: "0 16px"
    height: "48px"
  input-search:
    backgroundColor: "{colors.paper}"
    textColor: "{colors.ink}"
    typography: "{typography.body}"
    rounded: "{rounded.sm}"
    padding: "14px 16px"
  quality-picker:
    backgroundColor: "{colors.control-fill}"
    textColor: "{colors.ink}"
    typography: "{typography.body}"
    rounded: "13px"
    padding: "11px 14px"
  surface-card:
    backgroundColor: "{colors.paper}"
    textColor: "{colors.ink}"
    rounded: "{rounded.md}"
    padding: "10px"
  nav-selected:
    backgroundColor: "{colors.category-tint}"
    textColor: "{colors.ink}"
    typography: "{typography.label}"
    rounded: "{rounded.md}"
    padding: "10px"
---

# Design System: Musico

## Overview

**Creative North Star: "The Warm Media Shelf"**

Musico is a place to keep local music and follow upcoming anime releases, not a
marketing dashboard. Warm paper surfaces, deep-pine controls, burnt-clay
secondary accents, and ink-dark type make the archive feel personal and easy
to browse; real artwork and release information remain the focus.

The Windows and Android shell keeps familiar platform navigation and a
persistent player. Actions name their purpose, playback and download states
remain visible, and source, schedule, and licensing details stay close to the
content they describe.

**Key Characteristics:**
- Cream and parchment neutrals carry the shell; deep pine marks primary
  actions, while burnt clay marks secondary actions and saved states.
- Content surfaces are warm, flat, and separated by fine sand-colored borders.
- Existing media art remains the strongest source of saturated color.
- The supplied Musico mark remains on its black field.
- Compact headers pair the mark with a nearby Manrope "Musico" wordmark.
- Navigation uses restrained outlined Material icons; selected destinations
  change color and surface rather than switching to a heavier filled glyph.

## Colors

Warm paper neutrals establish the archive; deep pine anchors primary actions,
with burnt clay for secondary actions and muted sage for playback.

### Primary
- **Deep Pine** (`primary`): Main actions, focus, and playback controls.

### Secondary
- **Burnt Clay** (`secondary`): Secondary buttons, selected icons, and saved
  states.

### Tertiary
- **Olive** (`playback`): Playback and available states.
- **Brick** (`error`): Recoverable errors and failed actions.

### Neutral
- **Oat Canvas** (`canvas`): The app's overall background.
- **Parchment** (`surface-muted`): Navigation backgrounds and subtle grouping.
- **Cream Paper** (`paper`): Cards, fields, menus, and dialogs.
- **Charcoal Ink** (`ink`): Primary text and icons.
- **Warm Ink** (`soft-ink`): Secondary content and unselected controls.
- **Warm Taupe** (`muted`): Supporting text and unavailable controls.
- **Sand Rule** (`line`): Surface edges and dividers.

### Named Rules
**The Album Art Rule.** Let actual media artwork provide broad, saturated
color; do not paint decorative gradients behind it.

**The Two-Accent Rule.** Use Deep Pine for primary actions and Burnt Clay for
secondary actions; neither becomes ambient decoration.

## Typography

**Display Font:** Manrope (with a sans-serif fallback)
**Body Font:** Manrope (with a sans-serif fallback)
**Label/Mono Font:** IBM Plex Mono (for measurements and compact data only)

**Character:** Manrope gives the interface a calm, sturdy reading voice.
IBM Plex Mono is limited to values where aligned numerals or compact data
improve scanning.

### Hierarchy
- **Display** (700, 36px, 1.08 line height): Destination headings.
- **Headline** (700, 26px, 1.15 line height): Feature and empty-state headings.
- **Title** (700, 22px): Section and primary item titles.
- **Body** (400, 14px, 1.4 line height): Descriptions, settings, and supporting copy.
- **Label** (600, 13px): Buttons, navigation, and compact control labels.
- **Data label** (400–500, 10–11px): Short durations, file sizes, and schedule values.

### Named Rules
**The One Voice Rule.** Keep interface headings and body copy in Manrope;
reserve monospace for actual data, not for decoration.

## Layout

Windows uses a 224px navigation sidebar and a persistent player dock. Android
uses compact bottom navigation and retains the player within the available
screen area. The shell switches to a navigation rail at 680px and the wider
desktop layout at 980px. Songs opens directly to the searchable track list;
Anime, TV Shows, and Movies open separate category-specific discovery pages;
imported videos stay in the device-local libraries. Playlists is a dedicated
destination with playlist cards and a clear route back to the filtered song
list. Compact Android navigation keeps Songs, Anime, TV, Movies, and More;
Settings remains in the top bar and More links to Playlists, Favorites, and
Watchlist. The desktop sidebar exposes each destination directly. Import and
YouTube download actions remain distinct in the Songs header. Active Android playback publishes
the current track and media controls to the system notification. The watchlist
groups titles by their next published date. Settings becomes a two-column
index on wide windows and remains a single sequence on narrow screens. Content
insets and section gaps generally use 16–28px, with 8–12px inside compact
groups.

## Elevation & Depth

Cards and navigation are flat at rest. Surface color and a fine border do the
separating; the interface has no ambient glow, faux paper texture, or
decorative shadow vocabulary.
Dialogs and anchored menus use restrained Material elevation to communicate
their temporary foreground layer.

### Named Rules
**The Flat Surface Rule.** Do not add a shadow to ordinary cards, list items,
or the player dock. Use a border and a surface-color change.

## Shapes

Controls use restrained rounded corners rather than pills by default: buttons
and fields use 9–10px radii, cards and navigation use about 11px, and larger
feature surfaces and dialogs use 14px. Thin neutral borders define surfaces;
avoid colored side rails and nested card frames.

## Components

### Buttons
- **Shape:** Compact corners, 9px radius.
- **Primary:** Deep Pine fill, white label, and a 48px minimum height.
- **Secondary:** Cream Paper fill, Burnt Clay label, and a 1px Sand Rule
  outline.
- **Focus / Disabled:** Keep a visible Deep Pine focus treatment; disabled actions
  remain recognizable without competing with enabled controls.

### Chips
- **Style:** Quiet neutral fill, compact label, and a Fine Border where the
  control is selectable.
- **State:** Selected filters use the Deep Pine action color; media categories
  may use the restrained clay treatment.

### Cards / Containers
- **Background:** Cream Paper on Oat Canvas.
- **Border:** Sand Rule, 1px; no resting shadow.
- **Internal Padding:** 10–16px for compact content, with wider spacing for
  featured content.
- **Lists:** Prefer full-width rows and dividers for release schedules,
  watchlists, and library tracks; reserve framed surfaces for focused controls
  and temporary tasks.

### Inputs / Fields
- **Style:** Cream Paper fill with a 1px Sand Rule and 9–10px radius.
- **Focus:** Change the border to Deep Pine; do not add a glow.
- **Error / Disabled:** Use the semantic error color or muted neutral state.

### Navigation
- **Windows:** A persistent desktop sidebar with a restrained selected row.
- **Android:** Songs, Watch, TV, Movies, and More on compact widths; Settings
  opens from the compact shell bar. Medium widths use a rail with all destinations.
- **Page identity:** The content heading carries the destination name. The
  compact shell bar carries connection status rather than repeating the title.
- **Songs:** Open on the searchable collection without placing a promotional
  hero ahead of owned media. Keep Playlists as a distinct destination and make
  the active playlist filter easy to clear.
- **Anime:** Keep current-season and upcoming titles on the Anime page, with
 horizontal artwork shelves for browseable catalog data.
- **TV Shows and Movies:** Keep online discovery distinct from device-local
  imported video libraries, and show each category's cards on its own page.
  Metadata never implies that media was downloaded.
- **Watchlist:** Separate dated titles from titles awaiting a published date;
  sort dated entries by their next release.

### Player Dock
The anchored player keeps artwork, title, progress, and transport controls
available without a glow or gradient panel. Use a paper surface and a single
top border.

### Video Quality Menu
The custom anchored picker presents resolution, codec, and estimated size
together. The selected quality uses a check mark and Burnt Clay state; keep the
menu keyboard- and accessibility-readable.

## Do's and Don'ts

### Do:
- **Do** use the supplied brand mark with its black field.
- **Do** let source artwork and real release data carry the content.
- **Do** keep playback, download progress, and source details close to the
  media item.
- **Do** use the same semantic colors and surface rules across Windows and
  Android.

### Don't:
- **Don't** use ambient gradients, glass blur, neon, or colored glow.
- **Don't** repeat a page title in both the shell bar and page content.
- **Don't** add shadows to ordinary cards, rows, or playback controls.
- **Don't** use monospace as a decorative interface voice.
- **Don't** add card shells when spacing and a divider are enough.
