import QtQuick

// The edit affordance, wherever it appears: Font Awesome's pencil (U+F040,
// from the Nerd Font the sidebar's icons come from), at its own diagonal.
// Turned upright it read as strange, so it stays as drawn.
Text {
  text: ""
  font.family: Theme.fontFamily
  font.pixelSize: Theme.subtitleSize
  color: Theme.dim
}
