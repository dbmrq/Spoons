--- Readline.spoon Test Suite
--- Unit tests: spoon.Readline:loadTest().runUnit()
--- E2E tests:  spoon.Readline:loadTest().runE2E()

local M = {}

local actions = spoon.Readline and spoon.Readline.actions or require("init").actions

--------------------------------------------------------------------------------
-- Unit Tests - mock hs.eventtap.keyStroke to verify correct keys are sent
--------------------------------------------------------------------------------

function M.runUnit()
    print("\n=== Readline Unit Tests ===\n")

    local calls = {}
    local originalKeyStroke = hs.eventtap.keyStroke

    -- Mock keyStroke to capture calls
    hs.eventtap.keyStroke = function(mods, key)
        table.insert(calls, {mods = mods, key = key})
    end

    local function resetCalls()
        calls = {}
    end

    local function assertCall(index, expectedMods, expectedKey, testName)
        local call = calls[index]
        if not call then
            print("✗ " .. testName .. ": FAIL (no call at index " .. index .. ")")
            return false
        end

        -- Sort modifiers for comparison
        local function sortedMods(mods)
            local sorted = {}
            for _, m in ipairs(mods) do table.insert(sorted, m) end
            table.sort(sorted)
            return table.concat(sorted, "+")
        end

        local actualMods = sortedMods(call.mods)
        local expectMods = sortedMods(expectedMods)

        if actualMods == expectMods and call.key == expectedKey then
            return true
        else
            print("✗ " .. testName .. ": FAIL (expected " .. expectMods .. "+" .. expectedKey ..
                  ", got " .. actualMods .. "+" .. call.key .. ")")
            return false
        end
    end

    local passed, failed = 0, 0

    local tests = {
        {name = "wordForward", action = actions.wordForward, expected = {{{"alt"}, "Right"}}},
        {name = "wordBackward", action = actions.wordBackward, expected = {{{"alt"}, "Left"}}},
        {name = "wordSelectForward", action = actions.wordSelectForward, expected = {{{"alt", "shift"}, "Right"}}},
        {name = "wordSelectBackward", action = actions.wordSelectBackward, expected = {{{"alt", "shift"}, "Left"}}},
        {name = "docStart", action = actions.docStart, expected = {{{"cmd"}, "Up"}}},
        {name = "docEnd", action = actions.docEnd, expected = {{{"cmd"}, "Down"}}},
        {name = "deleteWordForward", action = actions.deleteWordForward, expected = {{{"alt"}, "ForwardDelete"}}},
        {name = "deleteWordBackward", action = actions.deleteWordBackward, expected = {{{"alt"}, "Delete"}}},
        {name = "killToStart", action = actions.killToStart, expected = {{{"cmd", "shift"}, "Left"}, {{}, "Delete"}}},
    }

    for _, test in ipairs(tests) do
        resetCalls()
        test.action()

        local testPassed = true
        if #calls ~= #test.expected then
            print("✗ " .. test.name .. ": FAIL (expected " .. #test.expected .. " calls, got " .. #calls .. ")")
            testPassed = false
        else
            for i, exp in ipairs(test.expected) do
                if not assertCall(i, exp[1], exp[2], test.name) then
                    testPassed = false
                    break
                end
            end
        end

        if testPassed then
            print("✓ " .. test.name .. ": PASS")
            passed = passed + 1
        else
            failed = failed + 1
        end
    end

    -- Restore original
    hs.eventtap.keyStroke = originalKeyStroke

    print("\n=== Unit Tests Complete: " .. passed .. " passed, " .. failed .. " failed ===")
    return failed == 0
end

--------------------------------------------------------------------------------
-- E2E Tests - run in TextEdit
--------------------------------------------------------------------------------
function M.runE2E()
    local testText = "one two three"
    local delay = 0.15

    -- Clear clipboard before testing
    local function clearClipboard()
        hs.pasteboard.setContents("")
    end

    -- Get clipboard content
    local function getClipboard()
        return hs.pasteboard.getContents() or ""
    end

    -- Verification helpers
    local function verifyClipboard(expected, testName)
        hs.timer.doAfter(delay, function()
            local actual = getClipboard()
            if actual == expected then
                print("✓ " .. testName .. ": PASS")
            else
                print("✗ " .. testName .. ": FAIL (expected '" .. expected .. "', got '" .. actual .. "')")
            end
        end)
    end

    local function verifyEmpty(testName)
        hs.timer.doAfter(delay, function()
            local actual = getClipboard()
            if actual == "" then
                print("✓ " .. testName .. ": PASS (clipboard empty as expected)")
            else
                print("✗ " .. testName .. ": FAIL (expected empty, got '" .. actual .. "')")
            end
        end)
    end

    -- Test definitions: {name, setup, action, verify}
    local tests = {
        {
            name = "wordForward",
            setup = function()
                -- Cursor at start, move forward one word, select back to verify position
                hs.eventtap.keyStroke({"cmd"}, "Left") -- go to start
            end,
            action = actions.wordForward,
            verify = function()
                clearClipboard()
                hs.eventtap.keyStroke({"shift", "alt"}, "Left") -- select word backward
                hs.eventtap.keyStroke({"cmd"}, "c")
                verifyClipboard("one", "wordForward")
            end
        },
        {
            name = "wordBackward",
            setup = function()
                hs.eventtap.keyStroke({"cmd"}, "Right") -- go to end
            end,
            action = actions.wordBackward,
            verify = function()
                clearClipboard()
                hs.eventtap.keyStroke({"shift", "alt"}, "Right")
                hs.eventtap.keyStroke({"cmd"}, "c")
                verifyClipboard("three", "wordBackward")
            end
        },
        {
            name = "wordSelectForward",
            setup = function()
                hs.eventtap.keyStroke({"cmd"}, "Left")
            end,
            action = actions.wordSelectForward,
            verify = function()
                clearClipboard()
                hs.eventtap.keyStroke({"cmd"}, "c")
                verifyClipboard("one", "wordSelectForward")
            end
        },
        {
            name = "wordSelectBackward",
            setup = function()
                hs.eventtap.keyStroke({"cmd"}, "Right")
            end,
            action = actions.wordSelectBackward,
            verify = function()
                clearClipboard()
                hs.eventtap.keyStroke({"cmd"}, "c")
                verifyClipboard("three", "wordSelectBackward")
            end
        },
        {
            name = "deleteWordBackward",
            setup = function()
                hs.eventtap.keyStroke({"cmd"}, "Right")
            end,
            action = actions.deleteWordBackward,
            verify = function()
                clearClipboard()
                hs.eventtap.keyStroke({"cmd"}, "a")
                hs.eventtap.keyStroke({"cmd"}, "c")
                verifyClipboard("one two ", "deleteWordBackward")
            end
        },
        {
            name = "deleteWordForward",
            setup = function()
                hs.eventtap.keyStroke({"cmd"}, "Left")
            end,
            action = actions.deleteWordForward,
            verify = function()
                clearClipboard()
                hs.eventtap.keyStroke({"cmd"}, "a")
                hs.eventtap.keyStroke({"cmd"}, "c")
                verifyClipboard(" two three", "deleteWordForward")
            end
        },
        {
            name = "docEnd",
            setup = function()
                hs.eventtap.keyStroke({"cmd"}, "Left")
            end,
            action = actions.docEnd,
            verify = function()
                clearClipboard()
                hs.eventtap.keyStroke({"cmd", "shift"}, "Left")
                hs.eventtap.keyStroke({"cmd"}, "c")
                verifyClipboard("one two three", "docEnd")
            end
        },
        {
            name = "docStart",
            setup = function()
                hs.eventtap.keyStroke({"cmd"}, "Right")
            end,
            action = actions.docStart,
            verify = function()
                clearClipboard()
                hs.eventtap.keyStroke({"cmd", "shift"}, "Right")
                hs.eventtap.keyStroke({"cmd"}, "c")
                verifyClipboard("one two three", "docStart")
            end
        },
    }

    -- Add killToStart test (continued in next section)
    table.insert(tests, {
        name = "killToStart",
        setup = function()
            hs.eventtap.keyStroke({"cmd"}, "Right")
        end,
        action = actions.killToStart,
        verify = function()
            clearClipboard()
            -- Type a marker, select all, verify only marker exists
            hs.eventtap.keyStrokes("X")
            hs.eventtap.keyStroke({"cmd"}, "a")
            hs.eventtap.keyStroke({"cmd"}, "c")
            verifyClipboard("X", "killToStart")
        end
    })

    -- Run tests sequentially in TextEdit
    print("\n=== Readline E2E Tests ===")
    print("Opening TextEdit...")

    hs.application.launchOrFocus("TextEdit")
    hs.timer.doAfter(0.5, function()
        -- Create new document
        hs.eventtap.keyStroke({"cmd"}, "n")
        hs.timer.doAfter(0.3, function()
            local currentTest = 1
            local function runNextTest()
                if currentTest > #tests then
                    print("\n=== Tests Complete ===")
                    return
                end

                local test = tests[currentTest]
                print("\nRunning: " .. test.name)

                -- Reset: select all, type test text
                hs.eventtap.keyStroke({"cmd"}, "a")
                hs.eventtap.keyStrokes(testText)
                hs.timer.doAfter(delay, function()
                    test.setup()
                    hs.timer.doAfter(delay, function()
                        test.action()
                        hs.timer.doAfter(delay, function()
                            test.verify()
                            currentTest = currentTest + 1
                            hs.timer.doAfter(delay * 2, runNextTest)
                        end)
                    end)
                end)
            end
            runNextTest()
        end)
    end)
end

return M

