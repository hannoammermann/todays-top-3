import QtQuick
import qs.Commons

// Terminal-style bracket tag: steps through `frames` on a plain Timer, then
// fires finished(). Shared by the completion and restore animations, which
// were previously ~40 duplicated lines each — same overlay, same
// frame-stepping Timer, same "hold on last frame then act" shape.
Item {
  id: root
  anchors.fill: parent

  property var frames: ["[    ]", "[ OK ]"]
  property int frameInterval: 90
  property int holdInterval: 150
  property int fontSize: Style.font.body
  property color idleColor: Color.foreground
  property color finishColor: Color.accent
  property string fontFamily: Style.font.family

  readonly property bool active: stepTimer.running || holdTimer.running
  property int frameIndex: 0

  signal finished()

  function start() {
    root.frameIndex = 0
    stepTimer.restart()
  }

  Rectangle {
    anchors.fill: parent
    radius: Style.cornerRadius
    color: Color.popups.background
    visible: root.active

    Text {
      anchors.centerIn: parent
      textFormat: Text.PlainText
      text: root.frames[root.frameIndex]
      font.family: root.fontFamily
      font.pixelSize: root.fontSize
      font.bold: root.frameIndex === root.frames.length - 1
      color: root.frameIndex === root.frames.length - 1 ? root.finishColor : root.idleColor
    }
  }

  Timer {
    id: stepTimer
    interval: root.frameInterval
    repeat: true
    onTriggered: {
      if (root.frameIndex < root.frames.length - 1) {
        root.frameIndex = root.frameIndex + 1
      } else {
        stepTimer.stop()
        holdTimer.restart()
      }
    }
  }

  Timer {
    id: holdTimer
    interval: root.holdInterval
    onTriggered: root.finished()
  }
}
