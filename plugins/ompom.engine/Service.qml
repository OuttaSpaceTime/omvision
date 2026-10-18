import QtQuick
import Quickshell
import Quickshell.Wayland

// Ompom's entry point for omarchy-shell (manifest.json): the cycle
// (Engine.qml) with its fullscreen blocking overlay (Overlay.qml) in a
// layer-shell surface of its own -- the same PanelWindow + WlrLayershell
// technique the lock screen and idle screensaver use -- rather than a
// separate summoned plugin. That keeps the block and the notes flow inside a
// single Wayland layer surface, so there's never a second layer-shell surface
// fighting it for exclusive keyboard focus. Engine, Overlay, NoteSection and
// OverlayButton are sibling files: QML resolves same-directory PascalCase
// files as types, no import needed.
Engine {
  id: root

  // Injected by omarchy-shell for first/third-party services. Unused here —
  // Ompom needs no host lookups — but declaring it matches the documented
  // service entry-point contract.
  property var shell: null

  PanelWindow {
    visible: root.overlayVisible
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "ompom-overlay"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore

    Overlay {
      anchors.fill: parent
      engine: root
    }
  }
}
