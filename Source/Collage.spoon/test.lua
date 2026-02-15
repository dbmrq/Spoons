--- Collage Test Suite
--- Run unit tests: spoon.Collage:loadTest().runUnit()

local M = {}

-- Get reference to the spoon
local collage = spoon and spoon.Collage or nil

--- Run unit tests (can run without GUI, mocks settings and pasteboard)
function M.runUnit()
    print("\n=== Collage Unit Tests ===\n")

    local passed = 0
    local failed = 0

    -- Create a mock object for testing
    local function createMockObj()
        local mockSettings = {}
        return {
            copyHistorySize = 10,
            cutHistorySize = 15,
            recentItemCount = 5,
            menuWidth = 40,
            menuTitle = "✂",
            _copyHistory = {},
            _cutHistory = {},
            _customItems = {},
            _customSubmenus = {},
            _menu = nil,
            _saveHistory = function(self)
                mockSettings.copy = self._copyHistory
                mockSettings.cut = self._cutHistory
            end,
            _refreshMenu = function(self) end,
            _loadHistory = function(self)
                self._copyHistory = mockSettings.copy or {}
                self._cutHistory = mockSettings.cut or {}
            end,
        }
    end

    -- Test 1: _addToHistory adds copy items correctly
    local function test_addToHistory_copy()
        local obj = createMockObj()
        obj._addToHistory = collage and collage._addToHistory or function(self, item, isCut)
            if not item or item == "" then return end
            local history = isCut and self._cutHistory or self._copyHistory
            local maxSize = isCut and self.cutHistorySize or self.copyHistorySize
            while #history >= maxSize do table.remove(history, 1) end
            table.insert(history, item)
            self:_saveHistory()
            self:_refreshMenu()
        end

        obj:_addToHistory("test item 1", false)
        obj:_addToHistory("test item 2", false)

        return #obj._copyHistory == 2
            and obj._copyHistory[1] == "test item 1"
            and obj._copyHistory[2] == "test item 2"
            and #obj._cutHistory == 0
    end

    if test_addToHistory_copy() then
        print("✓ addToHistory_copy: PASS")
        passed = passed + 1
    else
        print("✗ addToHistory_copy: FAIL")
        failed = failed + 1
    end

    -- Test 2: _addToHistory adds cut items correctly
    local function test_addToHistory_cut()
        local obj = createMockObj()
        obj._addToHistory = collage and collage._addToHistory or function(self, item, isCut)
            if not item or item == "" then return end
            local history = isCut and self._cutHistory or self._copyHistory
            local maxSize = isCut and self.cutHistorySize or self.copyHistorySize
            while #history >= maxSize do table.remove(history, 1) end
            table.insert(history, item)
            self:_saveHistory()
            self:_refreshMenu()
        end

        obj:_addToHistory("cut item 1", true)
        obj:_addToHistory("cut item 2", true)

        return #obj._cutHistory == 2
            and obj._cutHistory[1] == "cut item 1"
            and obj._cutHistory[2] == "cut item 2"
            and #obj._copyHistory == 0
    end

    if test_addToHistory_cut() then
        print("✓ addToHistory_cut: PASS")
        passed = passed + 1
    else
        print("✗ addToHistory_cut: FAIL")
        failed = failed + 1
    end

    -- Test 3: _truncate shortens long text
    local function test_truncate()
        local obj = createMockObj()
        obj._truncate = collage and collage._truncate or function(self, text)
            local display = text:gsub("\n", " "):gsub("\r", "")
            if #display > self.menuWidth then
                return display:sub(1, self.menuWidth) .. "…"
            end
            return display
        end

        local short = obj:_truncate("short text")
        local long = obj:_truncate("this is a very long text that should be truncated because it exceeds forty characters")
        local withNewline = obj:_truncate("line1\nline2")

        return short == "short text"
            and #long == 41  -- 40 chars + ellipsis
            and withNewline == "line1 line2"
    end

    if test_truncate() then
        print("✓ truncate: PASS")
        passed = passed + 1
    else
        print("✗ truncate: FAIL")
        failed = failed + 1
    end

    -- Test 4: addItem adds custom items
    local function test_addItem()
        local obj = createMockObj()
        obj.addItem = collage and collage.addItem or function(self, item)
            table.insert(self._customItems, item)
            self:_refreshMenu()
            return self
        end

        obj:addItem({ title = "Test Item", fn = function() end })

        return #obj._customItems == 1 and obj._customItems[1].title == "Test Item"
    end

    if test_addItem() then
        print("✓ addItem: PASS")
        passed = passed + 1
    else
        print("✗ addItem: FAIL")
        failed = failed + 1
    end

    if test_addSubmenu() then
        print("✓ addSubmenu: PASS")
        passed = passed + 1
    else
        print("✗ addSubmenu: FAIL")
        failed = failed + 1
    end

    -- Test 6: clearHistory clears both histories
    local function test_clearHistory()
        local obj = createMockObj()
        obj._copyHistory = {"a", "b", "c"}
        obj._cutHistory = {"x", "y", "z"}
        obj.clearHistory = collage and collage.clearHistory or function(self)
            self._copyHistory = {}
            self._cutHistory = {}
            self:_saveHistory()
            self:_refreshMenu()
            return self
        end

        obj:clearHistory()

        return #obj._copyHistory == 0 and #obj._cutHistory == 0
    end

    if test_clearHistory() then
        print("✓ clearHistory: PASS")
        passed = passed + 1
    else
        print("✗ clearHistory: FAIL")
        failed = failed + 1
    end

    -- Test 7: _getMergedHistory merges and sorts correctly
    local function test_getMergedHistory()
        local obj = createMockObj()
        obj._copyHistory = {"copy1", "copy2"}
        obj._cutHistory = {"cut1", "cut2", "cut3"}
        obj._getMergedHistory = collage and collage._getMergedHistory or function(self)
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

        local merged = obj:_getMergedHistory()

        -- Cut items should come first (higher index), most recent first
        return #merged == 5
            and merged[1] == "cut3"  -- Most recent cut
            and merged[2] == "cut2"
            and merged[3] == "cut1"
    end

    if test_getMergedHistory() then
        print("✓ getMergedHistory: PASS")
        passed = passed + 1
    else
        print("✗ getMergedHistory: FAIL")
        failed = failed + 1
    end

    -- Test 8: History limits are respected
    local function test_history_limits()
        local obj = createMockObj()
        obj.copyHistorySize = 3
        obj._addToHistory = collage and collage._addToHistory or function(self, item, isCut)
            if not item or item == "" then return end
            local history = isCut and self._cutHistory or self._copyHistory
            local maxSize = isCut and self.cutHistorySize or self.copyHistorySize
            while #history >= maxSize do table.remove(history, 1) end
            table.insert(history, item)
        end

        obj:_addToHistory("item1", false)
        obj:_addToHistory("item2", false)
        obj:_addToHistory("item3", false)
        obj:_addToHistory("item4", false)

        return #obj._copyHistory == 3
            and obj._copyHistory[1] == "item2"  -- item1 should be removed
            and obj._copyHistory[3] == "item4"
    end

    if test_history_limits() then
        print("✓ history_limits: PASS")
        passed = passed + 1
    else
        print("✗ history_limits: FAIL")
        failed = failed + 1
    end

    print("\n=== Unit Tests Complete: " .. passed .. " passed, " .. failed .. " failed ===\n")
    return failed == 0
end

return M
