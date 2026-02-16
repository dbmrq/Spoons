--- === Readline ===
---
--- Emacs/readline-style keybindings for text editing across macOS apps.
--- Provides word navigation, selection, deletion, and line kill commands.
--- Hotkeys are only active when the focused element is a text input field.
---
--- Download: [https://github.com/dbmrq/Spoons/raw/master/Spoons/Readline.spoon.zip](https://github.com/dbmrq/Spoons/raw/master/Spoons/Readline.spoon.zip)

local obj = {}
obj.__index = obj

-- Metadata
obj.name = "Readline"
obj.version = "1.1"
obj.author = "Daniel Marques <danielbmarques@gmail.com>"
obj.license = "MIT"
obj.homepage = "https://github.com/dbmrq/Spoons"

-- Text input AXRoles that should trigger readline bindings
local TEXT_INPUT_ROLES = {
    AXTextField = true,
    AXTextArea = true,
    AXComboBox = true,
    AXSearchField = true,
}

--- Readline.excludedApps
--- Variable
--- Table of application bundle IDs where Readline hotkeys should never be active.
--- These are typically terminal emulators or apps with their own readline/vim bindings.
--- Default: { "com.apple.Terminal", "com.googlecode.iterm2", "com.mitchellh.ghostty", "org.alacritty" }
obj.excludedApps = {
    ["com.apple.Terminal"] = true,
    ["com.googlecode.iterm2"] = true,
    ["com.mitchellh.ghostty"] = true,
    ["org.alacritty"] = true,
    ["io.alacritty"] = true,
    ["net.kovidgoyal.kitty"] = true,
}

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

-- Internal state
obj._eventtap = nil
obj._bindings = nil

-- Check if the current focused element is a text input field
local function isTextInputFocused()
    -- Check if current app is excluded (terminal emulators, etc.)
    local app = hs.application.frontmostApplication()
    if app then
        local bundleID = app:bundleID()
        if bundleID and obj.excludedApps[bundleID] then
            return false
        end
    end

    -- Get the focused UI element
    local systemElement = hs.axuielement.systemWideElement()
    if not systemElement then return false end

    local focusedElement = systemElement:attributeValue("AXFocusedUIElement")
    if not focusedElement then return false end

    local role = focusedElement:attributeValue("AXRole")
    return role and TEXT_INPUT_ROLES[role] or false
end

-- Normalize modifier flags to a set of modifier names
local function normalizeModifiers(flags)
    local mods = {}
    if flags.alt or flags["⌥"] then mods.alt = true end
    if flags.ctrl or flags["⌃"] then mods.ctrl = true end
    if flags.cmd or flags["⌘"] then mods.cmd = true end
    if flags.shift or flags["⇧"] then mods.shift = true end
    return mods
end

-- Check if modifiers match (exact match)
local function modifiersMatch(eventMods, bindingMods)
    local eventSet = normalizeModifiers(eventMods)
    local bindingSet = {}
    for _, mod in ipairs(bindingMods) do
        bindingSet[mod] = true
    end
    -- Check exact match
    for _, mod in ipairs({"alt", "ctrl", "cmd", "shift"}) do
        if (eventSet[mod] or false) ~= (bindingSet[mod] or false) then
            return false
        end
    end
    return true
end

--- Readline:bindHotkeys(mapping)
--- Method
--- Configures the hotkey bindings for Readline actions
---
--- Parameters:
---  * mapping - (optional) Table mapping action names to hotkey specs {modifiers, key}.
---              If nil, uses defaultBindings. Set a binding to `false` to disable it.
---
--- Returns:
---  * The Readline object
function obj:bindHotkeys(mapping)
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

    -- Store processed bindings for the eventtap
    self._bindings = {}
    for action, binding in pairs(bindings) do
        if binding and self.actions[action] then
            table.insert(self._bindings, {
                modifiers = binding[1],
                key = binding[2]:lower(),
                action = self.actions[action],
            })
        end
    end

    return self
end

--- Readline:start()
--- Method
--- Enables the Readline hotkeys (only active in text input fields)
---
--- Returns:
---  * The Readline object
function obj:start()
    if not self._bindings then
        self:bindHotkeys()
    end

    if self._eventtap then
        self._eventtap:stop()
    end

    self._eventtap = hs.eventtap.new({hs.eventtap.event.types.keyDown}, function(event)
        -- Only process if we're in a text input field
        if not isTextInputFocused() then
            return false -- Let the event pass through
        end

        local keyCode = event:getKeyCode()
        local keyChar = hs.keycodes.map[keyCode]
        if not keyChar then return false end
        keyChar = keyChar:lower()

        local flags = event:getFlags()

        -- Check each binding
        for _, binding in ipairs(self._bindings) do
            if keyChar == binding.key and modifiersMatch(flags, binding.modifiers) then
                binding.action()
                return true -- Consume the event
            end
        end

        return false -- Let unmatched events pass through
    end)

    self._eventtap:start()
    return self
end

--- Readline:stop()
--- Method
--- Disables the Readline hotkeys
---
--- Returns:
---  * The Readline object
function obj:stop()
    if self._eventtap then
        self._eventtap:stop()
        self._eventtap = nil
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
