--- === Readline ===
---
--- Emacs/readline-style keybindings for text editing across macOS apps.
--- Provides word navigation, selection, deletion, and line kill commands.
---
--- Download: [https://github.com/dbmrq/Spoons/raw/master/Spoons/Readline.spoon.zip](https://github.com/dbmrq/Spoons/raw/master/Spoons/Readline.spoon.zip)

local obj = {}
obj.__index = obj

-- Metadata
obj.name = "Readline"
obj.version = "1.0"
obj.author = "Daniel Marques <danielbmarques@gmail.com>"
obj.license = "MIT"
obj.homepage = "https://github.com/dbmrq/Spoons"

--- Readline.actions
--- Variable
--- Table of action functions that can be called directly or bound to hotkeys.
--- Available actions: wordForward, wordBackward, wordSelectForward, wordSelectBackward,
--- docStart, docEnd, deleteWordForward, deleteWordBackward, killToStart
obj.actions = {
    wordForward = function()
        hs.eventtap.keyStroke({"alt"}, "Right")
    end,
    wordBackward = function()
        hs.eventtap.keyStroke({"alt"}, "Left")
    end,
    wordSelectForward = function()
        hs.eventtap.keyStroke({"alt", "shift"}, "Right")
    end,
    wordSelectBackward = function()
        hs.eventtap.keyStroke({"alt", "shift"}, "Left")
    end,
    docStart = function()
        hs.eventtap.keyStroke({"cmd"}, "Up")
    end,
    docEnd = function()
        hs.eventtap.keyStroke({"cmd"}, "Down")
    end,
    deleteWordForward = function()
        hs.eventtap.keyStroke({"alt"}, "ForwardDelete")
    end,
    deleteWordBackward = function()
        hs.eventtap.keyStroke({"alt"}, "Delete")
    end,
    killToStart = function()
        hs.eventtap.keyStroke({"cmd", "shift"}, "Left")
        hs.eventtap.keyStroke({}, "Delete")
    end,
}

--- Readline.defaultBindings
--- Variable
--- Default hotkey bindings. Format: actionName = {modifiers, key}
obj.defaultBindings = {
    wordForward       = {{"alt"}, "f"},
    wordBackward      = {{"alt"}, "b"},
    wordSelectForward = {{"alt", "shift"}, "f"},
    wordSelectBackward= {{"alt", "shift"}, "b"},
    docStart          = {{"alt"}, ","},
    docEnd            = {{"alt"}, "."},
    deleteWordForward = {{"alt"}, "d"},
    deleteWordBackward= {{"ctrl"}, "w"},
    killToStart       = {{"ctrl"}, "u"},
}

-- Internal: stored hotkeys for cleanup
obj._hotkeys = {}

--- Readline:bindHotkeys(mapping)
--- Method
--- Binds hotkeys for Readline actions
---
--- Parameters:
---  * mapping - (optional) Table mapping action names to hotkey specs {modifiers, key}.
---              If nil, uses defaultBindings. Set a binding to `false` to disable it.
---
--- Returns:
---  * The Readline object
function obj:bindHotkeys(mapping)
    -- Clear existing hotkeys
    for _, hk in ipairs(self._hotkeys) do
        hk:delete()
    end
    self._hotkeys = {}

    -- Merge with defaults
    local bindings = {}
    for action, binding in pairs(self.defaultBindings) do
        bindings[action] = binding
    end
    if mapping then
        for action, binding in pairs(mapping) do
            bindings[action] = binding
        end
    end

    -- Create hotkeys
    for action, binding in pairs(bindings) do
        if binding and self.actions[action] then
            local hk = hs.hotkey.new(binding[1], binding[2], self.actions[action])
            table.insert(self._hotkeys, hk)
        end
    end

    return self
end

--- Readline:start()
--- Method
--- Enables the Readline hotkeys
---
--- Returns:
---  * The Readline object
function obj:start()
    if #self._hotkeys == 0 then
        self:bindHotkeys()
    end
    for _, hk in ipairs(self._hotkeys) do
        hk:enable()
    end
    return self
end

--- Readline:stop()
--- Method
--- Disables the Readline hotkeys
---
--- Returns:
---  * The Readline object
function obj:stop()
    for _, hk in ipairs(self._hotkeys) do
        hk:disable()
    end
    return self
end

--- Readline:loadTest()
--- Method
--- Loads the test module. Run tests with spoon.Readline:loadTest().runE2E()
---
--- Returns:
---  * The test module
function obj:loadTest()
    local spoonPath = hs.spoons.scriptPath()
    return dofile(spoonPath .. "/test.lua")
end

return obj

