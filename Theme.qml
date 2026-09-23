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
  readonly property color hairline: themeLoaded ? alpha(foreground, 0.14) : fallbackHairline
  readonly property color border: themeLoaded ? alpha(foreground, 0.40) : fallbackBorder
  readonly property color fill: themeLoaded ? alpha(foreground, 0.04) : fallbackFill
  readonly property color hoverFill: alpha(foreground, 0.08)
  readonly property color selectedFill: alpha(foreground, 0.18)
  readonly property color accentColor: accent
  readonly property color accentFill: themeLoaded ? alpha(accent, 0.12) : fallbackAccentFill
  readonly property color red: redColor

  // ---- type scale (spec §Tokens) -------------------------------------------
  readonly property string fontFamily: "monospace"
  readonly property int captionSize: 10
  readonly property int bodySmallSize: 11
  readonly property int bodySize: 12
  readonly property int subtitleSize: 13
  readonly property int titleSize: 14
  readonly property int headingSize: 16
  readonly property int displaySize: 24

  // ---- spacing / geometry ---------------------------------------------------
  readonly property int radius: 0
  readonly property int panelPadding: 18
  readonly property int rowGap: 8
  readonly property int controlHeight: 28
  readonly property int hairlineWidth: 1
  readonly property int borderWidth: 1

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
