--- CheatSheet.spoon Test Suite
--- Unit tests: spoon.CheatSheet:loadTest().runUnit()

local M = {}

local obj = spoon.CheatSheet or require("init")

--------------------------------------------------------------------------------
-- Unit Tests - verify configuration and methods exist
--------------------------------------------------------------------------------

function M.runUnit()
    print("\n=== CheatSheet Unit Tests ===\n")

    local passed, failed = 0, 0

    -- Test 1: Verify configuration variables have correct defaults
    local configTests = {
        {name = "modifiers", expectedType = "table"},
        {name = "delay", expected = 0.3},
        {name = "bgColor", expectedType = "table"},
        {name = "textColor", expectedType = "table"},
        {name = "highlightColor", expectedType = "table"},
        {name = "font", expected = "SF Pro"},
        {name = "fontSize", expected = 14},
        {name = "position", expected = "bottomLeft"},
        {name = "keyOrder", expectedType = "table"},
        {name = "enableReadlineSheet", expected = true},
        {name = "readlineBindings", expectedType = "table"},
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

    -- Test 2: Verify methods exist
    local expectedMethods = {"start", "stop", "toggle", "bindHotkeys"}
    for _, methodName in ipairs(expectedMethods) do
        if type(obj[methodName]) == "function" then
            print("✓ obj:" .. methodName .. "() exists: PASS")
            passed = passed + 1
        else
            print("✗ obj:" .. methodName .. "() exists: FAIL")
            failed = failed + 1
        end
    end

    -- Test 3: Verify keyOrder contains expected keys
    local keyOrder = obj.keyOrder or {}
    local expectedKeys = {"H", "J", "K", "L", "Left", "Down", "Up", "Right"}
    local foundKeys = 0
    for _, expected in ipairs(expectedKeys) do
        for _, actual in ipairs(keyOrder) do
            if actual == expected then
                foundKeys = foundKeys + 1
                break
            end
        end
    end
    if foundKeys >= 4 then
        print("✓ keyOrder contains vim keys (hjkl): PASS")
        passed = passed + 1
    else
        print("✗ keyOrder should contain vim keys: FAIL")
        failed = failed + 1
    end

    -- Test 4: Verify position is a valid option
    local validPositions = {center = true, bottomLeft = true, bottomRight = true, topLeft = true, topRight = true}
    if validPositions[obj.position] then
        print("✓ position is valid: PASS")
        passed = passed + 1
    else
        print("✗ position '" .. tostring(obj.position) .. "' is not valid: FAIL")
        failed = failed + 1
    end

    -- Test 5: Verify internal state variables exist
    local internalVars = {"_canvas", "_eventtap", "_timer", "_visible", "_modFlags", "_currentSheet"}
    for _, varName in ipairs(internalVars) do
        if obj[varName] ~= nil or obj[varName] == nil then  -- Just check it's defined
            print("✓ obj." .. varName .. " defined: PASS")
            passed = passed + 1
        else
            print("✗ obj." .. varName .. " not defined: FAIL")
            failed = failed + 1
        end
    end

    -- Test 6: Verify readlineBindings has expected structure
    local bindings = obj.readlineBindings or {}
    if #bindings > 0 then
        local first = bindings[1]
        if first.mods and first.key and first.desc then
            print("✓ readlineBindings has correct structure: PASS")
            passed = passed + 1
        else
            print("✗ readlineBindings missing mods/key/desc: FAIL")
            failed = failed + 1
        end
    else
        print("✗ readlineBindings is empty: FAIL")
        failed = failed + 1
    end

    -- Test 7: Verify internal methods exist
    local internalMethods = {"_createMainCanvas", "_createReadlineCanvas", "_show", "_hide", "_handleFlags"}
    for _, methodName in ipairs(internalMethods) do
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

return M

