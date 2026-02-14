# Spoons

Personal [Hammerspoon](https://www.hammerspoon.org/) Spoons repository.

## Installation

Add this repository to SpoonInstall in your `~/.hammerspoon/init.lua`:

```lua
hs.loadSpoon("SpoonInstall")

spoon.SpoonInstall.repos.dbmrq = {
    url = "https://github.com/dbmrq/Spoons",
    desc = "dbmrq's Spoons",
}

-- Install and use Spoons from this repo
spoon.SpoonInstall:andUse("Readline", { repo = "dbmrq", start = true })
```

## Available Spoons

### Readline

Emacs/readline-style keybindings for text editing across macOS apps.

| Binding | Action | Description |
|---------|--------|-------------|
| `Alt-f` | wordForward | Move cursor forward one word |
| `Alt-b` | wordBackward | Move cursor backward one word |
| `Alt-Shift-f` | wordSelectForward | Select forward one word |
| `Alt-Shift-b` | wordSelectBackward | Select backward one word |
| `Alt-,` | docStart | Move to start of document |
| `Alt-.` | docEnd | Move to end of document |
| `Alt-d` | deleteWordForward | Delete word forward |
| `Ctrl-w` | deleteWordBackward | Delete word backward |
| `Ctrl-u` | killToStart | Kill from cursor to start of line |

#### Customization

Override bindings or disable specific ones:

```lua
spoon.SpoonInstall:andUse("Readline", {
    repo = "dbmrq",
    start = true,
    hotkeys = {
        -- Custom binding
        wordForward = {{"ctrl"}, "f"},
        -- Disable a binding
        killToStart = false,
    }
})
```

## Development

### Building

```bash
./build.sh           # Build all Spoons
./build.sh Readline  # Build specific Spoon
```

This creates `Spoons/*.spoon.zip` and generates `docs/docs.json`.

### Structure

```
Spoons/
├── Source/
│   └── Readline.spoon/
│       └── init.lua
├── Spoons/
│   └── Readline.spoon.zip   (generated)
├── docs/
│   └── docs.json            (generated)
├── build.sh
└── README.md
```

