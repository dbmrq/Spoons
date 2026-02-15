--- === WinMan ===
---
--- Grid-based window management with automatic cascading for overlapping windows.
--- Resize and position windows using a customizable grid, with support for
--- multi-monitor setups, window cascading, and various layout shortcuts.
---
--- Download: [https://github.com/dbmrq/Spoons/raw/master/Spoons/WinMan.spoon.zip](https://github.com/dbmrq/Spoons/raw/master/Spoons/WinMan.spoon.zip)

local obj = {}
obj.__index = obj

-- Metadata
obj.name = "WinMan"
obj.version = "1.0"
obj.author = "Daniel Marques <danielbmarques@gmail.com>"
obj.license = "MIT"
obj.homepage = "https://github.com/dbmrq/Spoons"

-- Hammerspoon modules
local grid = require("hs.grid")
local geometry = require("hs.geometry")
local window = require("hs.window")
local screen = require("hs.screen")
local hotkey = require("hs.hotkey")
local timer = require("hs.timer")

---------------------------------------------------------------------------
-- Configuration Variables
---------------------------------------------------------------------------

--- WinMan.gridSize
--- Variable
--- Grid dimensions as "WxH" string. Default: "6x6"
obj.gridSize = "6x6"

--- WinMan.gridMargins
--- Variable
--- Margins between windows as "X,Y" string. Default: "15,15"
obj.gridMargins = "15,15"

--- WinMan.cascadeSpacing
--- Variable
--- Pixel offset between cascaded windows. Set to 0 to disable cascading. Default: 40
obj.cascadeSpacing = 40

--- WinMan.modifiers
--- Variable
--- Modifier keys for all hotkeys. Default: {"ctrl", "alt", "cmd"}
obj.modifiers = {"ctrl", "alt", "cmd"}

--- WinMan.slowResizeApps
--- Variable
--- Apps that need delayed cascade check due to slow resize. Default: {"Terminal", "MacVim"}
obj.slowResizeApps = {"Terminal", "MacVim"}

--- WinMan.desktopStripeWidth
--- Variable
--- Width of desktop stripe shown by showDesktop action. Default: 128
obj.desktopStripeWidth = 128

--- WinMan.focusScreenOnMove
--- Variable
--- Whether to move mouse cursor to center of screen when moving window to another screen. Default: false
obj.focusScreenOnMove = false

--- WinMan.preserveGridCell
--- Variable
--- When moving windows between screens, preserve grid cell position (e.g., left-half stays left-half).
--- If false, uses relative pixel positioning instead. Default: true
obj.preserveGridCell = true

--- WinMan.screenConfigs
--- Variable
--- Per-screen configuration overrides. Keys are screen names or "default".
--- Each entry can have: gridSize, gridMargins
--- Example: { ["Built-in Retina Display"] = { gridSize = "4x4" } }
obj.screenConfigs = {}

---------------------------------------------------------------------------
-- Default Hotkey Bindings
---------------------------------------------------------------------------

--- WinMan.defaultBindings
--- Variable
--- Default hotkey bindings. Format: actionName = key (uses obj.modifiers).
--- Set a binding to `false` to disable it.
obj.defaultBindings = {
    -- Resize (anchor to edge, toggle grow/shrink)
    resizeUp = "K",
    resizeDown = "J",
    resizeLeft = "H",
    resizeRight = "L",

    -- Move (push window in direction)
    moveUp = "Up",
    moveDown = "Down",
    moveLeft = "Left",
    moveRight = "Right",

    -- Layout actions
    maximize = ";",
    showDesktop = "O",
    cascadeAll = ",",
    cascadeApp = ".",
    snapAll = "/",

    -- Multi-monitor
    moveToNextScreen = "N",
    moveToPrevScreen = "P",
    moveToScreen1 = "1",
    moveToScreen2 = "2",
    moveToScreen3 = "3",

    -- New features (Phase 4)
    center = false,
    centerSmall = false,
    centerLarge = false,
    leftThird = false,
    centerThird = false,
    rightThird = false,
    leftTwoThirds = false,
    rightTwoThirds = false,
    gatherWindows = false,
    gatherAppWindows = false,
    swapWindows = false,
    toggleStageManager = false,
    focusMode = false,
}

--- WinMan.actionDescriptions
--- Variable
--- Human-readable descriptions for actions (used by CheatSheet)
obj.actionDescriptions = {
    resizeUp = "Resize ↑",
    resizeDown = "Resize ↓",
    resizeLeft = "Resize ←",
    resizeRight = "Resize →",
    moveUp = "Move ↑",
    moveDown = "Move ↓",
    moveLeft = "Move ←",
    moveRight = "Move →",
    maximize = "Maximize",
    showDesktop = "Show Desktop",
    cascadeAll = "Cascade All",
    cascadeApp = "Cascade App",
    snapAll = "Snap All",
    moveToNextScreen = "Next Screen",
    moveToPrevScreen = "Prev Screen",
    moveToScreen1 = "Screen 1",
    moveToScreen2 = "Screen 2",
    moveToScreen3 = "Screen 3",
    center = "Center",
    centerSmall = "Center Small",
    centerLarge = "Center Large",
    leftThird = "Left ⅓",
    centerThird = "Center ⅓",
    rightThird = "Right ⅓",
    leftTwoThirds = "Left ⅔",
    rightTwoThirds = "Right ⅔",
    gatherWindows = "Gather All",
    gatherAppWindows = "Gather App",
    swapWindows = "Swap Windows",
    toggleStageManager = "Stage Manager",
    focusMode = "Focus Mode",
}

-- Internal state
obj._hotkeys = {}
obj._gridWidth = 6
obj._gridHeight = 6
obj._screenWatcher = nil
obj._windowFilter = nil  -- For tracking window focus
obj._lastFocusedWindow = nil  -- For swap windows feature
obj._previousFocusedWindow = nil  -- The window before the last focused
obj._stageManagerEnabled = false  -- Track Stage Manager state

---------------------------------------------------------------------------
-- Private Helper Functions
---------------------------------------------------------------------------

local function parseGridSize(sizeStr)
    local w, h = sizeStr:match("(%d+)x(%d+)")
    return tonumber(w) or 6, tonumber(h) or 6
end

-- Get grid configuration for a specific screen
local function getScreenConfig(scr)
    if not scr then
        return obj.gridSize, obj.gridMargins
    end

    local screenName = scr:name()
    local config = obj.screenConfigs[screenName] or obj.screenConfigs["default"] or {}

    local gridSize = config.gridSize or obj.gridSize
    local gridMargins = config.gridMargins or obj.gridMargins

    return gridSize, gridMargins
end

-- Get grid dimensions for a specific screen
local function getGridDimensions(scr)
    local gridSize = getScreenConfig(scr)
    return parseGridSize(gridSize)
end

-- Apply grid settings for a specific screen
local function applyGridForScreen(scr)
    local gridSize, gridMargins = getScreenConfig(scr)
    grid.setGrid(gridSize, scr)
    grid.setMargins(gridMargins)
    return parseGridSize(gridSize)
end

local function snapToTop(win, cell, scr)
    local newCell = geometry(cell.x, 0, cell.w, cell.h)
    grid.set(win, newCell, scr)
end

local function snapToBottom(win, cell, scr)
    local gridW, gridH = getGridDimensions(scr)
    local newCell = geometry(cell.x, gridH - cell.h, cell.w, cell.h)
    grid.set(win, newCell, scr)
end

local function snapToLeft(win, cell, scr)
    local newCell = geometry(0, cell.y, cell.w, cell.h)
    grid.set(win, newCell, scr)
end

local function snapToRight(win, cell, scr)
    local gridW, gridH = getGridDimensions(scr)
    local newCell = geometry(gridW - cell.w, cell.y, cell.w, cell.h)
    grid.set(win, newCell, scr)
end

local function maxX(frame)
    return frame.x + frame.w
end

local function maxY(frame)
    return frame.y + frame.h
end

local function xOverlaps(frameA, frameB)
    local aMaxX, bMaxX = maxX(frameA), maxX(frameB)
    return (frameA.x >= frameB.x and frameA.x <= bMaxX) or
           (aMaxX >= frameB.x and aMaxX <= bMaxX)
end

local function yOverlaps(frameA, frameB)
    local aMaxY, bMaxY = maxY(frameA), maxY(frameB)
    return (frameA.y >= frameB.y and frameA.y <= bMaxY) or
           (aMaxY >= frameB.y and aMaxY <= bMaxY)
end

local function overlaps(frameA, frameB)
    return xOverlaps(frameA, frameB) and yOverlaps(frameA, frameB)
end

local function areCascaded(frameA, frameB, spacing)
    return math.abs(frameA.w - frameB.w) % spacing == 0 and
           math.abs(frameA.h - frameB.h) % spacing == 0 and
           math.abs(frameA.x - frameB.x) % spacing == 0 and
           math.abs(frameA.y - frameB.y) % spacing == 0
end

local function largestFrame(windows)
    local scr = windows[1]:screen():frame()
    local minX, minY = scr.w, scr.h
    local maxXVal, maxYVal = 0, 0

    for _, win in ipairs(windows) do
        local f = win:frame()
        if f.x < minX then minX = f.x end
        if f.y < minY then minY = f.y end
    end
    for _, win in ipairs(windows) do
        local f = win:frame()
        local wx, wy = f.x + f.w, f.y + f.h
        if wx > maxXVal then maxXVal = wx end
        if wy > maxYVal then maxYVal = wy end
    end

    return {x = minX, y = minY, w = maxXVal - minX, h = maxYVal - minY}
end

local function cascadeWindows(windows, spacing)
    if #windows <= 1 or spacing == 0 then return end
    local frame = largestFrame(windows)
    local nOfSpaces = #windows - 1

    for i, win in ipairs(windows) do
        local offset = (i - 1) * spacing
        local rect = {
            x = frame.x + offset,
            y = frame.y + offset,
            w = frame.w - (nOfSpaces * spacing),
            h = frame.h - (nOfSpaces * spacing),
        }
        win:setFrame(rect)
    end
end

-- Check if two windows are on the same screen
local function onSameScreen(winA, winB)
    if not winA or not winB then return false end
    local scrA, scrB = winA:screen(), winB:screen()
    if not scrA or not scrB then return false end
    return scrA:id() == scrB:id()
end

local function cascadeWindowsOverlapping(winA, spacing)
    if spacing == 0 then return {} end
    local allWindows = window.allWindows()
    local overlappingWindows = {winA}
    local frameA = winA:frame()

    for _, winB in ipairs(allWindows) do
        -- Only cascade windows on the same screen
        if winA:id() ~= winB:id() and onSameScreen(winA, winB) then
            local frameB = winB:frame()
            if overlaps(frameA, frameB) and areCascaded(frameA, frameB, spacing) then
                table.insert(overlappingWindows, winB)
            end
        end
    end

    cascadeWindows(overlappingWindows, spacing)
    return overlappingWindows
end

local function cascadeAllOverlapping(spacing, slowApps, secondPass)
    if spacing == 0 then return end
    local allWindows = window.allWindows()
    local cascadedWindows = {}
    local needsSecondPass = false

    for _, win in ipairs(allWindows) do
        local app = win:application()
        if app then
            local title = app:title()
            for _, slowApp in ipairs(slowApps or {}) do
                if title == slowApp then
                    needsSecondPass = true
                    break
                end
            end
        end

        if not cascadedWindows[win:id()] then
            local currentCascading = cascadeWindowsOverlapping(win, spacing)
            for _, cascadedWin in ipairs(currentCascading) do
                cascadedWindows[cascadedWin:id()] = true
            end
        end
    end

    if needsSecondPass and not secondPass then
        timer.doAfter(1, function()
            cascadeAllOverlapping(spacing, slowApps, true)
        end)
    end
end

-- Multi-monitor helpers
local function getSortedScreens()
    local screens = screen.allScreens()
    table.sort(screens, function(a, b)
        local aFrame, bFrame = a:frame(), b:frame()
        if aFrame.x ~= bFrame.x then
            return aFrame.x < bFrame.x
        end
        return aFrame.y < bFrame.y
    end)
    return screens
end

local function getScreenIndex(scr, screens)
    for i, s in ipairs(screens) do
        if s:id() == scr:id() then
            return i
        end
    end
    return 1
end

local function moveWindowToScreen(win, targetScreen, preserveGridCell)
    if not win or not targetScreen then return end

    local currentScreen = win:screen()
    if not currentScreen then return end
    if currentScreen:id() == targetScreen:id() then return end

    local currentFrame = currentScreen:frame()
    local targetFrame = targetScreen:frame()
    local winFrame = win:frame()

    if preserveGridCell then
        -- Preserve grid cell position (e.g., left-half stays left-half)
        local cell = grid.get(win, currentScreen)
        if cell then
            -- Apply grid settings for target screen
            applyGridForScreen(targetScreen)
            grid.set(win, cell, targetScreen)
        else
            -- Fallback to relative positioning
            local relX = (winFrame.x - currentFrame.x) / currentFrame.w
            local relY = (winFrame.y - currentFrame.y) / currentFrame.h
            local relW = winFrame.w / currentFrame.w
            local relH = winFrame.h / currentFrame.h

            local newFrame = {
                x = targetFrame.x + (relX * targetFrame.w),
                y = targetFrame.y + (relY * targetFrame.h),
                w = relW * targetFrame.w,
                h = relH * targetFrame.h,
            }
            win:setFrame(newFrame)
        end
    else
        -- Use relative positioning (percentage-based)
        local relX = (winFrame.x - currentFrame.x) / currentFrame.w
        local relY = (winFrame.y - currentFrame.y) / currentFrame.h
        local relW = winFrame.w / currentFrame.w
        local relH = winFrame.h / currentFrame.h

        local newFrame = {
            x = targetFrame.x + (relX * targetFrame.w),
            y = targetFrame.y + (relY * targetFrame.h),
            w = relW * targetFrame.w,
            h = relH * targetFrame.h,
        }
        win:setFrame(newFrame)
    end

    -- Optionally focus the target screen
    if obj.focusScreenOnMove then
        local center = targetScreen:frame().center
        hs.mouse.absolutePosition(center)
    end
end


---------------------------------------------------------------------------
-- Actions (callable methods)
---------------------------------------------------------------------------

--- WinMan.actions
--- Variable
--- Table of action functions that can be called directly or bound to hotkeys.
obj.actions = {}

-- Resize actions use a shared grow state per direction
local growVertical = true
local growHorizontal = true

function obj.actions.resizeUp()
    local win = window.focusedWindow()
    if not win then return end
    local scr = win:screen()
    if not scr then return end

    -- Apply grid for this screen
    local gridW, gridH = applyGridForScreen(scr)
    local cell = grid.get(win)
    if not cell then return end

    -- If not at top, snap to top
    if cell.y > 0 then
        snapToTop(win, cell, scr)
        cascadeAllOverlapping(obj.cascadeSpacing, obj.slowResizeApps)
        return
    end

    -- Toggle grow/shrink based on size
    if cell.h <= 2 then
        growVertical = true
    elseif cell.h >= gridH then
        growVertical = false
    end

    -- Resize
    if growVertical and cell.h >= 4 then
        grid.resizeWindowTaller()
        grid.resizeWindowTaller()
    elseif growVertical then
        grid.resizeWindowTaller()
    elseif cell.h >= 6 then
        grid.resizeWindowShorter()
        grid.resizeWindowShorter()
    else
        grid.resizeWindowShorter()
    end

    cell = grid.get(win)
    snapToTop(win, cell, scr)
    cascadeAllOverlapping(obj.cascadeSpacing, obj.slowResizeApps)
end

function obj.actions.resizeDown()
    local win = window.focusedWindow()
    if not win then return end
    local scr = win:screen()
    if not scr then return end

    -- Apply grid for this screen
    local gridW, gridH = applyGridForScreen(scr)
    local cell = grid.get(win)
    if not cell then return end

    -- If not at bottom, snap to bottom
    if cell.y < gridH - cell.h then
        snapToBottom(win, cell, scr)
        cascadeAllOverlapping(obj.cascadeSpacing, obj.slowResizeApps)
        return
    end

    -- Toggle grow/shrink based on size
    if cell.h <= 2 then
        growVertical = true
    elseif cell.h >= gridH then
        growVertical = false
    end

    -- Resize
    if growVertical and cell.h >= 4 then
        grid.resizeWindowTaller()
        grid.resizeWindowTaller()
    elseif growVertical then
        grid.resizeWindowTaller()
    elseif cell.h >= 6 then
        grid.resizeWindowShorter()
        grid.resizeWindowShorter()
    else
        grid.resizeWindowShorter()
    end

    cell = grid.get(win)
    snapToBottom(win, cell, scr)
    cascadeAllOverlapping(obj.cascadeSpacing, obj.slowResizeApps)
end

function obj.actions.resizeLeft()
    local win = window.focusedWindow()
    if not win then return end
    local scr = win:screen()
    if not scr then return end

    -- Apply grid for this screen
    local gridW, gridH = applyGridForScreen(scr)
    local cell = grid.get(win)
    if not cell then return end

    -- If not at left, snap to left
    if cell.x > 0 then
        snapToLeft(win, cell, scr)
        cascadeAllOverlapping(obj.cascadeSpacing, obj.slowResizeApps)
        return
    end

    -- Toggle grow/shrink based on size
    if cell.w <= 2 then
        growHorizontal = true
    elseif cell.w >= gridW then
        growHorizontal = false
    end

    -- Resize
    if growHorizontal and cell.w >= 4 then
        grid.resizeWindowWider()
        grid.resizeWindowWider()
    elseif growHorizontal then
        grid.resizeWindowWider()
    elseif cell.w >= 6 then
        grid.resizeWindowThinner()
        grid.resizeWindowThinner()
    else
        grid.resizeWindowThinner()
    end

    cell = grid.get(win)
    snapToLeft(win, cell, scr)
    cascadeAllOverlapping(obj.cascadeSpacing, obj.slowResizeApps)
end

function obj.actions.resizeRight()
    local win = window.focusedWindow()
    if not win then return end
    local scr = win:screen()
    if not scr then return end

    -- Apply grid for this screen
    local gridW, gridH = applyGridForScreen(scr)
    local cell = grid.get(win)
    if not cell then return end

    -- If not at right, snap to right
    if cell.x < gridW - cell.w then
        snapToRight(win, cell, scr)
        cascadeAllOverlapping(obj.cascadeSpacing, obj.slowResizeApps)
        return
    end

    -- Toggle grow/shrink based on size
    if cell.w <= 2 then
        growHorizontal = true
    elseif cell.w >= gridW then
        growHorizontal = false
    end

    -- Resize
    if growHorizontal and cell.w >= 4 then
        grid.resizeWindowWider()
        grid.resizeWindowWider()
    elseif growHorizontal then
        grid.resizeWindowWider()
    elseif cell.w >= 6 then
        grid.resizeWindowThinner()
        grid.resizeWindowThinner()
    else
        grid.resizeWindowThinner()
    end

    cell = grid.get(win)
    snapToRight(win, cell, scr)
    cascadeAllOverlapping(obj.cascadeSpacing, obj.slowResizeApps)
end

-- Move actions (push window in grid increments)
function obj.actions.moveUp()
    local win = window.focusedWindow()
    if not win then return end
    local scr = win:screen()
    if not scr then return end

    applyGridForScreen(scr)
    local cell = grid.get(win)
    if not cell or cell.y == 0 then return end

    local steps = (cell.h == 3) and 3 or 2
    for _ = 1, steps do grid.pushWindowUp() end
    cascadeAllOverlapping(obj.cascadeSpacing, obj.slowResizeApps)
end

function obj.actions.moveDown()
    local win = window.focusedWindow()
    if not win then return end
    local scr = win:screen()
    if not scr then return end

    local gridW, gridH = applyGridForScreen(scr)
    local cell = grid.get(win)
    if not cell or cell.y + cell.h >= gridH then return end

    local steps = (cell.h == 3) and 3 or 2
    for _ = 1, steps do grid.pushWindowDown() end
    cascadeAllOverlapping(obj.cascadeSpacing, obj.slowResizeApps)
end

function obj.actions.moveLeft()
    local win = window.focusedWindow()
    if not win then return end
    local scr = win:screen()
    if not scr then return end

    applyGridForScreen(scr)
    local cell = grid.get(win)
    if not cell or cell.x == 0 then return end

    local steps = (cell.w == 3) and 3 or 2
    for _ = 1, steps do grid.pushWindowLeft() end
    cascadeAllOverlapping(obj.cascadeSpacing, obj.slowResizeApps)
end

function obj.actions.moveRight()
    local win = window.focusedWindow()
    if not win then return end
    local scr = win:screen()
    if not scr then return end

    local gridW, gridH = applyGridForScreen(scr)
    local cell = grid.get(win)
    if not cell or cell.x + cell.w >= gridW then return end

    local steps = (cell.w == 3) and 3 or 2
    for _ = 1, steps do grid.pushWindowRight() end
    cascadeAllOverlapping(obj.cascadeSpacing, obj.slowResizeApps)
end

-- Layout actions
function obj.actions.maximize()
    local win = window.focusedWindow()
    if win then grid.maximizeWindow(win) end
end

function obj.actions.showDesktop()
    local windows = window.visibleWindows()
    if not windows or #windows == 0 then return end

    local desktopWin = window.desktop()
    if not desktopWin then return end
    local desktop = desktopWin:frame()
    if not desktop then return end

    local finished = false
    local stripeWidth = obj.desktopStripeWidth

    for _, win in ipairs(windows) do
        local frame = win:frame()
        if frame and frame.x + frame.w > desktop.w - stripeWidth then
            frame.w = desktop.w - frame.x - stripeWidth
            win:setFrame(frame)
            finished = true
        end
    end

    if finished then return end

    -- Restore windows if already showing stripe
    for _, win in ipairs(windows) do
        local frame = win:frame()
        if frame and frame.x + frame.w == desktop.w - stripeWidth then
            frame.w = frame.w + (stripeWidth - 20)
            win:setFrame(frame)
        end
    end
end

function obj.actions.cascadeAll()
    if obj.cascadeSpacing == 0 then return end
    local windows = window.orderedWindows()
    if not windows or #windows == 0 then return end

    local firstWin = windows[1]
    if not firstWin then return end
    local firstScreen = firstWin:screen()
    if not firstScreen then return end
    local scr = firstScreen:frame()
    if not scr then return end

    local nOfSpaces = #windows - 1
    local xMargin = scr.w / 10
    local yMargin = 20

    local spacing = obj.cascadeSpacing * 10 / math.max(nOfSpaces, 1)
    if nOfSpaces > 10 then spacing = obj.cascadeSpacing end

    for i, win in ipairs(windows) do
        local offset = (i - 1) * spacing
        local rect = {
            x = xMargin + offset,
            y = scr.y + yMargin + offset,
            w = scr.w - (2 * xMargin) - (nOfSpaces * spacing),
            h = scr.h - (2 * yMargin) - (nOfSpaces * spacing),
        }
        win:setFrame(rect)
    end
end

function obj.actions.cascadeApp()
    if obj.cascadeSpacing == 0 then return end
    local focusedWin = window.focusedWindow()
    if not focusedWin then return end

    local focusedApp = focusedWin:application()
    if not focusedApp then return end

    local windows = window.orderedWindows()
    if not windows then return end

    local appWindows = {}
    for _, win in ipairs(windows) do
        local app = win:application()
        if app and app == focusedApp then
            table.insert(appWindows, win)
        end
    end

    if #appWindows == 0 then return end

    local firstWin = appWindows[1]
    if not firstWin then return end
    local firstScreen = firstWin:screen()
    if not firstScreen then return end
    local scr = firstScreen:frame()
    if not scr then return end

    local nOfSpaces = #appWindows - 1
    local xMargin = scr.w / 10
    local yMargin = 20

    local spacing = obj.cascadeSpacing * 10 / math.max(nOfSpaces, 1)
    if nOfSpaces > 10 then spacing = obj.cascadeSpacing end

    for i, win in ipairs(appWindows) do
        local offset = (i - 1) * spacing
        local rect = {
            x = xMargin + offset,
            y = scr.y + yMargin + offset,
            w = scr.w - (2 * xMargin) - (nOfSpaces * spacing),
            h = scr.h - (2 * yMargin) - (nOfSpaces * spacing),
        }
        win:setFrame(rect)
    end
end

function obj.actions.snapAll()
    local windows = window.visibleWindows()
    if not windows then return end
    for _, win in ipairs(windows) do
        if win then grid.snap(win) end
    end
end

-- Multi-monitor actions
function obj.actions.moveToNextScreen()
    local win = window.focusedWindow()
    if not win then return end

    local screens = getSortedScreens()
    if #screens < 2 then return end

    local currentIndex = getScreenIndex(win:screen(), screens)
    local nextIndex = (currentIndex % #screens) + 1
    moveWindowToScreen(win, screens[nextIndex], obj.preserveGridCell)
end

function obj.actions.moveToPrevScreen()
    local win = window.focusedWindow()
    if not win then return end

    local screens = getSortedScreens()
    if #screens < 2 then return end

    local currentIndex = getScreenIndex(win:screen(), screens)
    local prevIndex = ((currentIndex - 2) % #screens) + 1
    moveWindowToScreen(win, screens[prevIndex], obj.preserveGridCell)
end

function obj.actions.moveToScreen1()
    local win = window.focusedWindow()
    if not win then return end
    local screens = getSortedScreens()
    if #screens >= 1 then moveWindowToScreen(win, screens[1], obj.preserveGridCell) end
end

function obj.actions.moveToScreen2()
    local win = window.focusedWindow()
    if not win then return end
    local screens = getSortedScreens()
    if #screens >= 2 then moveWindowToScreen(win, screens[2], obj.preserveGridCell) end
end

function obj.actions.moveToScreen3()
    local win = window.focusedWindow()
    if not win then return end
    local screens = getSortedScreens()
    if #screens >= 3 then moveWindowToScreen(win, screens[3], obj.preserveGridCell) end
end

---------------------------------------------------------------------------
-- Phase 4: New Features
---------------------------------------------------------------------------

-- Center window at various sizes
local function centerWindowAtSize(sizeFraction)
    local win = window.focusedWindow()
    if not win then return end
    local scr = win:screen()
    if not scr then return end

    local screenFrame = scr:frame()
    local newW = screenFrame.w * sizeFraction
    local newH = screenFrame.h * sizeFraction
    local newX = screenFrame.x + (screenFrame.w - newW) / 2
    local newY = screenFrame.y + (screenFrame.h - newH) / 2

    win:setFrame({x = newX, y = newY, w = newW, h = newH})
end

function obj.actions.center()
    centerWindowAtSize(0.66)  -- 66% of screen
end

function obj.actions.centerSmall()
    centerWindowAtSize(0.50)  -- 50% of screen
end

function obj.actions.centerLarge()
    centerWindowAtSize(0.80)  -- 80% of screen
end

-- Quick thirds positioning
function obj.actions.leftThird()
    local win = window.focusedWindow()
    if not win then return end
    local scr = win:screen()
    if not scr then return end

    applyGridForScreen(scr)
    grid.set(win, geometry(0, 0, 2, 6), scr)  -- 2/6 = 1/3 width
end

function obj.actions.centerThird()
    local win = window.focusedWindow()
    if not win then return end
    local scr = win:screen()
    if not scr then return end

    applyGridForScreen(scr)
    grid.set(win, geometry(2, 0, 2, 6), scr)  -- middle 1/3
end

function obj.actions.rightThird()
    local win = window.focusedWindow()
    if not win then return end
    local scr = win:screen()
    if not scr then return end

    applyGridForScreen(scr)
    grid.set(win, geometry(4, 0, 2, 6), scr)  -- right 1/3
end

function obj.actions.leftTwoThirds()
    local win = window.focusedWindow()
    if not win then return end
    local scr = win:screen()
    if not scr then return end

    applyGridForScreen(scr)
    grid.set(win, geometry(0, 0, 4, 6), scr)  -- 4/6 = 2/3 width
end

function obj.actions.rightTwoThirds()
    local win = window.focusedWindow()
    if not win then return end
    local scr = win:screen()
    if not scr then return end

    applyGridForScreen(scr)
    grid.set(win, geometry(2, 0, 4, 6), scr)  -- right 2/3
end

-- Gather windows to current screen
function obj.actions.gatherWindows()
    local focusedWin = window.focusedWindow()
    if not focusedWin then return end
    local targetScreen = focusedWin:screen()
    if not targetScreen then return end

    local allWindows = window.allWindows()
    for _, win in ipairs(allWindows) do
        if win and win:screen() and win:screen():id() ~= targetScreen:id() then
            moveWindowToScreen(win, targetScreen, obj.preserveGridCell)
        end
    end
end

function obj.actions.gatherAppWindows()
    local focusedWin = window.focusedWindow()
    if not focusedWin then return end
    local targetScreen = focusedWin:screen()
    if not targetScreen then return end
    local focusedApp = focusedWin:application()
    if not focusedApp then return end

    local allWindows = window.allWindows()
    for _, win in ipairs(allWindows) do
        local app = win and win:application()
        if app and app == focusedApp and win:screen() and win:screen():id() ~= targetScreen:id() then
            moveWindowToScreen(win, targetScreen, obj.preserveGridCell)
        end
    end
end

-- Swap windows (swap current window with last focused)
function obj.actions.swapWindows()
    local currentWin = window.focusedWindow()
    if not currentWin then return end

    -- Try to use the previously focused window
    local otherWin = obj._previousFocusedWindow
    if not otherWin or not otherWin:frame() then
        -- Fallback: get the next window in order
        local orderedWindows = window.orderedWindows()
        for _, win in ipairs(orderedWindows) do
            if win:id() ~= currentWin:id() then
                otherWin = win
                break
            end
        end
    end

    if not otherWin then return end

    local currentFrame = currentWin:frame()
    local otherFrame = otherWin:frame()

    currentWin:setFrame(otherFrame)
    otherWin:setFrame(currentFrame)
end

-- Stage Manager integration
local function isStageManagerEnabled()
    -- Check Stage Manager status via defaults
    local output, status = hs.execute("defaults read com.apple.WindowManager GloballyEnabled 2>/dev/null")
    if status then
        return output:match("1") ~= nil
    end
    return false
end

local function setStageManager(enabled)
    local value = enabled and "1" or "0"
    hs.execute("defaults write com.apple.WindowManager GloballyEnabled -int " .. value)
    -- Restart WindowManager to apply changes
    hs.execute("killall -HUP WindowManager 2>/dev/null || true")
    obj._stageManagerEnabled = enabled
end

function obj.actions.toggleStageManager()
    local currentState = isStageManagerEnabled()
    setStageManager(not currentState)
end

-- Focus mode: center window + enable Stage Manager
function obj.actions.focusMode()
    local win = window.focusedWindow()
    if not win then return end

    if obj._stageManagerEnabled or isStageManagerEnabled() then
        -- Disable focus mode: turn off Stage Manager
        setStageManager(false)
    else
        -- Enable focus mode: center window and enable Stage Manager
        centerWindowAtSize(0.80)
        setStageManager(true)
    end
end


---------------------------------------------------------------------------
-- Spoon Methods
---------------------------------------------------------------------------

--- WinMan:bindHotkeys(mapping)
--- Method
--- Binds hotkeys for WinMan actions
---
--- Parameters:
---  * mapping - (optional) Table mapping action names to keys.
---              If nil, uses defaultBindings. Set a binding to `false` to disable it.
---              Keys use obj.modifiers as the modifier keys.
---
--- Returns:
---  * The WinMan object
function obj:bindHotkeys(mapping)
    -- Clear existing hotkeys
    for _, hk in ipairs(self._hotkeys) do
        hk:delete()
    end
    self._hotkeys = {}

    -- Merge with defaults
    local bindings = {}
    for action, key in pairs(self.defaultBindings) do
        bindings[action] = key
    end
    if mapping then
        for action, key in pairs(mapping) do
            bindings[action] = key
        end
    end

    -- Create hotkeys
    for action, key in pairs(bindings) do
        if key and self.actions[action] then
            -- Use human-readable description for cheat sheet discovery
            local description = self.actionDescriptions[action] or action
            local hk = hotkey.new(self.modifiers, key, description, self.actions[action])
            table.insert(self._hotkeys, hk)
        end
    end

    return self
end

--- WinMan:start()
--- Method
--- Starts WinMan - initializes grid settings, enables hotkeys, and starts screen watcher
---
--- Returns:
---  * The WinMan object
function obj:start()
    -- Parse and apply grid settings
    self._gridWidth, self._gridHeight = parseGridSize(self.gridSize)
    grid.setGrid(self.gridSize)
    grid.setMargins(self.gridMargins)

    -- Apply per-screen grid configurations
    for screenName, config in pairs(self.screenConfigs) do
        if screenName ~= "default" then
            for _, scr in ipairs(screen.allScreens()) do
                if scr:name() == screenName then
                    applyGridForScreen(scr)
                end
            end
        end
    end

    -- Bind hotkeys if not already done
    if #self._hotkeys == 0 then
        self:bindHotkeys()
    end

    -- Enable all hotkeys
    for _, hk in ipairs(self._hotkeys) do
        hk:enable()
    end

    -- Start screen watcher to handle connect/disconnect
    if not self._screenWatcher then
        self._screenWatcher = screen.watcher.new(function()
            -- Re-apply grid settings when screens change
            grid.setGrid(self.gridSize)
            grid.setMargins(self.gridMargins)

            -- Apply per-screen configurations
            for _, scr in ipairs(screen.allScreens()) do
                applyGridForScreen(scr)
            end
        end)
    end
    self._screenWatcher:start()

    -- Start window filter to track focus changes (for swap feature)
    if not self._windowFilter then
        self._windowFilter = hs.window.filter.new()
        self._windowFilter:subscribe(hs.window.filter.windowFocused, function(win)
            if win and self._lastFocusedWindow then
                if win:id() ~= self._lastFocusedWindow:id() then
                    self._previousFocusedWindow = self._lastFocusedWindow
                end
            end
            self._lastFocusedWindow = win
        end)
    end

    return self
end

--- WinMan:stop()
--- Method
--- Stops WinMan - disables all hotkeys, screen watcher, and window filter
---
--- Returns:
---  * The WinMan object
function obj:stop()
    for _, hk in ipairs(self._hotkeys) do
        hk:disable()
    end

    if self._screenWatcher then
        self._screenWatcher:stop()
    end

    if self._windowFilter then
        self._windowFilter:unsubscribeAll()
        self._windowFilter = nil
    end

    return self
end

--- WinMan:loadTest()
--- Method
--- Loads the test module. Run tests with spoon.WinMan:loadTest().runTests()
---
--- Returns:
---  * The test module
function obj:loadTest()
    local spoonPath = hs.spoons.scriptPath()
    return dofile(spoonPath .. "/test.lua")
end

return obj
