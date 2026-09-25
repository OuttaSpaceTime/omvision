import QtQuick
import qs.Commons
import MarkdownHighlight

// Omvision's journal highlighter, on the overlay's two writing surfaces (the
// intent line and the break notes), so writing here looks exactly like
// writing in the journal: same module, same settings. The module is
// ~/Code/omvision/highlighter, built there and deployed into this plugin's
// native/ directory, which is already on omarchy-shell's QML2_IMPORT_PATH
// (see native/README.md). It replaces this plugin's own Ompom.Highlight,
// which drew markdown differently; keeping two highlighters meant the
// overlay and the journal never quite matched.
//
// In a file of its own, loaded through a Loader, because a QML import
// failure takes the whole importing file down: if the module is missing,
// the overlay loses its styling and nothing else.
//
// The values mirror omvision's JournalHighlight.qml. Colours can't come
// from omvision's Theme singleton, which isn't reachable from inside
// omarchy-shell, so they are solved here the same way Theme solves them:
// by contrast against the overlay's background rather than by a fixed
// alpha. They are bindings, so a theme switch restyles live text.
MarkdownHighlighter {
  // Service.qml sets this from its writingPointSize.
  basePointSize: 15
  // Percent. omvision measured 135 against omawrite: lists stay one list,
  // a blank line still opens a clear gap. See JournalHighlight.qml.
  lineHeight: 135
  bodyColor: Color.popups.text
  markerColor: textForContrast(Color.popups.text, Color.background, 2.0)
  accentColor: Color.accent
  quoteColor: textForContrast(Color.popups.text, Color.background, 4.5)
  codeColor: Color.popups.text
  codeBackground: Util.alpha(Color.popups.text, 0.04)

  // Same functions as omvision's Theme.qml: blend the text toward the
  // background only as far as the target contrast ratio allows.
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

  function textForContrast(fg, bg, target) {
    if (contrastRatio(fg, bg) < target) return fg
    var lo = 0, hi = 1
    for (var i = 0; i < 12; i++) {
      var mid = (lo + hi) / 2
      if (contrastRatio(blend(fg, bg, mid), bg) >= target) hi = mid
      else lo = mid
    }
    return blend(fg, bg, hi)
  }
}
