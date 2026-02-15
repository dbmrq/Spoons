--- === CheatSheet ===
---
--- Display a cheat sheet of keyboard shortcuts when modifier keys are held.
--- Automatically discovers hotkeys registered with Hammerspoon and displays
--- only those matching the configured modifiers.
---
--- Download: [https://github.com/dbmrq/Spoons/raw/master/Spoons/CheatSheet.spoon.zip](https://github.com/dbmrq/Spoons/raw/master/Spoons/CheatSheet.spoon.zip)

local obj = {}
obj.__index = obj

-- Metadata
obj.name = "CheatSheet"
obj.version = "1.0"
obj.author = "Daniel Marques <danielbmarques@gmail.com>"
obj.license = "MIT"
obj.homepage = "https://github.com/dbmrq/Spoons"

---------------------------------------------------------------------------
-- Configuration Variables
---------------------------------------------------------------------------

--- CheatSheet.modifiers
--- Variable
--- Table of modifier keys to watch. When all these modifiers (and only these)
--- are held, the cheat sheet appears. Default: {"ctrl", "alt", "cmd"}
obj.modifiers = {"ctrl", "alt", "cmd"}

--- CheatSheet.delay
--- Variable
--- Seconds to wait before showing cheat sheet after modifiers are pressed.
--- Default: 0.3
obj.delay = 0.3

--- CheatSheet.bgColor
--- Variable
--- Background color for the cheat sheet. Default: semi-transparent black
obj.bgColor = {red = 0, green = 0, blue = 0, alpha = 0.85}

--- CheatSheet.textColor
--- Variable
--- Text color for shortcuts. Default: white
obj.textColor = {red = 1, green = 1, blue = 1, alpha = 1}

--- CheatSheet.highlightColor
--- Variable
--- Color for key labels. Default: yellow
obj.highlightColor = {red = 1, green = 0.8, blue = 0.2, alpha = 1}

--- CheatSheet.font
--- Variable
--- Font for the cheat sheet text. Default: SF Pro
obj.font = "SF Pro"

--- CheatSheet.fontSize
--- Variable
--- Font size for the cheat sheet. Default: 14
obj.fontSize = 14

--- CheatSheet.position
--- Variable
--- Position of the cheat sheet on screen. Options: "center", "bottomLeft",
--- "bottomRight", "topLeft", "topRight". Default: "bottomLeft"
obj.position = "bottomLeft"

--- CheatSheet.keyOrder
--- Variable
--- Custom ordering for keys. Keys listed here appear first in this order.
--- Keys not listed are sorted alphabetically after these.
--- Default: logical grouping for common keys
obj.keyOrder = {
    -- Vim-style navigation (hjkl)
    "H", "J", "K", "L",
    -- Arrow keys
    "Left", "Down", "Up", "Right",
    -- Numbers
    "1", "2", "3", "4", "5", "6", "7", "8", "9", "0",
    -- Letters (alphabetically for the rest)
}

---------------------------------------------------------------------------
-- Internal State
---------------------------------------------------------------------------

obj._canvas = nil
obj._eventtap = nil
obj._timer = nil
obj._visible = false
obj._modFlags = {}

---------------------------------------------------------------------------
-- Modifier Utilities
---------------------------------------------------------------------------

-- Normalize modifier names to eventtap flag names
local modifierMap = {
    cmd = "cmd", command = "cmd",
    ctrl = "ctrl", control = "ctrl",
    alt = "alt", option = "alt",
    shift = "shift",
}

-- Symbol map for display
local modifierSymbols = {
    cmd = "⌘", ctrl = "⌃", alt = "⌥", shift = "⇧",
}

-- Convert modifier table to normalized set
local function normalizeModifiers(mods)
    local normalized = {}
    for _, mod in ipairs(mods) do
        local norm = modifierMap[mod:lower()]
        if norm then normalized[norm] = true end
    end
    return normalized
end

-- Check if current flags exactly match target modifiers
local function flagsMatchModifiers(flags, targetMods)
    local relevantFlags = {"cmd", "ctrl", "alt", "shift"}
    for _, flag in ipairs(relevantFlags) do
        local flagSet = flags[flag] or false
        local targetSet = targetMods[flag] or false
        if flagSet ~= targetSet then return false end
    end
    return true
end

-- Parse hotkey idx string to extract modifiers and key
local function parseHotkeyIdx(idx)
    local mods = {}
    local key = idx
    for symbol, name in pairs({["⌘"] = "cmd", ["⌃"] = "ctrl", ["⌥"] = "alt", ["⇧"] = "shift"}) do
        if idx:find(symbol, 1, true) then
            mods[name] = true
            key = key:gsub(symbol, "")
        end
    end
    return mods, key
end

-- Check if hotkey modifiers match our target modifiers
local function hotkeyMatchesModifiers(idx, targetMods)
    local hotkeyMods, _ = parseHotkeyIdx(idx)
    for mod, _ in pairs(targetMods) do
        if not hotkeyMods[mod] then return false end
    end
    for mod, _ in pairs(hotkeyMods) do
        if not targetMods[mod] then return false end
    end
    return true
end

-- Format modifier symbols for display
local function formatModifiers(mods)
    local order = {"ctrl", "alt", "shift", "cmd"}
    local result = ""
    for _, mod in ipairs(order) do
        if mods[mod] then result = result .. modifierSymbols[mod] end
    end
    return result
end

---------------------------------------------------------------------------
-- Hotkey Discovery
---------------------------------------------------------------------------

-- Get all hotkeys matching our modifiers
local function getMatchingHotkeys(targetMods, keyOrder)
    local hotkeys = hs.hotkey.getHotkeys()
    local matching = {}

    for _, hk in ipairs(hotkeys) do
        if hotkeyMatchesModifiers(hk.idx, targetMods) then
            local _, key = parseHotkeyIdx(hk.idx)
            -- Extract description from msg (format: "idx description" or just "idx")
            local desc = hk.msg or ""
            -- Remove the idx prefix if present
            desc = desc:gsub("^" .. hk.idx:gsub("([%%%^%$%(%)%.%[%]%*%+%-%?])", "%%%1") .. "%s*", "")
            if desc == "" then desc = key end
            table.insert(matching, {key = key, desc = desc})
        end
    end

    -- Build key order lookup table
    local orderLookup = {}
    for i, k in ipairs(keyOrder or {}) do
        orderLookup[k:upper()] = i
        orderLookup[k:lower()] = i
        orderLookup[k] = i
    end

    -- Sort by custom order, then alphabetically
    table.sort(matching, function(a, b)
        local aOrder = orderLookup[a.key] or 9999
        local bOrder = orderLookup[b.key] or 9999
        if aOrder ~= bOrder then
            return aOrder < bOrder
        end
        return a.key < b.key
    end)
    return matching
end

---------------------------------------------------------------------------
-- Canvas Drawing
---------------------------------------------------------------------------

-- Create or update the canvas with current hotkeys
function obj:_createCanvas()
    local screen = hs.screen.mainScreen()
    local frame = screen:frame()
    local hotkeys = getMatchingHotkeys(self._modFlags, self.keyOrder)

    if #hotkeys == 0 then return nil end

    -- Calculate layout
    local padding = 30
    local margin = 20  -- Distance from screen edge
    local lineHeight = self.fontSize + 10
    local keyWidth = 60
    local descWidth = 200
    local colWidth = keyWidth + descWidth + 20

    -- Determine columns and rows
    local maxRowsPerCol = math.floor((frame.h - padding * 2) / lineHeight) - 1
    local numCols = math.ceil(#hotkeys / maxRowsPerCol)
    numCols = math.min(numCols, 4)  -- Max 4 columns
    local rowsPerCol = math.ceil(#hotkeys / numCols)

    local canvasWidth = numCols * colWidth + padding * 2
    local canvasHeight = (rowsPerCol + 1) * lineHeight + padding * 2

    -- Position based on self.position setting
    local x, y
    local pos = self.position or "center"
    if pos == "bottomLeft" then
        x = frame.x + margin
        y = frame.y + frame.h - canvasHeight - margin
    elseif pos == "bottomRight" then
        x = frame.x + frame.w - canvasWidth - margin
        y = frame.y + frame.h - canvasHeight - margin
    elseif pos == "topLeft" then
        x = frame.x + margin
        y = frame.y + margin
    elseif pos == "topRight" then
        x = frame.x + frame.w - canvasWidth - margin
        y = frame.y + margin
    else  -- center
        x = frame.x + (frame.w - canvasWidth) / 2
        y = frame.y + (frame.h - canvasHeight) / 2
    end

    local canvas = hs.canvas.new({x = x, y = y, w = canvasWidth, h = canvasHeight})

    -- Background with rounded corners
    canvas:appendElements({
        type = "rectangle",
        action = "fill",
        fillColor = self.bgColor,
        roundedRectRadii = {xRadius = 12, yRadius = 12},
    })

    -- Title
    local modString = formatModifiers(self._modFlags)
    canvas:appendElements({
        type = "text",
        text = modString .. " Shortcuts",
        textColor = self.highlightColor,
        textFont = self.font,
        textSize = self.fontSize + 4,
        frame = {x = padding, y = padding, w = canvasWidth - padding * 2, h = lineHeight},
    })

    -- Hotkeys
    for i, hk in ipairs(hotkeys) do
        local col = math.floor((i - 1) / rowsPerCol)
        local row = (i - 1) % rowsPerCol
        local xPos = padding + col * colWidth
        local yPos = padding + (row + 1) * lineHeight + 10

        -- Key
        canvas:appendElements({
            type = "text",
            text = hk.key,
            textColor = self.highlightColor,
            textFont = self.font,
            textSize = self.fontSize,
            textAlignment = "right",
            frame = {x = xPos, y = yPos, w = keyWidth, h = lineHeight},
        })

        -- Description
        canvas:appendElements({
            type = "text",
            text = hk.desc,
            textColor = self.textColor,
            textFont = self.font,
            textSize = self.fontSize,
            frame = {x = xPos + keyWidth + 10, y = yPos, w = descWidth, h = lineHeight},
        })
    end

    return canvas
end

function obj:_show()
    if self._visible then return end
    self._canvas = self:_createCanvas()
    if self._canvas then
        self._canvas:show()
        self._visible = true
    end
end

function obj:_hide()
    if not self._visible then return end
    if self._canvas then
        self._canvas:delete()
        self._canvas = nil
    end
    self._visible = false
end

---------------------------------------------------------------------------
-- Event Handling
---------------------------------------------------------------------------

function obj:_handleFlags(event)
    local flags = event:getFlags()

    if flagsMatchModifiers(flags, self._modFlags) then
        -- Modifiers match - start timer to show
        if not self._timer then
            self._timer = hs.timer.doAfter(self.delay, function()
                self:_show()
                self._timer = nil
            end)
        end
    else
        -- Modifiers don't match - hide and cancel timer
        if self._timer then
            self._timer:stop()
            self._timer = nil
        end
        self:_hide()
    end

    return false  -- Don't consume the event
end

---------------------------------------------------------------------------
-- Public API
---------------------------------------------------------------------------

--- CheatSheet:start()
--- Method
--- Starts CheatSheet, watching for modifier keys
---
--- Returns:
---  * The CheatSheet object
function obj:start()
    self._modFlags = normalizeModifiers(self.modifiers)

    if not self._eventtap then
        self._eventtap = hs.eventtap.new({hs.eventtap.event.types.flagsChanged}, function(event)
            return self:_handleFlags(event)
        end)
    end

    self._eventtap:start()
    return self
end

--- CheatSheet:stop()
--- Method
--- Stops CheatSheet
---
--- Returns:
---  * The CheatSheet object
function obj:stop()
    if self._eventtap then
        self._eventtap:stop()
    end
    if self._timer then
        self._timer:stop()
        self._timer = nil
    end
    self:_hide()
    return self
end

--- CheatSheet:toggle()
--- Method
--- Manually toggle the cheat sheet visibility
function obj:toggle()
    if self._visible then
        self:_hide()
    else
        self._modFlags = normalizeModifiers(self.modifiers)
        self:_show()
    end
end

--- CheatSheet:bindHotkeys(mapping)
--- Method
--- Binds hotkeys for CheatSheet
---
--- Parameters:
---  * mapping - A table with keys 'toggle' mapped to hotkey specs
---
--- Returns:
---  * The CheatSheet object
function obj:bindHotkeys(mapping)
    local spec = {
        toggle = hs.fnutils.partial(self.toggle, self)
    }
    hs.spoons.bindHotkeysToSpec(spec, mapping)
    return self
end

return obj

