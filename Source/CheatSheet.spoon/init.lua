--- === CheatSheet ===
---
--- Display a cheat sheet of keyboard shortcuts when modifier keys are held.
--- Supports multiple sheets: auto-discovered hotkeys for custom modifier combos,
--- and a readline/text-editing sheet when ctrl/alt is held in a text field.
---
--- Download: [https://github.com/dbmrq/Spoons/raw/master/Spoons/CheatSheet.spoon.zip](https://github.com/dbmrq/Spoons/raw/master/Spoons/CheatSheet.spoon.zip)

local obj = {}
obj.__index = obj

-- Metadata
obj.name = "CheatSheet"
obj.version = "2.0"
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

--- CheatSheet.enableReadlineSheet
--- Variable
--- Enable the readline/text-editing cheat sheet when ctrl, alt, or alt+shift
--- is held while editing text. Default: true
obj.enableReadlineSheet = true

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

--- CheatSheet.readlineBindings
--- Variable
--- Predefined readline/text-editing bindings (macOS defaults + Readline spoon).
--- Format: {mods = "⌃" or "⌥" or "⌥⇧", key = "X", desc = "Description"}
obj.readlineBindings = {
    -- Control key bindings (macOS defaults)
    {mods = "⌃", key = "A", desc = "Start of line"},
    {mods = "⌃", key = "E", desc = "End of line"},
    {mods = "⌃", key = "F", desc = "Forward char"},
    {mods = "⌃", key = "B", desc = "Backward char"},
    {mods = "⌃", key = "N", desc = "Next line"},
    {mods = "⌃", key = "P", desc = "Previous line"},
    {mods = "⌃", key = "D", desc = "Delete forward"},
    {mods = "⌃", key = "H", desc = "Delete backward"},
    {mods = "⌃", key = "K", desc = "Kill to end"},
    {mods = "⌃", key = "Y", desc = "Yank (paste kill)"},
    {mods = "⌃", key = "T", desc = "Transpose chars"},
    {mods = "⌃", key = "O", desc = "Insert newline after"},
    {mods = "⌃", key = "U", desc = "Kill to start"},
    {mods = "⌃", key = "W", desc = "Delete word back"},
    -- Alt key bindings (Readline spoon + macOS)
    {mods = "⌥", key = "F", desc = "Word forward"},
    {mods = "⌥", key = "B", desc = "Word backward"},
    {mods = "⌥", key = "D", desc = "Delete word forward"},
    {mods = "⌥", key = ",", desc = "Start of document"},
    {mods = "⌥", key = ".", desc = "End of document"},
    {mods = "⌥", key = "←", desc = "Word backward"},
    {mods = "⌥", key = "→", desc = "Word forward"},
    {mods = "⌥", key = "⌫", desc = "Delete word back"},
    -- Alt+Shift bindings (selection)
    {mods = "⌥⇧", key = "F", desc = "Select word forward"},
    {mods = "⌥⇧", key = "B", desc = "Select word backward"},
    {mods = "⌥⇧", key = "←", desc = "Select word backward"},
    {mods = "⌥⇧", key = "→", desc = "Select word forward"},
}

---------------------------------------------------------------------------
-- Internal State
---------------------------------------------------------------------------

obj._canvas = nil
obj._eventtap = nil
obj._timer = nil
obj._visible = false
obj._modFlags = {}
obj._currentSheet = nil  -- "main", "readline", or "mode"
obj._modeHintsCanvas = nil  -- Separate canvas for mode hints (from WinMan)
obj._modeHintsVisible = false

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

-- Check if current flags match readline sheet triggers (ctrl, alt, or alt+shift)
local function isReadlineModifiers(flags)
    local ctrl = flags.ctrl or false
    local alt = flags.alt or false
    local shift = flags.shift or false
    local cmd = flags.cmd or false

    if cmd then return false end  -- cmd+anything is not readline
    if ctrl and not alt and not shift then return true end  -- ctrl only
    if alt and not ctrl and not shift then return true end  -- alt only
    if alt and shift and not ctrl then return true end  -- alt+shift
    return false
end

---------------------------------------------------------------------------
-- Text Field Detection
---------------------------------------------------------------------------

-- Text input roles that indicate an editable text field
local textInputRoles = {
    AXTextField = true,
    AXTextArea = true,
    AXComboBox = true,
    AXSearchField = true,
}

-- Check if the currently focused element is a text field
local function isTextFieldFocused()
    local axSys = hs.axuielement.systemWideElement()
    if not axSys then return false end

    local focused = axSys:attributeValue("AXFocusedUIElement")
    if not focused then return false end

    local role = focused:attributeValue("AXRole")
    if textInputRoles[role] then return true end

    -- Also check if element is editable (for custom views)
    local editable = focused:attributeValue("AXEditable") or
                     focused:attributeValue("AXEnabled")
    if role == "AXWebArea" then return true end  -- Web text inputs

    return false
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
            -- Skip hotkeys without a meaningful description (empty or just whitespace)
            if desc ~= "" and desc:match("%S") then
                table.insert(matching, {key = key, desc = desc})
            end
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

-- Calculate canvas position based on settings
local function calculatePosition(frame, canvasWidth, canvasHeight, position)
    local margin = 20
    local pos = position or "center"
    local x, y

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
    return x, y
end

-- Create canvas for main sheet (discovered hotkeys)
function obj:_createMainCanvas()
    local screen = hs.screen.mainScreen()
    local frame = screen:frame()
    local hotkeys = getMatchingHotkeys(self._modFlags, self.keyOrder)

    if #hotkeys == 0 then return nil end

    local padding = 30
    local lineHeight = self.fontSize + 10
    local keyWidth = 60
    local descWidth = 200
    local colWidth = keyWidth + descWidth + 20

    local maxRowsPerCol = math.floor((frame.h - padding * 2) / lineHeight) - 1
    local numCols = math.ceil(#hotkeys / maxRowsPerCol)
    numCols = math.min(numCols, 4)
    local rowsPerCol = math.ceil(#hotkeys / numCols)

    local canvasWidth = numCols * colWidth + padding * 2
    local canvasHeight = (rowsPerCol + 1) * lineHeight + padding * 2

    local x, y = calculatePosition(frame, canvasWidth, canvasHeight, self.position)
    local canvas = hs.canvas.new({x = x, y = y, w = canvasWidth, h = canvasHeight})

    canvas:appendElements({
        type = "rectangle", action = "fill", fillColor = self.bgColor,
        roundedRectRadii = {xRadius = 12, yRadius = 12},
    })

    local modString = formatModifiers(self._modFlags)
    canvas:appendElements({
        type = "text", text = modString .. " Shortcuts",
        textColor = self.highlightColor, textFont = self.font,
        textSize = self.fontSize + 4,
        frame = {x = padding, y = padding, w = canvasWidth - padding * 2, h = lineHeight},
    })

    for i, hk in ipairs(hotkeys) do
        local col = math.floor((i - 1) / rowsPerCol)
        local row = (i - 1) % rowsPerCol
        local xPos = padding + col * colWidth
        local yPos = padding + (row + 1) * lineHeight + 10

        canvas:appendElements({
            type = "text", text = hk.key,
            textColor = self.highlightColor, textFont = self.font,
            textSize = self.fontSize, textAlignment = "right",
            frame = {x = xPos, y = yPos, w = keyWidth, h = lineHeight},
        })
        canvas:appendElements({
            type = "text", text = hk.desc,
            textColor = self.textColor, textFont = self.font,
            textSize = self.fontSize,
            frame = {x = xPos + keyWidth + 10, y = yPos, w = descWidth, h = lineHeight},
        })
    end

    return canvas
end

-- Create canvas for readline sheet (predefined bindings)
function obj:_createReadlineCanvas()
    local screen = hs.screen.mainScreen()
    local frame = screen:frame()
    local bindings = self.readlineBindings

    if #bindings == 0 then return nil end

    local padding = 30
    local lineHeight = self.fontSize + 10
    local modWidth = 30
    local keyWidth = 30
    local descWidth = 160
    local colWidth = modWidth + keyWidth + descWidth + 20

    local maxRowsPerCol = math.floor((frame.h - padding * 2) / lineHeight) - 1
    local numCols = math.ceil(#bindings / maxRowsPerCol)
    numCols = math.min(numCols, 4)
    local rowsPerCol = math.ceil(#bindings / numCols)

    local canvasWidth = numCols * colWidth + padding * 2
    local canvasHeight = (rowsPerCol + 1) * lineHeight + padding * 2

    local x, y = calculatePosition(frame, canvasWidth, canvasHeight, self.position)
    local canvas = hs.canvas.new({x = x, y = y, w = canvasWidth, h = canvasHeight})

    canvas:appendElements({
        type = "rectangle", action = "fill", fillColor = self.bgColor,
        roundedRectRadii = {xRadius = 12, yRadius = 12},
    })

    canvas:appendElements({
        type = "text", text = "Text Editing",
        textColor = self.highlightColor, textFont = self.font,
        textSize = self.fontSize + 4,
        frame = {x = padding, y = padding, w = canvasWidth - padding * 2, h = lineHeight},
    })

    for i, binding in ipairs(bindings) do
        local col = math.floor((i - 1) / rowsPerCol)
        local row = (i - 1) % rowsPerCol
        local xPos = padding + col * colWidth
        local yPos = padding + (row + 1) * lineHeight + 10

        -- Modifier symbol
        canvas:appendElements({
            type = "text", text = binding.mods,
            textColor = self.textColor, textFont = self.font,
            textSize = self.fontSize, textAlignment = "right",
            frame = {x = xPos, y = yPos, w = modWidth, h = lineHeight},
        })
        -- Key
        canvas:appendElements({
            type = "text", text = binding.key,
            textColor = self.highlightColor, textFont = self.font,
            textSize = self.fontSize, textAlignment = "left",
            frame = {x = xPos + modWidth + 5, y = yPos, w = keyWidth, h = lineHeight},
        })
        -- Description
        canvas:appendElements({
            type = "text", text = binding.desc,
            textColor = self.textColor, textFont = self.font,
            textSize = self.fontSize,
            frame = {x = xPos + modWidth + keyWidth + 15, y = yPos, w = descWidth, h = lineHeight},
        })
    end

    return canvas
end

function obj:_show(sheetType)
    if self._visible then return end

    if sheetType == "readline" then
        self._canvas = self:_createReadlineCanvas()
    else
        self._canvas = self:_createMainCanvas()
    end

    if self._canvas then
        self._canvas:show()
        self._visible = true
        self._currentSheet = sheetType
    end
end

function obj:_hide()
    if not self._visible then return end
    if self._canvas then
        self._canvas:delete()
        self._canvas = nil
    end
    self._visible = false
    self._currentSheet = nil
end

---------------------------------------------------------------------------
-- Event Handling
---------------------------------------------------------------------------

function obj:_handleFlags(event)
    local flags = event:getFlags()

    -- Check for main sheet (all configured modifiers)
    if flagsMatchModifiers(flags, self._modFlags) then
        if not self._timer then
            self._timer = hs.timer.doAfter(self.delay, function()
                self:_show("main")
                self._timer = nil
            end)
        end
        return false
    end

    -- Check for readline sheet (ctrl, alt, or alt+shift while editing text)
    if self.enableReadlineSheet and isReadlineModifiers(flags) then
        if not self._timer then
            self._timer = hs.timer.doAfter(self.delay, function()
                if isTextFieldFocused() then
                    self:_show("readline")
                end
                self._timer = nil
            end)
        end
        return false
    end

    -- No match - hide and cancel timer
    if self._timer then
        self._timer:stop()
        self._timer = nil
    end
    self:_hide()

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

---------------------------------------------------------------------------
-- Mode Hints API (for WinMan modal integration)
---------------------------------------------------------------------------

--- CheatSheet:showModeHints(modeName, hints)
--- Method
--- Show a mode-specific hint overlay (called by WinMan when entering a modal)
---
--- Parameters:
---  * modeName - String name of the mode (e.g., "Focus", "Resize")
---  * hints - Table of {key, description} pairs to display
---
--- Returns:
---  * The CheatSheet object
function obj:showModeHints(modeName, hints)
    -- Hide any existing mode hints
    self:hideModeHints()

    if not hints or #hints == 0 then return self end

    local screen = hs.screen.mainScreen()
    local frame = screen:frame()

    local padding = 20
    local lineHeight = self.fontSize + 8
    local keyWidth = 80
    local descWidth = 160
    local entryWidth = keyWidth + descWidth

    -- Calculate dimensions
    local numEntries = #hints
    local canvasWidth = entryWidth + padding * 2
    local canvasHeight = (numEntries + 1) * lineHeight + padding * 2

    -- Position at bottom-left (matching main position)
    local x, y = frame.x + 20, frame.y + frame.h - canvasHeight - 20

    local canvas = hs.canvas.new({x = x, y = y, w = canvasWidth, h = canvasHeight})

    -- Background
    canvas:appendElements({
        type = "rectangle", action = "fill", fillColor = self.bgColor,
        roundedRectRadii = {xRadius = 10, yRadius = 10},
    })

    -- Title
    canvas:appendElements({
        type = "text", text = "[" .. modeName .. " Mode]",
        textColor = self.highlightColor, textFont = self.font,
        textSize = self.fontSize + 2,
        frame = {x = padding, y = padding, w = canvasWidth - padding * 2, h = lineHeight},
    })

    -- Hints
    for i, hint in ipairs(hints) do
        local yPos = padding + i * lineHeight

        -- Key
        canvas:appendElements({
            type = "text", text = hint[1],
            textColor = self.highlightColor, textFont = self.font,
            textSize = self.fontSize, textAlignment = "right",
            frame = {x = padding, y = yPos, w = keyWidth - 10, h = lineHeight},
        })

        -- Description
        canvas:appendElements({
            type = "text", text = hint[2],
            textColor = self.textColor, textFont = self.font,
            textSize = self.fontSize,
            frame = {x = padding + keyWidth, y = yPos, w = descWidth, h = lineHeight},
        })
    end

    canvas:show()
    self._modeHintsCanvas = canvas
    self._modeHintsVisible = true

    return self
end

--- CheatSheet:hideModeHints()
--- Method
--- Hide the mode hints overlay
---
--- Returns:
---  * The CheatSheet object
function obj:hideModeHints()
    if self._modeHintsCanvas then
        self._modeHintsCanvas:delete()
        self._modeHintsCanvas = nil
    end
    self._modeHintsVisible = false
    return self
end

return obj

