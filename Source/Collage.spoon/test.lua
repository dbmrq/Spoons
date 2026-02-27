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
            flashOnCopy = false,  -- Disable flash in tests
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
            _flashMenu = function(self) end,
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
            local timestamp = os.time() + os.clock()
            while #history >= maxSize do table.remove(history, 1) end
            table.insert(history, { text = item, timestamp = timestamp })
            self:_saveHistory()
            self:_refreshMenu()
        end

        obj:_addToHistory("test item 1", false)
        obj:_addToHistory("test item 2", false)

        return #obj._copyHistory == 2
            and obj._copyHistory[1].text == "test item 1"
            and obj._copyHistory[2].text == "test item 2"
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
            local timestamp = os.time() + os.clock()
            while #history >= maxSize do table.remove(history, 1) end
            table.insert(history, { text = item, timestamp = timestamp })
            self:_saveHistory()
            self:_refreshMenu()
        end

        obj:_addToHistory("cut item 1", true)
        obj:_addToHistory("cut item 2", true)

        return #obj._cutHistory == 2
            and obj._cutHistory[1].text == "cut item 1"
            and obj._cutHistory[2].text == "cut item 2"
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
            and #long == 43  -- 40 chars + ellipsis (3 bytes for "…" in UTF-8)
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

    -- Test 5: addSubmenu adds custom submenus
    local function test_addSubmenu()
        local obj = createMockObj()
        obj.addSubmenu = collage and collage.addSubmenu or function(self, title, items)
            table.insert(self._customSubmenus, { title = title, items = items })
            self:_refreshMenu()
            return self
        end

        obj:addSubmenu("Test Submenu", {
            { title = "Item 1", fn = function() end },
            { title = "Item 2", fn = function() end }
        })

        return #obj._customSubmenus == 1
            and obj._customSubmenus[1].title == "Test Submenu"
            and #obj._customSubmenus[1].items == 2
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

    -- Test 7: _getMergedHistory merges and sorts correctly by timestamp
    local function test_getMergedHistory()
        local obj = createMockObj()
        -- Use timestamps to control ordering: most recent item has highest timestamp
        local baseTime = os.time()
        obj._copyHistory = {
            { text = "copy1", timestamp = baseTime + 1 },
            { text = "copy2", timestamp = baseTime + 4 }  -- Most recent copy
        }
        obj._cutHistory = {
            { text = "cut1", timestamp = baseTime + 2 },
            { text = "cut2", timestamp = baseTime + 3 },
            { text = "cut3", timestamp = baseTime + 5 }   -- Most recent overall
        }
        obj._getMergedHistory = collage and collage._getMergedHistory or function(self)
            local merged = {}
            local seen = {}
            local allItems = {}

            for _, item in ipairs(self._copyHistory) do
                table.insert(allItems, item)
            end
            for _, item in ipairs(self._cutHistory) do
                table.insert(allItems, item)
            end

            table.sort(allItems, function(a, b) return a.timestamp > b.timestamp end)

            for _, item in ipairs(allItems) do
                if not seen[item.text] then
                    seen[item.text] = true
                    table.insert(merged, item.text)
                end
            end

            return merged
        end

        local merged = obj:_getMergedHistory()

        -- Items should be sorted by timestamp, most recent first
        return #merged == 5
            and merged[1] == "cut3"   -- timestamp +5, most recent
            and merged[2] == "copy2"  -- timestamp +4
            and merged[3] == "cut2"   -- timestamp +3
            and merged[4] == "cut1"   -- timestamp +2
            and merged[5] == "copy1"  -- timestamp +1, oldest
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
            local timestamp = os.time() + os.clock()
            while #history >= maxSize do table.remove(history, 1) end
            table.insert(history, { text = item, timestamp = timestamp })
        end

        obj:_addToHistory("item1", false)
        obj:_addToHistory("item2", false)
        obj:_addToHistory("item3", false)
        obj:_addToHistory("item4", false)

        return #obj._copyHistory == 3
            and obj._copyHistory[1].text == "item2"  -- item1 should be removed
            and obj._copyHistory[3].text == "item4"
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
