import QtQuick

// A label at caption size, bold: a section's or a field's name (`What
// happened`, `Tasks`, a dialog's `When`) in dim, sentence case
// (docs/ui-spec.md, Tokens), and with its own `color`, a badge (`running` in
// the accent, `Cancelled` and a deadline in red) or a day's header in ink.
// One type, so these can't drift apart in size or weight; it was the same
// five lines in over twenty places.
Text {
  font.family: Theme.fontFamily
  font.pixelSize: Theme.captionSize
  font.bold: true
  color: Theme.dim
}
