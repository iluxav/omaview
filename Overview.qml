import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import qs.Commons
import qs.Ui

// omaview: every workspace at once, each drawn as a small copy of its monitor
// with its windows where they really sit, showing what is in them right now.
//
//   click a window      jump to it
//   click a workspace   switch to it
//   1-9                 switch to that workspace
//   Esc                 close
//
// Window pictures come from Hyprland's toplevel export, one capture per window.
// Windows on workspaces you are not looking at show the last frame they drew.
//
//   omarchy-shell shell toggle iluxav.omaview '{}'
Item {
  id: root

  property var shell: null
  property var manifest: null
  property string omarchyPath: Quickshell.env("OMARCHY_PATH")

  property bool opened: false
  property string screenName: ""
  property string hoverText: ""

  property color foreground: Color.menu.text
  property color scrim: Util.alpha(Color.menu.background, 0.94)
  property color accent: Color.menu.selectedText
  readonly property int cornerRadius: Style.cornerRadius
  property string fontFamily: Style.font.menuFamily
  readonly property int gap: Style.space(28)
  readonly property int labelHeight: Style.font.title + Style.space(10)

  function open(payloadJson) {
    Hyprland.refreshMonitors()
    Hyprland.refreshWorkspaces()
    Hyprland.refreshToplevels()
    root.screenName = Hyprland.focusedMonitor ? Hyprland.focusedMonitor.name : ""
    root.hoverText = ""
    root.opened = true
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function close() {
    root.opened = false
  }

  function toggle() {
    if (root.opened) root.close()
    else root.open("{}")
  }

  // ---- hyprland -----------------------------------------------------------

  function focusWindow(toplevel) {
    var address = String(toplevel.address || "")
    if (address.indexOf("0x") !== 0) address = "0x" + address
    root.close()
    Hyprland.dispatch(Hyprland.usingLua
      ? "hl.dsp.focus({ window = \"address:" + address + "\" })"
      : "focuswindow address:" + address)
  }

  function focusWorkspace(id) {
    root.close()
    Hyprland.dispatch(Hyprland.usingLua
      ? "hl.dsp.focus({ workspace = \"" + id + "\" })"
      : "workspace " + id)
  }

  function screenFor(name) {
    var screens = Quickshell.screens
    for (var i = 0; i < screens.length; i++) {
      if (screens[i].name === name) return screens[i]
    }
    return null
  }

  // The monitor's area in layout coordinates, the same space window
  // positions are in: scaled, and turned on its side when rotated.
  function monitorBox(monitor) {
    if (!monitor) return { x: 0, y: 0, w: 1920, h: 1080 }
    var ipc = monitor.lastIpcObject || {}
    var scale = Number(ipc.scale || monitor.scale || 1)
    var w = Number(ipc.width || monitor.width) / scale
    var h = Number(ipc.height || monitor.height) / scale
    var rotated = Number(ipc.transform || 0) % 2 === 1
    return {
      x: Number(ipc.x !== undefined ? ipc.x : monitor.x),
      y: Number(ipc.y !== undefined ? ipc.y : monitor.y),
      w: rotated ? h : w,
      h: rotated ? w : h
    }
  }

  // Real windows on a workspace, bottom first: tiled under floating, and
  // within each, the most recently focused on top.
  function windowsOn(workspaceId) {
    return Hyprland.toplevels.values.filter(function(t) {
      var ipc = t.lastIpcObject
      return ipc && ipc.workspace && ipc.workspace.id === workspaceId
        && ipc.at && ipc.size && ipc.mapped !== false && !ipc.hidden
    }).sort(function(a, b) {
      var fa = a.lastIpcObject.floating ? 1 : 0
      var fb = b.lastIpcObject.floating ? 1 : 0
      if (fa !== fb) return fa - fb
      return Number(b.lastIpcObject.focusHistoryID) - Number(a.lastIpcObject.focusHistoryID)
    })
  }

  // ---- layout -------------------------------------------------------------

  // Lay the workspaces out in centred rows, as large as will fit. Every tile
  // shares one height and takes its own monitor's shape, so a portrait
  // monitor's workspaces come out tall and narrow.
  function computeTiles(workspaces, width, height) {
    if (workspaces.length === 0 || width <= 0 || height <= 0) return []

    var boxes = workspaces.map(function(ws) { return root.monitorBox(ws.monitor) })
    var aspects = boxes.map(function(b) { return b.w / Math.max(1, b.h) })

    var lo = 40
    var hi = Math.min(height * 0.45, height - root.labelHeight)
    var best = null
    for (var step = 0; step < 24; step++) {
      var mid = (lo + hi) / 2
      var rows = root.flowRows(aspects, mid, width)
      var total = rows ? rows.length * (mid + root.labelHeight) + (rows.length - 1) * root.gap : Infinity
      if (rows && total <= height) {
        best = { h: mid, rows: rows }
        lo = mid
      } else {
        hi = mid
      }
    }
    if (!best) best = { h: lo, rows: root.flowRows(aspects, lo, width) || [aspects.map(function(_, i) { return i })] }

    var tiles = []
    var blockHeight = best.rows.length * (best.h + root.labelHeight) + (best.rows.length - 1) * root.gap
    var y = Math.max(0, (height - blockHeight) / 2)
    for (var r = 0; r < best.rows.length; r++) {
      var row = best.rows[r]
      var rowWidth = (row.length - 1) * root.gap
      for (var i = 0; i < row.length; i++) rowWidth += aspects[row[i]] * best.h
      var x = (width - rowWidth) / 2
      for (var j = 0; j < row.length; j++) {
        var index = row[j]
        var w = aspects[index] * best.h
        tiles.push({ workspace: workspaces[index], box: boxes[index], x: x, y: y, w: w, h: best.h })
        x += w + root.gap
      }
      y += best.h + root.labelHeight + root.gap
    }
    return tiles
  }

  function flowRows(aspects, tileHeight, width) {
    var rows = []
    var row = []
    var rowWidth = 0
    for (var i = 0; i < aspects.length; i++) {
      var w = aspects[i] * tileHeight
      if (w > width) return null
      if (row.length > 0 && rowWidth + root.gap + w > width) {
        rows.push(row)
        row = []
        rowWidth = 0
      }
      rowWidth += (row.length > 0 ? root.gap : 0) + w
      row.push(i)
    }
    if (row.length > 0) rows.push(row)
    return rows
  }

  readonly property var workspaces: Hyprland.workspaces.values
    .filter(function(ws) { return ws.id > 0 })
    .sort(function(a, b) { return a.id - b.id })

  // ---- window -------------------------------------------------------------

  PanelWindow {
    id: panel
    visible: root.opened
    screen: root.screenFor(root.screenName)
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "omaview"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore

    Rectangle {
      anchors.fill: parent
      color: root.scrim
    }

    MouseArea {
      anchors.fill: parent
      onClicked: root.close()
    }

    Item {
      id: keyCatcher
      anchors.fill: parent
      focus: true
      Keys.onPressed: function(event) {
        if (event.key === Qt.Key_Escape) {
          root.close()
          event.accepted = true
        } else if (event.key >= Qt.Key_1 && event.key <= Qt.Key_9) {
          root.focusWorkspace(event.key - Qt.Key_0)
          event.accepted = true
        }
      }
    }

    Item {
      id: stage
      anchors.fill: parent
      anchors.margins: Style.space(48)
      anchors.bottomMargin: Style.space(48) + hoverLabel.height

      Repeater {
        model: root.opened ? root.computeTiles(root.workspaces, stage.width, stage.height) : []

        delegate: Item {
          id: tile
          required property var modelData
          readonly property var workspace: modelData.workspace
          readonly property var box: modelData.box
          readonly property real ratio: modelData.w / Math.max(1, box.w)

          x: modelData.x
          y: modelData.y
          width: modelData.w
          height: modelData.h + root.labelHeight

          Text {
            id: label
            width: parent.width
            height: root.labelHeight
            text: tile.workspace.name
            color: tile.workspace.focused ? root.accent : root.foreground
            opacity: tile.workspace.active ? 1 : 0.7
            font.family: root.fontFamily
            font.pixelSize: Style.font.title
            font.bold: tile.workspace.focused
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
          }

          Rectangle {
            id: screenArea
            y: root.labelHeight
            width: tile.modelData.w
            height: tile.modelData.h
            radius: root.cornerRadius
            color: Util.alpha(root.foreground, workspaceArea.containsMouse ? 0.1 : 0.05)
            clip: true

            MouseArea {
              id: workspaceArea
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: root.focusWorkspace(tile.workspace.id)
              onContainsMouseChanged: if (containsMouse) root.hoverText = "Workspace " + tile.workspace.name
            }

            Repeater {
              model: root.windowsOn(tile.workspace.id)

              delegate: Rectangle {
                id: win
                required property var modelData
                readonly property var ipc: modelData.lastIpcObject
                readonly property var entry: DesktopEntries.heuristicLookup(String(ipc.class || ""))

                x: (ipc.at[0] - tile.box.x) * tile.ratio
                y: (ipc.at[1] - tile.box.y) * tile.ratio
                width: Math.max(4, ipc.size[0] * tile.ratio)
                height: Math.max(4, ipc.size[1] * tile.ratio)
                radius: Math.min(root.cornerRadius, 4)
                color: Util.alpha(root.foreground, 0.12)
                clip: true

                ScreencopyView {
                  id: capture
                  anchors.fill: parent
                  captureSource: root.opened ? win.modelData.wayland : null
                  live: true
                }

                // Until the first frame arrives, or for a window that cannot
                // be captured, show what it is.
                Column {
                  anchors.centerIn: parent
                  width: parent.width - Style.space(8)
                  spacing: Style.space(4)
                  visible: !capture.hasContent

                  Image {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: Math.min(win.width, win.height) * 0.35
                    height: width
                    sourceSize.width: width * 2
                    sourceSize.height: height * 2
                    source: win.entry && win.entry.icon ? Quickshell.iconPath(win.entry.icon, true) : ""
                    visible: source != ""
                  }

                  Text {
                    width: parent.width
                    text: win.entry ? win.entry.name : String(win.ipc.class || "")
                    color: root.foreground
                    opacity: 0.7
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideRight
                  }
                }

                Rectangle {
                  anchors.fill: parent
                  radius: parent.radius
                  color: "transparent"
                  border.width: windowArea.containsMouse ? 2 : (win.modelData.activated ? 1 : 0)
                  border.color: root.accent
                }

                MouseArea {
                  id: windowArea
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.focusWindow(win.modelData)
                  onContainsMouseChanged: if (containsMouse) root.hoverText = win.modelData.title || String(win.ipc.class || "")
                }
              }
            }

            Rectangle {
              anchors.fill: parent
              radius: parent.radius
              color: "transparent"
              // Every workspace gets an outline so neighbours read apart; the
              // ones on screen are brighter, and the one you are in is accented.
              border.width: tile.workspace.focused ? 2 : 1
              border.color: tile.workspace.focused ? root.accent
                : Util.alpha(root.foreground, tile.workspace.active ? 0.5 : 0.22)
            }
          }
        }
      }
    }

    Text {
      id: hoverLabel
      anchors.bottom: parent.bottom
      anchors.bottomMargin: Style.space(28)
      anchors.horizontalCenter: parent.horizontalCenter
      width: Math.min(implicitWidth, parent.width * 0.8)
      text: root.hoverText || "Click a window to jump to it · 1–9 switch workspace · Esc closes"
      color: root.foreground
      opacity: root.hoverText ? 0.9 : 0.5
      font.family: root.fontFamily
      font.pixelSize: Style.font.title
      elide: Text.ElideMiddle
    }
  }
}
