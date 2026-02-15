--- === Collage ===
---
--- Clipboard manager with customizable menu for utilities.
--- Stores clipboard history from Cmd+C (copy) and Cmd+X (cut) operations.
--- Cut items persist longer than copy items. Allows adding custom menu items and submenus.
---
--- Download: [https://github.com/dbmrq/Spoons/raw/master/Spoons/Collage.spoon.zip](https://github.com/dbmrq/Spoons/raw/master/Spoons/Collage.spoon.zip)

local obj = {}
obj.__index = obj

-- Metadata
obj.name = "Collage"
obj.version = "1.0"
obj.author = "Daniel Marques <danielbmarques@gmail.com>"
obj.license = "MIT"
obj.homepage = "https://github.com/dbmrq/Spoons"

--- Collage.copyHistorySize
--- Variable
--- Number of items from Cmd+C to keep. Default: 10
obj.copyHistorySize = 10

--- Collage.cutHistorySize
--- Variable
--- Number of items from Cmd+X to keep (these persist longer). Default: 15
obj.cutHistorySize = 15

--- Collage.recentItemCount
--- Variable
--- Number of recent items shown in main menu before "More..." submenu. Default: 5
obj.recentItemCount = 5

--- Collage.menuWidth
--- Variable
--- Maximum characters to show before truncating menu item titles. Default: 40
obj.menuWidth = 40

--- Collage.menuTitle
--- Variable
--- Menu bar icon/title. Default: "✂"
obj.menuTitle = "✂"

--- Collage.copyModifiers
--- Variable
--- Modifiers for copy hotkey. Default: {"cmd"}
obj.copyModifiers = {"cmd"}

--- Collage.copyKey
--- Variable
--- Key for copy hotkey. Default: "c"
obj.copyKey = "c"

--- Collage.cutModifiers
--- Variable
--- Modifiers for cut hotkey. Default: {"cmd"}
obj.cutModifiers = {"cmd"}

--- Collage.cutKey
--- Variable
--- Key for cut hotkey. Default: "x"
obj.cutKey = "x"

-- Internal state
obj._menu = nil
obj._copyHotkey = nil
obj._cutHotkey = nil
obj._copyHistory = {}
obj._cutHistory = {}
obj._customItems = {}
obj._customSubmenus = {}

local pasteboard = require("hs.pasteboard")
local settings = require("hs.settings")

local COPY_HISTORY_KEY = "Collage.copyHistory"
local CUT_HISTORY_KEY = "Collage.cutHistory"

function obj:_loadHistory()
    self._copyHistory = settings.get(COPY_HISTORY_KEY) or {}
    self._cutHistory = settings.get(CUT_HISTORY_KEY) or {}
end

function obj:_saveHistory()
    settings.set(COPY_HISTORY_KEY, self._copyHistory)
    settings.set(CUT_HISTORY_KEY, self._cutHistory)
end

function obj:_addToHistory(item, isCut)
    if not item or item == "" then return end

    local history = isCut and self._cutHistory or self._copyHistory
    local maxSize = isCut and self.cutHistorySize or self.copyHistorySize

    -- Remove duplicate if exists in either history
    for i = #self._copyHistory, 1, -1 do
        if self._copyHistory[i] == item then
            table.remove(self._copyHistory, i)
        end
    end
    for i = #self._cutHistory, 1, -1 do
        if self._cutHistory[i] == item then
            table.remove(self._cutHistory, i)
        end
    end

    -- Add to appropriate history
    while #history >= maxSize do
        table.remove(history, 1)
    end
    table.insert(history, item)

    self:_saveHistory()
    self:_refreshMenu()
end

function obj:_getMergedHistory()
    local merged = {}
    local seen = {}
    local allItems = {}

    for i, item in ipairs(self._copyHistory) do
        table.insert(allItems, { text = item, index = i, source = "copy" })
    end
    for i, item in ipairs(self._cutHistory) do
        table.insert(allItems, { text = item, index = i + 1000, source = "cut" })
    end

    table.sort(allItems, function(a, b) return a.index > b.index end)

    for _, item in ipairs(allItems) do
        if not seen[item.text] then
            seen[item.text] = true
            table.insert(merged, item.text)
        end
    end

    return merged
end

function obj:_truncate(text)
    local display = text:gsub("\n", " "):gsub("\r", "")
    if #display > self.menuWidth then
        return display:sub(1, self.menuWidth) .. "…"
    end
    return display
end

function obj:_buildMenu()
    local menuData = {}
    local history = self:_getMergedHistory()

    if #history == 0 and #self._customItems == 0 and #self._customSubmenus == 0 then
        table.insert(menuData, { title = "No items", disabled = true })
        return menuData
    end

    -- Recent clipboard items (up to recentItemCount)
    local recentCount = math.min(#history, self.recentItemCount)
    for i = 1, recentCount do
        local item = history[i]
        table.insert(menuData, {
            title = self:_truncate(item),
            fn = function() hs.eventtap.keyStrokes(item) end
        })
    end

    -- "More..." submenu (always shown when there's history, contains Clear All)
    if #history > 0 then
        local moreItems = {}
        for i = self.recentItemCount + 1, #history do
            local item = history[i]
            table.insert(moreItems, {
                title = self:_truncate(item),
                fn = function() hs.eventtap.keyStrokes(item) end
            })
        end
        if #moreItems > 0 then
            table.insert(moreItems, { title = "-" })
        end
        table.insert(moreItems, {
            title = "Clear All",
            fn = function() self:clearHistory() end
        })
        table.insert(menuData, { title = "More...", menu = moreItems })
    end

    -- Divider before custom items
    if #self._customItems > 0 or #self._customSubmenus > 0 then
        table.insert(menuData, { title = "-" })
    end

    for _, item in ipairs(self._customItems) do
        table.insert(menuData, item)
    end

    for _, submenu in ipairs(self._customSubmenus) do
        table.insert(menuData, {
            title = submenu.title,
            menu = submenu.items
        })
    end

    return menuData
end

function obj:_refreshMenu()
    if not self._menu then
        self._menu = hs.menubar.new()
    end
    self._menu:setTitle(self.menuTitle)
    self._menu:setTooltip("Collage - Clipboard Manager")
    self._menu:setMenu(function() return self:_buildMenu() end)
    self._menu:returnToMenuBar()
end

function obj:_storeCopy(isCut)
    local contents = pasteboard.getContents()
    if contents then
        self:_addToHistory(contents, isCut)
    end
end

--- Collage:clearHistory()
--- Method
--- Clear all clipboard history
---
--- Returns:
---  * The Collage object
function obj:clearHistory()
    self._copyHistory = {}
    self._cutHistory = {}
    self:_saveHistory()
    self:_refreshMenu()
    return self
end

--- Collage:getHistory()
--- Method
--- Get the merged clipboard history
---
--- Returns:
---  * A table of clipboard history items, most recent first
function obj:getHistory()
    return self:_getMergedHistory()
end

--- Collage:addItem(item)
--- Method
--- Add a custom menu item to the main menu
---
--- Parameters:
---  * item - A table with `title` and `fn` keys (standard hs.menubar item format)
---
--- Returns:
---  * The Collage object
---
--- Example:
--- ```lua
--- spoon.Collage:addItem({ title = "My Action", fn = function() print("Hello!") end })
--- ```
function obj:addItem(item)
    table.insert(self._customItems, item)
    self:_refreshMenu()
    return self
end

--- Collage:addItems(items)
--- Method
--- Add multiple custom menu items to the main menu
---
--- Parameters:
---  * items - A table of menu item tables
---
--- Returns:
---  * The Collage object
function obj:addItems(items)
    for _, item in ipairs(items) do
        table.insert(self._customItems, item)
    end
    self:_refreshMenu()
    return self
end

--- Collage:addSubmenu(title, items)
--- Method
--- Add a custom submenu to the main menu
---
--- Parameters:
---  * title - The submenu title
---  * items - A table of menu item tables for the submenu contents
---
--- Returns:
---  * The Collage object
---
--- Example:
--- ```lua
--- spoon.Collage:addSubmenu("Reddit", {
---     { title = "Top of month", fn = redditTopMonth },
---     { title = "Top of year", fn = redditTopYear },
--- })
--- ```
function obj:addSubmenu(title, items)
    table.insert(self._customSubmenus, { title = title, items = items })
    self:_refreshMenu()
    return self
end


--- Collage:start()
--- Method
--- Start Collage - enables hotkeys and shows menu bar item
---
--- Returns:
---  * The Collage object
function obj:start()
    self:_loadHistory()
    self:_refreshMenu()

    -- Copy hotkey (Cmd+C by default)
    if self._copyHotkey then
        self._copyHotkey:delete()
    end
    self._copyHotkey = hs.hotkey.bind(self.copyModifiers, self.copyKey, function()
        self._copyHotkey:disable()
        hs.eventtap.keyStroke({"cmd"}, "c")
        self._copyHotkey:enable()
        hs.timer.doAfter(0.1, function() self:_storeCopy(false) end)
    end)

    -- Cut hotkey (Cmd+X by default)
    if self._cutHotkey then
        self._cutHotkey:delete()
    end
    self._cutHotkey = hs.hotkey.bind(self.cutModifiers, self.cutKey, function()
        self._cutHotkey:disable()
        hs.eventtap.keyStroke({"cmd"}, "x")
        self._cutHotkey:enable()
        hs.timer.doAfter(0.1, function() self:_storeCopy(true) end)
    end)

    return self
end

--- Collage:stop()
--- Method
--- Stop Collage - disables hotkeys and removes menu bar item
---
--- Returns:
---  * The Collage object
function obj:stop()
    if self._copyHotkey then
        self._copyHotkey:delete()
        self._copyHotkey = nil
    end
    if self._cutHotkey then
        self._cutHotkey:delete()
        self._cutHotkey = nil
    end
    if self._menu then
        self._menu:delete()
        self._menu = nil
    end
    return self
end

--- Collage:bindHotkeys(mapping)
--- Method
--- Bind hotkeys for Collage (currently unused, hotkeys are auto-bound on start)
---
--- Parameters:
---  * mapping - A table with hotkey mappings (reserved for future use)
---
--- Returns:
---  * The Collage object
function obj:bindHotkeys(mapping)
    -- Reserved for future use
    return self
end

--- Collage:loadTest()
--- Method
--- Loads the test module. Run tests with spoon.Collage:loadTest().runUnit()
---
--- Returns:
---  * The test module
function obj:loadTest()
    local spoonPath = hs.spoons.scriptPath()
    return dofile(spoonPath .. "/test.lua")
end

return obj
