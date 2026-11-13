# Omaview

Every workspace at once, each drawn as a small copy of its monitor with its
windows where they really sit, showing what is in them. Click a window to jump
to it. It is Omarchy's take on macOS Mission Control.

- Each window is a live picture of that window, not an app name or icon.
- Workspaces keep their monitor's shape, so a portrait monitor's workspaces
  come out tall and narrow.
- The overview opens on the monitor you are using and shows the workspaces of
  every monitor.

What it can do today and what has changed: [osfeed.dev/p/iluxav/omaview](https://osfeed.dev/p/iluxav/omaview).

## Install

```bash
omarchy plugin add https://github.com/iluxav/omaview.git --enable
```

Then give it a key in `~/.config/hypr/bindings.lua`:

```lua
o.bind("SUPER + GRAVE", "Overview", "omarchy-shell shell toggle iluxav.omaview '{}'")
```

## Use

| Action | Result |
|---|---|
| Click a window | Jump to it, switching workspace and monitor if needed |
| Click empty space in a workspace | Switch to that workspace |
| 1–9 | Switch to that workspace |
| Esc, or click outside | Close |

Hovering a window shows its title at the bottom of the screen.

## How it works

Window positions come from Hyprland, and the pictures from Hyprland's toplevel
export, one capture per window, through Quickshell's `ScreencopyView`. Windows
on workspaces you are not looking at do not redraw, so they show the last frame
they drew. Captures run only while the overview is open.

## Limits

- Special workspaces (scratchpads) are not shown.
- Windows tabbed inside a group show only the visible tab.

## Requirements

Omarchy on Hyprland.

## License

MIT
