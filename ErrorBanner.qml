import QtQuick

// The app's write-error line: a failed write is never silent. It hangs at
// the top of the window, over whichever screen is showing, for a few seconds
// after show(), or until it is clicked.
//
// Padded like a Button's label, spaceMd a side and spaceSm above and below,
// and kept spaceLg in from the window's edges, close to the spaceMd it hangs
// below the top. spaceLg a side would make the banner roomier than any
// button, and spaceXl from the edges would keep a long message twice as far
// from the sides as from the top.
Rectangle {
  id: banner

  property string message: ""

  function show(text) {
    banner.message = text
    hideTimer.restart()
  }

  visible: banner.message.length > 0
  anchors.top: parent.top
  anchors.horizontalCenter: parent.horizontalCenter
  anchors.topMargin: Theme.spaceMd
  width: Math.min(parent.width - Theme.spaceLg * 2, bannerText.implicitWidth + Theme.spaceMd * 2)
  height: bannerText.implicitHeight + Theme.spaceSm * 2
  color: Theme.paper
  border.color: Theme.red
  border.width: Theme.borderWidth

  // Bounded by the box and wrapping, so a long message grows the banner
  // downwards instead of running out of the window at 720px. The box sizes
  // itself from the text's *implicit* (unwrapped) width and the text takes
  // its width from the box; sizing the box from the text's actual width
  // would be a binding loop.
  Text {
    id: bannerText
    anchors.centerIn: parent
    width: parent.width - Theme.spaceMd * 2
    wrapMode: Text.Wrap
    horizontalAlignment: Text.AlignHCenter
    text: banner.message
    font.family: Theme.fontFamily
    font.pixelSize: Theme.bodySmallSize
    color: Theme.red
  }

  MouseArea {
    anchors.fill: parent
    cursorShape: Qt.PointingHandCursor
    onClicked: banner.message = ""
  }

  Timer {
    id: hideTimer
    interval: 5000
    onTriggered: banner.message = ""
  }
}
