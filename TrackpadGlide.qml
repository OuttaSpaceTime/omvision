import QtQuick

// Kinetic scrolling for the trackpad, on the Flickable this is put in
// (`flickable`). Other apps keep gliding after you lift your fingers; Qt
// Quick on Wayland does not: the compositor sends no momentum events, only
// ScrollEnd, and Flickable just stops there. So Flickable keeps tracking the
// fingers 1:1 itself, and this handler only watches -- `blocking: false`
// passes every event on to it -- measuring how fast the page was moving and,
// on ScrollEnd, throwing it on at that speed.
//
// Taking the whole gesture over instead was rejected: Flickable would still
// see ScrollBegin (it carries no delta, so this handler declines it) but
// never the matching ScrollEnd, and be left mid-drag. Mouse wheel events
// (NoScrollPhase) are left alone too, to Qt's own wheel handling.
// acceptedDevices must name TouchPad: Qt's Wayland backend marks trackpad
// scrolls as synthesized, which a WheelHandler ignores by default.
WheelHandler {
  id: glide

  property Flickable flickable: null

  target: null
  blocking: false
  acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad

  // Velocity is read over the last `windowMs` ms of the gesture; if the
  // fingers rested longer than `restMs` before lifting, there is no glide,
  // so a careful scroll to a spot stays put.
  readonly property int windowMs: 80
  readonly property int restMs: 50
  readonly property real boost: 1.5
  readonly property real minVelocity: 100
  property var samples: []

  onWheel: (event) => {
    const now = Date.now()
    if (event.phase === Qt.ScrollUpdate) {
      samples.push({ t: now, dy: event.pixelDelta.y })
      while (samples.length > 0 && now - samples[0].t > windowMs) samples.shift()
    } else if (event.phase === Qt.ScrollEnd) {
      const s = samples
      samples = []
      if (s.length < 2 || now - s[s.length - 1].t > restMs) return
      let dy = 0
      for (let i = 1; i < s.length; ++i) dy += s[i].dy
      const ms = s[s.length - 1].t - s[0].t
      if (ms <= 0) return
      const v = dy / ms * 1000 * boost
      if (Math.abs(v) < minVelocity) return
      // Later, not now: Flickable handles this same ScrollEnd right after
      // us, and its returnToBounds() can reset the timeline a flick started
      // here would run on. Putting fingers back down (ScrollBegin) resets it
      // on purpose, which catches the glide.
      Qt.callLater(() => glide.flickable.flick(0, v))
    }
  }
}
