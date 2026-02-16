# Spoons

Personal [Hammerspoon](https://www.hammerspoon.org/) Spoons.

## Installation

```lua
hs.loadSpoon("SpoonInstall")
spoon.SpoonInstall.repos.dbmrq = {
    url = "https://github.com/dbmrq/Spoons",
    desc = "dbmrq's Spoons",
}

spoon.SpoonInstall:andUse("WinMan", { repo = "dbmrq", start = true })
```

## Spoons

### WinMan

Grid-based window management with modal bindings inspired by Zellij.

**Zellij mode** (modal, like Zellij/tmux):
| Key | Mode | Actions |
|-----|------|---------|
| `Super+p` | Focus | `hjkl` focus, `f` maximize, `x` close |
| `Super+n` | Resize | `hjkl` resize edges |
| `Super+h` | Move | `hjkl` move, `123` screen, `c/a` cascade |
| `Super+t` | Spaces | `hl` switch, `n` new |

**Simple mode** (direct bindings): `HJKL` resize, arrows move, `;` maximize.

```lua
spoon.WinMan.mode = "zellij"  -- or "simple"
spoon.WinMan.modifiers = {"ctrl", "alt", "cmd"}
spoon.WinMan.gridSize = "6x6"
spoon.WinMan:start()
```

### CheatSheet

Shows hotkey hints when modifier keys are held. Auto-discovers hotkeys and supports modal mode hints from WinMan.

```lua
spoon.CheatSheet.modifiers = {"ctrl", "alt", "cmd"}
spoon.CheatSheet.delay = 0.5
spoon.CheatSheet:start()
```

### Collage

Clipboard manager in the menu bar. Tracks copy/cut history with custom submenus.

```lua
spoon.SpoonInstall:andUse("Collage", {
    repo = "dbmrq", start = true,
    fn = function(s)
        s:addSubmenu("Utils", {{ title = "Reload", fn = hs.reload }})
    end
})
```

### Readline

Emacs-style text editing keybindings system-wide.

| Key | Action |
|-----|--------|
| `Alt-f/b` | Word forward/back |
| `Alt-d` | Delete word forward |
| `Ctrl-w` | Delete word back |
| `Ctrl-u` | Kill to line start |

### SlowQ

Hold `Cmd+Q` for a countdown before quitting — prevents accidental closes.

```lua
spoon.SlowQ.delay = 4  -- seconds
```

## Development

```bash
./build.sh           # Build all
./build.sh WinMan    # Build one
```
