pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Omvision's own token singleton. Deliberately does NOT import qs.Commons —
// that module belongs to the omarchy-shell process and is not reachable from
// a standalone `qs -p` config. Reads the live omarchy theme when present and
// falls back to the documented Flexoki Light palette otherwise. Must never
// throw on a missing or malformed theme file.
QtObject {
  id: root

  readonly property string home: Quickshell.env("HOME")
  readonly property string themePath: home + "/.local/state/omarchy/current/theme/colors.toml"

  // ---- Flexoki Light fallback (spec §Tokens) -------------------------------
  readonly property string fallbackBackground: "#FFFCF0"
  readonly property string fallbackForeground: "#100F0F"
  readonly property string fallbackSecondaryInk: "#403E3C"
  readonly property string fallbackDim: "#6F6E69"
  readonly property string fallbackFaint: "#878580"
  readonly property string fallbackHairline: "#DAD8CC"
  readonly property string fallbackBorder: "#B7B5AC"
  readonly property string fallbackFill: "#F6F3E8"
  readonly property string fallbackAccent: "#205EA6"
  readonly property string fallbackAccentFill: "#E8EDF4"
  readonly property string fallbackRed: "#AF3029"

  // ---- live values, overwritten by loadColors() on a successful parse -----
  property bool themeLoaded: false
  property string mode: "light"
  property color background: fallbackBackground
  property color foreground: fallbackForeground
  property color accent: fallbackAccent
  property color mutedColor: fallbackDim
  property color redColor: fallbackRed

  function alpha(c, a) {
    return Qt.rgba(c.r, c.g, c.b, a)
  }

  // ---- readable secondary text -------------------------------------------
  // Secondary text is NOT the theme's `muted` key and NOT the foreground at
  // some pleasing-looking alpha. `muted` is omarchy's colour for muted UI
  // *elements* -- inactive marks, borders -- and on a light theme it is very
  // close to the background: Rosé Pine Dawn's is #cecacd on #faf4ed, which
  // renders body text at about 1.3:1. A fixed alpha is no better, because how
  // much contrast 50% buys depends entirely on how far apart that theme's
  // foreground and background are.
  //
  // So instead of choosing a colour and hoping, choose a contrast ratio and
  // solve for the colour: blend the foreground toward the background only as
  // far as the target ratio allows. Every theme then gets the lightest text
  // that is still readable on it, and a theme whose foreground cannot reach
  // the target simply gets the full foreground rather than an unreadable tint.
  function blend(fg, bg, a) {
    return Qt.rgba(fg.r * a + bg.r * (1 - a),
                   fg.g * a + bg.g * (1 - a),
                   fg.b * a + bg.b * (1 - a), 1)
  }

  function relativeLuminance(c) {
    function lin(v) { return v <= 0.03928 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4) }
    return 0.2126 * lin(c.r) + 0.7152 * lin(c.g) + 0.0722 * lin(c.b)
  }

  function contrastRatio(a, b) {
    var l1 = relativeLuminance(a), l2 = relativeLuminance(b)
    return (Math.max(l1, l2) + 0.05) / (Math.min(l1, l2) + 0.05)
  }

  // Lightest blend of fg over bg that still meets `target` contrast.
  function textForContrast(fg, bg, target) {
    if (contrastRatio(fg, bg) < target) return fg // as good as this theme gets
    var lo = 0, hi = 1
    for (var i = 0; i < 12; i++) {
      var mid = (lo + hi) / 2
      if (contrastRatio(blend(fg, bg, mid), bg) >= target) hi = mid
      else lo = mid
    }
    return blend(fg, bg, hi)
  }

  // Derived surfaces. When the live theme loaded, these are computed from
  // the alpha rule in the spec's "Surfaces" section (4/8/18/40%). When it
  // didn't, the literal Flexoki fallback hexes are used directly, since
  // those are given precisely in the spec.
  readonly property color paper: background
  readonly property color ink: foreground
  // Three steps of secondary text, each defined by the contrast it must keep
  // rather than by a colour. 4.5:1 is the AA floor for body text, and every
  // one of these is used at 10-13px, so none of them may sit below it; the
  // hierarchy comes from the gap between 7 and 5.5 and 4.5, not from letting
  // the quietest one become unreadable.
  readonly property color secondaryInk: textForContrast(foreground, background, 7.0)
  readonly property color dim: textForContrast(foreground, background, 5.5)
  readonly property color faint: textForContrast(foreground, background, 4.5)
  // The one deliberate exception to that floor: markdown syntax in the
  // journal (`#`, `-`, `1.`, `>`). It is not text to be read but the scaffold
  // around it, and it has to recede for the words to stand out -- at 4.5:1 it
  // sat barely lighter than the prose. 2:1 is what omawrite's markers measure
  // on the same paper.
  readonly property color markup: textForContrast(foreground, background, 2.0)
  readonly property color hairline: themeLoaded ? alpha(foreground, 0.14) : fallbackHairline
  readonly property color border: themeLoaded ? alpha(foreground, 0.40) : fallbackBorder
  readonly property color fill: themeLoaded ? alpha(foreground, 0.04) : fallbackFill
  readonly property color hoverFill: alpha(foreground, 0.08)
  readonly property color selectedFill: alpha(foreground, 0.18)
  readonly property color accentColor: accent
  readonly property color accentFill: themeLoaded ? alpha(accent, 0.12) : fallbackAccentFill
  readonly property color red: redColor

  // ---- type scale (spec §Tokens) -------------------------------------------
  // Sized against the journal, not against a toolbar. The app used to set its
  // text at 10-12px, which read as UI chrome next to the journal's 15pt page:
  // the screens around the writing felt like a different, busier app. Body
  // text is now 15px -- a notch under the journal's 20px so the writing stays
  // the largest text in the app -- and a screen's title is the one large thing
  // on it, the way a page has one heading.
  readonly property string fontFamily: "monospace"
  readonly property int captionSize: 12
  readonly property int bodySmallSize: 14
  readonly property int bodySize: 15
  readonly property int subtitleSize: 16
  readonly property int titleSize: 17
  readonly property int headingSize: 24
  readonly property int displaySize: 32

  // ---- spacing scale -------------------------------------------------------
  // One scale, 4px based, and every margin and gap in the app comes from it.
  // Before this the same decisions were spelled 2, 4, 6, 8, 10, 12, 14, 16,
  // 18, 20, 24 and 28 across ten files, which is how two rows that were meant
  // to match ended up a pixel or two apart and why nothing could be adjusted
  // globally. The steps are deliberately few: if a value here looks wrong for
  // a place, the fix is to pick the neighbouring step, not to type a number.
  readonly property int spaceXxs: 2   // hairline gaps inside a single line of text
  readonly property int spaceXs: 4    // between a label and the value under it
  readonly property int spaceSm: 8    // inside a control, between chips
  readonly property int spaceMd: 12   // between rows of related text
  readonly property int spaceLg: 16   // between controls in a row
  readonly property int spaceXl: 24   // between a screen's blocks
  readonly property int space2xl: 32  // a page's own margin
  readonly property int space3xl: 48
  readonly property int space4xl: 64  // the writing page's gutter

  // Named for what they are, defined by the scale. These are the ones a
  // screen should reach for; the raw steps above are for the gaps inside a
  // component that has no name of its own.
  // Every screen's page margin, the journal's included. It was the
  // journal's own gutter first: at 40px the column sat too close to the
  // window edge to read as a page, and 32 did the same to the other screens
  // once their text grew toward the journal's.
  readonly property int panelPadding: space4xl
  readonly property int sectionGap: space2xl   // between a header and its content
  readonly property int rowGap: spaceMd        // between list rows' contents
  readonly property int rowPadding: spaceXl    // a list row's text to its hairline

  // Wrapped prose -- a break note, a coaching summary -- is read, not
  // scanned, so it gets leading closer to the journal's. Single-line labels
  // keep the font's own line height: extra leading there only pushes a label
  // off the control or marker it sits beside.
  readonly property real proseLineHeight: 1.4

  // ---- geometry -------------------------------------------------------------
  readonly property int radius: 0
  // 32, not 28: at 15px a label in a 28px box touched its border top and
  // bottom. Still quiet -- 1px hairline, no fill (layout-rules §9).
  readonly property int controlHeight: 32
  // Small secondary actions (`+ task`, `copy`) and the inline field they
  // open. Was a typed 20 in each place, which a 15px label no longer fits.
  readonly property int smallControlHeight: 24
  // Every modal card. The dialogs were 440 and 520 and padded 16px, which
  // read as a cramped form once their text grew to match the pages behind.
  readonly property int dialogWidth: 560
  readonly property int hairlineWidth: 1
  readonly property int borderWidth: 1

  // ---- writing surface (Journal) -------------------------------------------
  // The journal is a writing tool, not a list screen: it gets its own type
  // size and its own measure rather than the 12px body size and full-width
  // text the rest of the app uses. Sized against omawrite side by side --
  // ~20px of text with a lot of air around it, not UI-sized type.
  //
  // This one size is in *points*, not pixels, and it is the only place in the
  // app that is. The markdown highlighter's character formats are point-sized
  // (that is how omawrite shrinks a hidden marker to 1pt), and mixing a
  // pixel-sized document font with point-sized character formats gives Qt two
  // different size systems to reconcile on the same run of text.
  readonly property real writingPointSize: 15

  // The measure is in characters, not pixels, so it survives a change of
  // writing size or font: the column is as wide as this many monospace
  // characters, and the screen only decides whether it fits.
  readonly property int writingColumns: 70

  // ---- the page column -----------------------------------------------------
  // Every screen sets its text in the journal's column: the same measure, on
  // the same vertical line in the window. Moving between Journal and Goals
  // then changes what is on the page, not where the page is, and the other
  // screens read as pages of the same notebook instead of a dashboard around
  // it. Full-width screens were rejected because a 1300px line of break notes
  // is not something anyone reads, and a column pinned to the rail because
  // it would put the journal's left edge and everyone else's in two places.
  //
  // The measure comes off the writing font, as the journal's always did, so
  // it follows the writing size instead of being a pixel number that
  // silently drifts from it.
  property FontMetrics writingMetrics: FontMetrics {
    font.family: root.fontFamily
    font.pointSize: root.writingPointSize
  }
  readonly property int pageMeasure: Math.round(writingMetrics.advanceWidth("0") * writingColumns)
  readonly property int railWidth: 64

  // The column's width inside an area `areaWidth` wide: the measure, or less
  // when the area can't hold it plus a margin on each side.
  function pageWidth(areaWidth) {
    return Math.max(0, Math.min(pageMeasure, areaWidth - panelPadding * 2))
  }

  // The column's x inside that area, given how far the area's left edge
  // sits from the window's (the rail, or 0 when the rail is hidden). Centred
  // on the *window*, not the area, so the column does not move when the rail
  // slides in or out -- only the area around it changes. At narrow widths it
  // stops at the area's own margin rather than sliding under the rail.
  function pageX(areaWidth, leftInset) {
    var w = pageWidth(areaWidth)
    var centred = Math.round((areaWidth + leftInset - w) / 2) - leftInset
    return Math.max(panelPadding, centred)
  }

  function parseToml(text) {
    var out = {}
    var lines = String(text || "").replace(/\r\n/g, "\n").split("\n")
    for (var i = 0; i < lines.length; i++) {
      var line = lines[i].replace(/\s+$/, "")
      var m = line.match(/^([A-Za-z0-9_-]+)\s*=\s*"([^"]*)"\s*$/)
      if (!m) continue
      out[m[1]] = m[2]
    }
    return out
  }

  function loadColors(text) {
    var t = parseToml(text)
    if (!t.background || !t.foreground || !t.accent) {
      themeLoaded = false
      return
    }
    background = t.background
    foreground = t.foreground
    accent = t.accent
    mutedColor = t.muted ? t.muted : fallbackDim
    redColor = t.red ? t.red : fallbackRed
    mode = t.mode ? t.mode : "light"
    themeLoaded = true
  }

  property FileView colorsFile: FileView {
    id: colorsFile
    path: root.themePath
    watchChanges: true
    printErrors: false
    onLoaded: root.loadColors(text())
    onLoadFailed: function(error) { root.themeLoaded = false }
  }
}
