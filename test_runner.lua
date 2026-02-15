#!/usr/bin/env lua
--- CI Test Runner for Spoons
--- Runs unit tests with mocked Hammerspoon APIs
--- Usage: lua test_runner.lua

-- Create mock hs namespace
hs = {
    eventtap = {
        keyStroke = function(mods, key)
            -- Will be mocked by tests
        end,
        keyStrokes = function(text) end,
    },
    pasteboard = {
        setContents = function(text) end,
        getContents = function() return "" end,
    },
    timer = {
        doAfter = function(delay, fn) fn() end,
    },
    application = {
        launchOrFocus = function(name) end,
    },
    spoons = {
        scriptPath = function() return "." end,
    },
    menubar = {
        new = function()
            return {
                setTitle = function() end,
                setTooltip = function() end,
                setMenu = function() end,
                returnToMenuBar = function() end,
                delete = function() end,
            }
        end,
    },
    hotkey = {
        bind = function()
            return {
                delete = function() end,
                enable = function() end,
                disable = function() end,
            }
        end,
    },
    settings = {
        get = function() return nil end,
        set = function() end,
    },
    grid = {
        setGrid = function() end,
        setMargins = function() end,
        getGrid = function() return { w = 6, h = 6 } end,
        get = function() return { x = 0, y = 0, w = 1, h = 1 } end,
        set = function() end,
        show = function() end,
    },
    geometry = {
        rect = function(x, y, w, h) return { x = x, y = y, w = w, h = h } end,
        point = function(x, y) return { x = x, y = y } end,
        size = function(w, h) return { w = w, h = h } end,
    },
    window = {
        focusedWindow = function() return nil end,
        filter = {
            new = function() return { getWindows = function() return {} end } end,
        },
    },
    screen = {
        mainScreen = function()
            return {
                frame = function() return { x = 0, y = 0, w = 1920, h = 1080 } end,
            }
        end,
        allScreens = function() return {} end,
    },
}

-- Set up package.preload so require("hs.module") returns the mock
local hsModules = {
    "hs.pasteboard", "hs.settings", "hs.timer", "hs.eventtap",
    "hs.application", "hs.spoons", "hs.menubar", "hs.hotkey",
    "hs.grid", "hs.geometry", "hs.window", "hs.screen",
}
for _, modName in ipairs(hsModules) do
    local submodule = modName:match("^hs%.(.+)$")
    if submodule and hs[submodule] then
        package.preload[modName] = function() return hs[submodule] end
    end
end

-- Mock spoon namespace
spoon = {
    Readline = nil,  -- Will be loaded
}

-- Load the Readline spoon
local function loadSpoon(path)
    local chunk, err = loadfile(path .. "/init.lua")
    if not chunk then
        print("ERROR: Failed to load " .. path .. "/init.lua: " .. tostring(err))
        os.exit(1)
    end
    return chunk()
end

-- Run unit tests for a spoon
local function runSpoonTests(spoonPath, spoonName)
    print("Loading " .. spoonName .. " from " .. spoonPath)
    
    -- Load the spoon
    local spoonModule = loadSpoon(spoonPath)
    spoon[spoonName] = spoonModule
    
    -- Load and run tests
    local testPath = spoonPath .. "/test.lua"
    local testChunk, err = loadfile(testPath)
    if not testChunk then
        print("ERROR: Failed to load " .. testPath .. ": " .. tostring(err))
        os.exit(1)
    end
    
    local testModule = testChunk()
    
    if testModule.runUnit then
        print("\n" .. string.rep("=", 60))
        print("Running unit tests for " .. spoonName)
        print(string.rep("=", 60))
        local success = testModule.runUnit()
        return success
    else
        print("WARN: No runUnit() found in " .. testPath)
        return true
    end
end

-- Main
local function main()
    local allPassed = true
    local spoonDir = arg[1] or "Source"
    
    -- Find all spoons in Source/
    local handle = io.popen('ls -d ' .. spoonDir .. '/*.spoon 2>/dev/null')
    if not handle then
        print("ERROR: Cannot list spoons in " .. spoonDir)
        os.exit(1)
    end
    
    local spoons = {}
    for line in handle:lines() do
        table.insert(spoons, line)
    end
    handle:close()
    
    if #spoons == 0 then
        print("No spoons found in " .. spoonDir)
        os.exit(1)
    end
    
    for _, spoonPath in ipairs(spoons) do
        local spoonName = spoonPath:match("([^/]+)%.spoon$")
        if spoonName then
            local success = runSpoonTests(spoonPath, spoonName)
            if not success then
                allPassed = false
            end
        end
    end
    
    print("\n" .. string.rep("=", 60))
    if allPassed then
        print("ALL TESTS PASSED")
        os.exit(0)
    else
        print("SOME TESTS FAILED")
        os.exit(1)
    end
end

main()

