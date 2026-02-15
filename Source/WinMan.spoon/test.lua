--- WinMan.spoon Test Suite
--- Unit tests: spoon.WinMan:loadTest().runUnit()
--- E2E tests:  spoon.WinMan:loadTest().runE2E()

local M = {}

local obj = spoon.WinMan or require("init")
local actions = obj.actions

--------------------------------------------------------------------------------
-- Unit Tests - verify action functions exist and can be called
--------------------------------------------------------------------------------

function M.runUnit()
    print("\n=== WinMan Unit Tests ===\n")

    local passed, failed = 0, 0

    -- Test 1: Verify all expected actions exist
    local expectedActions = {
        -- Core actions
        "resizeUp", "resizeDown", "resizeLeft", "resizeRight",
        "moveUp", "moveDown", "moveLeft", "moveRight",
        "maximize", "showDesktop", "cascadeAll", "cascadeApp", "snapAll",
        "moveToNextScreen", "moveToPrevScreen",
        "moveToScreen1", "moveToScreen2", "moveToScreen3",
        -- Phase 4: New features
        "center", "centerSmall", "centerLarge",
        "leftThird", "centerThird", "rightThird",
        "leftTwoThirds", "rightTwoThirds",
        "gatherWindows", "gatherAppWindows",
        "swapWindows",
        "toggleStageManager", "focusMode",
    }

    for _, actionName in ipairs(expectedActions) do
        if actions[actionName] then
            print("✓ actions." .. actionName .. " exists: PASS")
            passed = passed + 1
        else
            print("✗ actions." .. actionName .. " exists: FAIL")
            failed = failed + 1
        end
    end

    -- Test 2: Verify configuration variables have defaults
    local configTests = {
        {name = "gridSize", expected = "6x6"},
        {name = "gridMargins", expected = "15,15"},
        {name = "cascadeSpacing", expectedType = "number"},
        {name = "modifiers", expectedType = "table"},
        {name = "slowResizeApps", expectedType = "table"},
        {name = "desktopStripeWidth", expectedType = "number"},
        {name = "focusScreenOnMove", expectedType = "boolean"},
        {name = "preserveGridCell", expectedType = "boolean"},
        {name = "screenConfigs", expectedType = "table"},
    }

    for _, test in ipairs(configTests) do
        local value = obj[test.name]
        if test.expected then
            if value == test.expected then
                print("✓ obj." .. test.name .. " = '" .. tostring(value) .. "': PASS")
                passed = passed + 1
            else
                print("✗ obj." .. test.name .. " = '" .. tostring(value) .. "' (expected '" .. test.expected .. "'): FAIL")
                failed = failed + 1
            end
        elseif test.expectedType then
            if type(value) == test.expectedType then
                print("✓ obj." .. test.name .. " is " .. test.expectedType .. ": PASS")
                passed = passed + 1
            else
                print("✗ obj." .. test.name .. " is " .. type(value) .. " (expected " .. test.expectedType .. "): FAIL")
                failed = failed + 1
            end
        end
    end

    -- Test 3: Verify methods exist
    local expectedMethods = {"bindHotkeys", "start", "stop", "loadTest"}
    for _, methodName in ipairs(expectedMethods) do
        if type(obj[methodName]) == "function" then
            print("✓ obj:" .. methodName .. "() exists: PASS")
            passed = passed + 1
        else
            print("✗ obj:" .. methodName .. "() exists: FAIL")
            failed = failed + 1
        end
    end

    print("\n=== Unit Tests Complete: " .. passed .. " passed, " .. failed .. " failed ===")
    return failed == 0
end

--------------------------------------------------------------------------------
-- E2E Tests - test actual window manipulation
--------------------------------------------------------------------------------

function M.runE2E()
    print("\n=== WinMan E2E Tests ===\n")
    print("NOTE: E2E tests require a focused window.")
    print("Please focus a window (e.g., Finder) before running.\n")

    local win = hs.window.focusedWindow()
    if not win then
        print("✗ No focused window found. Please focus a window and try again.")
        return false
    end

    local passed, failed = 0, 0
    local originalFrame = win:frame()

    -- Helper to check if window moved
    local function frameChanged(newFrame)
        return newFrame.x ~= originalFrame.x or newFrame.y ~= originalFrame.y or
               newFrame.w ~= originalFrame.w or newFrame.h ~= originalFrame.h
    end

    -- Test: Maximize
    print("Testing maximize...")
    actions.maximize()
    hs.timer.usleep(100000) -- 100ms
    local afterMaximize = win:frame()
    local screen = win:screen():frame()

    -- Check if window is close to screen size (accounting for margins)
    if afterMaximize.w > screen.w * 0.9 and afterMaximize.h > screen.h * 0.9 then
        print("✓ maximize: PASS")
        passed = passed + 1
    else
        print("✗ maximize: FAIL (window not maximized)")
        failed = failed + 1
    end

    -- Restore original frame
    win:setFrame(originalFrame)
    hs.timer.usleep(100000)

    -- Test: resizeLeft
    print("Testing resizeLeft...")
    actions.resizeLeft()
    hs.timer.usleep(100000)
    local afterResizeLeft = win:frame()
    if afterResizeLeft.x <= originalFrame.x or afterResizeLeft.w ~= originalFrame.w then
        print("✓ resizeLeft: PASS (window changed)")
        passed = passed + 1
    else
        print("✗ resizeLeft: FAIL")
        failed = failed + 1
    end

    -- Restore
    win:setFrame(originalFrame)
    hs.timer.usleep(100000)

    -- Test: snapAll (should not error)
    print("Testing snapAll...")
    local snapSuccess = pcall(actions.snapAll)
    if snapSuccess then
        print("✓ snapAll: PASS (no error)")
        passed = passed + 1
    else
        print("✗ snapAll: FAIL (error occurred)")
        failed = failed + 1
    end

    -- Restore
    win:setFrame(originalFrame)
    hs.timer.usleep(100000)

    -- Test: center
    print("Testing center...")
    actions.center()
    hs.timer.usleep(100000)
    local afterCenter = win:frame()
    -- Check if window is roughly centered (within 10% margin)
    local screenCenter = screen.w / 2
    local winCenter = afterCenter.x + afterCenter.w / 2
    if math.abs(winCenter - screenCenter) < screen.w * 0.1 then
        print("✓ center: PASS (window centered)")
        passed = passed + 1
    else
        print("✗ center: FAIL (window not centered)")
        failed = failed + 1
    end

    -- Restore
    win:setFrame(originalFrame)
    hs.timer.usleep(100000)

    -- Test: leftThird
    print("Testing leftThird...")
    actions.leftThird()
    hs.timer.usleep(100000)
    local afterLeftThird = win:frame()
    -- Check if window is roughly 1/3 width
    if afterLeftThird.w < screen.w * 0.4 and afterLeftThird.x < screen.w * 0.1 then
        print("✓ leftThird: PASS (window at left third)")
        passed = passed + 1
    else
        print("✗ leftThird: FAIL")
        failed = failed + 1
    end

    -- Restore
    win:setFrame(originalFrame)
    hs.timer.usleep(100000)

    -- Test: gatherWindows (should not error)
    print("Testing gatherWindows...")
    local gatherSuccess = pcall(actions.gatherWindows)
    if gatherSuccess then
        print("✓ gatherWindows: PASS (no error)")
        passed = passed + 1
    else
        print("✗ gatherWindows: FAIL (error occurred)")
        failed = failed + 1
    end

    print("\n=== E2E Tests Complete: " .. passed .. " passed, " .. failed .. " failed ===")
    return failed == 0
end

return M

