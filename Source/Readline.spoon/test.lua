--- Readline.spoon Test Suite
--- Run with: require("Readline.spoon.test").runE2E()

local M = {}

local actions = spoon.Readline and spoon.Readline.actions or require("init").actions

-- E2E Tests - run in TextEdit
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

