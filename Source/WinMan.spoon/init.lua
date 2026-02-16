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

--- WinMan.mode
--- Variable
--- Window management mode: "simple" (direct bindings) or "zellij" (modal bindings).
--- In "zellij" mode, uses modal system matching Zellij's patterns:
---   Super+p = Focus mode, Super+n = Resize mode, Super+h = Move mode, Super+t = Spaces mode
--- In "simple" mode, uses direct bindings (HJKL resize, arrows move).
--- Default: "simple" (backwards compatible)
obj.mode = "simple"

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

    -- Undo/redo
    undo = "Z",
    redo = "Y",
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
    undo = "Undo",
    redo = "Redo",
}

-- Internal state
obj._hotkeys = {}
obj._screenWatcher = nil
obj._windowFilter = nil  -- For tracking window focus
obj._lastFocusedWindow = nil  -- For swap windows feature
obj._previousFocusedWindow = nil  -- The window before the last focused
obj._stageManagerEnabled = false  -- Track Stage Manager state

-- Modal state (for zellij mode)
obj._modals = {}  -- Stores hs.hotkey.modal objects
obj._currentModal = nil  -- Currently active modal name

-- Undo/redo state: tracks window frame history per window ID
-- Structure: { [windowId] = { frames = {frame1, frame2, ...}, index = currentIndex } }
obj._frameHistory = {}
obj._maxHistorySize = 50  -- Maximum number of frames to remember per window

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

-- Move window to screen using relative positioning (percentage-based)
local function moveWindowRelative(win, currentScreen, targetScreen)
    local currentFrame = currentScreen:frame()
    local targetFrame = targetScreen:frame()
    local winFrame = win:frame()

    local relX = (winFrame.x - currentFrame.x) / currentFrame.w
    local relY = (winFrame.y - currentFrame.y) / currentFrame.h
    local relW = winFrame.w / currentFrame.w
    local relH = winFrame.h / currentFrame.h

    win:setFrame({
        x = targetFrame.x + (relX * targetFrame.w),
        y = targetFrame.y + (relY * targetFrame.h),
        w = relW * targetFrame.w,
        h = relH * targetFrame.h,
    })
end

local function moveWindowToScreen(win, targetScreen, preserveGridCell)
    if not win or not targetScreen then return end

    local currentScreen = win:screen()
    if not currentScreen then return end
    if currentScreen:id() == targetScreen:id() then return end

    if preserveGridCell then
        -- Preserve grid cell position (e.g., left-half stays left-half)
        local cell = grid.get(win, currentScreen)
        if cell then
            applyGridForScreen(targetScreen)
            grid.set(win, cell, targetScreen)
        else
            moveWindowRelative(win, currentScreen, targetScreen)
        end
    else
        moveWindowRelative(win, currentScreen, targetScreen)
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

---------------------------------------------------------------------------
-- Undo/Redo Helpers
---------------------------------------------------------------------------

-- Record current frame for a window (call before making changes)
local function recordFrameForUndo(win)
    if not win then return end
    local id = win:id()
    if not id then return end

    local frame = win:frame()
    if not frame then return end

    -- Initialize history for this window if needed
    if not obj._frameHistory[id] then
        obj._frameHistory[id] = { frames = {}, index = 0 }
    end

    local history = obj._frameHistory[id]

    -- If we're not at the end of history (user did undo then new action),
    -- truncate forward history
    if history.index < #history.frames then
        for i = #history.frames, history.index + 1, -1 do
            table.remove(history.frames, i)
        end
    end

    -- Check if the current frame is different from the last recorded frame
    local lastFrame = history.frames[#history.frames]
    if lastFrame and
       lastFrame.x == frame.x and lastFrame.y == frame.y and
       lastFrame.w == frame.w and lastFrame.h == frame.h then
        return  -- No change, don't record
    end

    -- Add current frame to history
    table.insert(history.frames, { x = frame.x, y = frame.y, w = frame.w, h = frame.h })
    history.index = #history.frames

    -- Trim history if too large
    while #history.frames > obj._maxHistorySize do
        table.remove(history.frames, 1)
        history.index = history.index - 1
    end
end

-- Undo action
function obj.actions.undo()
    local win = window.focusedWindow()
    if not win then return end
    local id = win:id()
    if not id then return end

    local history = obj._frameHistory[id]
    if not history or history.index <= 1 then
        hs.alert.show("Nothing to undo", 0.5)
        return
    end

    -- Record current position if at the end (so we can redo back to it)
    if history.index == #history.frames then
        local frame = win:frame()
        local lastFrame = history.frames[#history.frames]
        if not lastFrame or
           lastFrame.x ~= frame.x or lastFrame.y ~= frame.y or
           lastFrame.w ~= frame.w or lastFrame.h ~= frame.h then
            table.insert(history.frames, { x = frame.x, y = frame.y, w = frame.w, h = frame.h })
            history.index = #history.frames
        end
    end

    -- Move back in history
    history.index = history.index - 1
    local targetFrame = history.frames[history.index]
    if targetFrame then
        win:setFrame(targetFrame)
    end
end

-- Redo action
function obj.actions.redo()
    local win = window.focusedWindow()
    if not win then return end
    local id = win:id()
    if not id then return end

    local history = obj._frameHistory[id]
    if not history or history.index >= #history.frames then
        hs.alert.show("Nothing to redo", 0.5)
        return
    end

    -- Move forward in history
    history.index = history.index + 1
    local targetFrame = history.frames[history.index]
    if targetFrame then
        win:setFrame(targetFrame)
    end
end

---------------------------------------------------------------------------

-- Resize state tracking
local resizeState = { vertical = true, horizontal = true }

-- Unified resize helper that handles all four directions
-- @param direction: "up", "down", "left", "right"
local function resizeInDirection(direction)
    local win = window.focusedWindow()
    if not win then return end
    local scr = win:screen()
    if not scr then return end

    recordFrameForUndo(win)  -- Record for undo before changes
    local gridW, gridH = applyGridForScreen(scr)
    local cell = grid.get(win)
    if not cell then return end

    -- Direction-specific configuration
    local config = {
        up = {
            isVertical = true,
            atEdge = function() return cell.y == 0 end,
            snapFn = snapToTop,
            growFn = grid.resizeWindowTaller,
            shrinkFn = grid.resizeWindowShorter,
            sizeKey = "h",
            maxSize = gridH,
        },
        down = {
            isVertical = true,
            atEdge = function() return cell.y + cell.h >= gridH end,
            snapFn = snapToBottom,
            growFn = grid.resizeWindowTaller,
            shrinkFn = grid.resizeWindowShorter,
            sizeKey = "h",
            maxSize = gridH,
        },
        left = {
            isVertical = false,
            atEdge = function() return cell.x == 0 end,
            snapFn = snapToLeft,
            growFn = grid.resizeWindowWider,
            shrinkFn = grid.resizeWindowThinner,
            sizeKey = "w",
            maxSize = gridW,
        },
        right = {
            isVertical = false,
            atEdge = function() return cell.x + cell.w >= gridW end,
            snapFn = snapToRight,
            growFn = grid.resizeWindowWider,
            shrinkFn = grid.resizeWindowThinner,
            sizeKey = "w",
            maxSize = gridW,
        },
    }

    local cfg = config[direction]
    local stateKey = cfg.isVertical and "vertical" or "horizontal"
    local currentSize = cell[cfg.sizeKey]

    -- If not at edge, snap to edge first
    if not cfg.atEdge() then
        cfg.snapFn(win, cell, scr)
        cascadeAllOverlapping(obj.cascadeSpacing, obj.slowResizeApps)
        return
    end

    -- Toggle grow/shrink based on current size
    if currentSize <= 2 then
        resizeState[stateKey] = true
    elseif currentSize >= cfg.maxSize then
        resizeState[stateKey] = false
    end

    -- Resize (double step for larger sizes)
    local growing = resizeState[stateKey]
    local resizeFn = growing and cfg.growFn or cfg.shrinkFn
    local threshold = growing and 4 or 6

    resizeFn()
    if currentSize >= threshold then
        resizeFn()
    end

    -- Re-snap after resize
    cell = grid.get(win)
    cfg.snapFn(win, cell, scr)
    cascadeAllOverlapping(obj.cascadeSpacing, obj.slowResizeApps)
end

function obj.actions.resizeUp() resizeInDirection("up") end
function obj.actions.resizeDown() resizeInDirection("down") end
function obj.actions.resizeLeft() resizeInDirection("left") end
function obj.actions.resizeRight() resizeInDirection("right") end

-- Unified move helper that handles all four directions
-- @param direction: "up", "down", "left", "right"
-- @param multiStep: if true, move multiple grid steps based on window size
local function moveInDirection(direction, multiStep)
    local win = window.focusedWindow()
    if not win then return end
    local scr = win:screen()
    if not scr then return end

    recordFrameForUndo(win)  -- Record for undo before changes
    local gridW, gridH = applyGridForScreen(scr)
    local cell = grid.get(win)
    if not cell then return end

    -- Direction-specific configuration
    local config = {
        up    = { pushFn = grid.pushWindowUp,    atEdge = cell.y == 0,               sizeKey = "h" },
        down  = { pushFn = grid.pushWindowDown,  atEdge = cell.y + cell.h >= gridH,  sizeKey = "h" },
        left  = { pushFn = grid.pushWindowLeft,  atEdge = cell.x == 0,               sizeKey = "w" },
        right = { pushFn = grid.pushWindowRight, atEdge = cell.x + cell.w >= gridW,  sizeKey = "w" },
    }

    local cfg = config[direction]
    if cfg.atEdge then return end

    local steps = 1
    if multiStep then
        steps = (cell[cfg.sizeKey] == 3) and 3 or 2
    end

    for _ = 1, steps do cfg.pushFn() end
    cascadeAllOverlapping(obj.cascadeSpacing, obj.slowResizeApps)
end

-- Move actions (push window in grid increments with multi-step)
function obj.actions.moveUp() moveInDirection("up", true) end
function obj.actions.moveDown() moveInDirection("down", true) end
function obj.actions.moveLeft() moveInDirection("left", true) end
function obj.actions.moveRight() moveInDirection("right", true) end

-- Layout actions
function obj.actions.maximize()
    local win = window.focusedWindow()
    if not win then return end
    recordFrameForUndo(win)
    grid.maximizeWindow(win)
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

-- Helper to cascade a list of windows
local function cascadeWindowList(windows)
    if obj.cascadeSpacing == 0 or not windows or #windows == 0 then return end

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
        win:setFrame({
            x = xMargin + offset,
            y = scr.y + yMargin + offset,
            w = scr.w - (2 * xMargin) - (nOfSpaces * spacing),
            h = scr.h - (2 * yMargin) - (nOfSpaces * spacing),
        })
    end
end

function obj.actions.cascadeAll()
    cascadeWindowList(window.orderedWindows())
end

function obj.actions.cascadeApp()
    local focusedWin = window.focusedWindow()
    if not focusedWin then return end

    local focusedApp = focusedWin:application()
    if not focusedApp then return end

    local appWindows = {}
    for _, win in ipairs(window.orderedWindows() or {}) do
        local app = win:application()
        if app and app == focusedApp then
            table.insert(appWindows, win)
        end
    end
    cascadeWindowList(appWindows)
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

    recordFrameForUndo(win)
    local currentIndex = getScreenIndex(win:screen(), screens)
    local nextIndex = (currentIndex % #screens) + 1
    moveWindowToScreen(win, screens[nextIndex], obj.preserveGridCell)
end

function obj.actions.moveToPrevScreen()
    local win = window.focusedWindow()
    if not win then return end

    local screens = getSortedScreens()
    if #screens < 2 then return end

    recordFrameForUndo(win)
    local currentIndex = getScreenIndex(win:screen(), screens)
    local prevIndex = ((currentIndex - 2) % #screens) + 1
    moveWindowToScreen(win, screens[prevIndex], obj.preserveGridCell)
end

-- Helper to move window to a specific screen number
local function moveToScreenNumber(screenNum)
    local win = window.focusedWindow()
    if not win then return end
    local screens = getSortedScreens()
    if #screens >= screenNum then
        recordFrameForUndo(win)
        moveWindowToScreen(win, screens[screenNum], obj.preserveGridCell)
    end
end

function obj.actions.moveToScreen1() moveToScreenNumber(1) end
function obj.actions.moveToScreen2() moveToScreenNumber(2) end
function obj.actions.moveToScreen3() moveToScreenNumber(3) end

---------------------------------------------------------------------------
-- Positioning Actions
---------------------------------------------------------------------------

-- Center window at various sizes
local function centerWindowAtSize(sizeFraction)
    local win = window.focusedWindow()
    if not win then return end
    local scr = win:screen()
    if not scr then return end

    recordFrameForUndo(win)  -- Record for undo before changes
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

-- Quick positioning helper - sets window to a specific grid cell
local function setWindowGridPosition(x, y, w, h)
    local win = window.focusedWindow()
    if not win then return end
    local scr = win:screen()
    if not scr then return end
    recordFrameForUndo(win)  -- Record for undo before changes
    applyGridForScreen(scr)
    grid.set(win, geometry(x, y, w, h), scr)
end

-- Quick thirds positioning (grid is 6x6, so 2 cells = 1/3, 4 cells = 2/3)
function obj.actions.leftThird() setWindowGridPosition(0, 0, 2, 6) end
function obj.actions.centerThird() setWindowGridPosition(2, 0, 2, 6) end
function obj.actions.rightThird() setWindowGridPosition(4, 0, 2, 6) end
function obj.actions.leftTwoThirds() setWindowGridPosition(0, 0, 4, 6) end
function obj.actions.rightTwoThirds() setWindowGridPosition(2, 0, 4, 6) end

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
-- Zellij Mode: Focus Direction Actions
---------------------------------------------------------------------------

-- Focus window in a direction
function obj.actions.focusWest()
    local win = window.focusedWindow()
    if win then win:focusWindowWest(nil, true, true) end
end

function obj.actions.focusSouth()
    local win = window.focusedWindow()
    if win then win:focusWindowSouth(nil, true, true) end
end

function obj.actions.focusNorth()
    local win = window.focusedWindow()
    if win then win:focusWindowNorth(nil, true, true) end
end

function obj.actions.focusEast()
    local win = window.focusedWindow()
    if win then win:focusWindowEast(nil, true, true) end
end

-- Cycle through cascaded/overlapping windows (z-order)
function obj.actions.focusNextInStack()
    local orderedWindows = window.orderedWindows()
    if #orderedWindows < 2 then return end

    -- Focus the next window in z-order (the one behind current)
    local nextWin = orderedWindows[2]
    if nextWin then nextWin:focus() end
end

function obj.actions.focusPrevInStack()
    local orderedWindows = window.orderedWindows()
    if #orderedWindows < 2 then return end

    -- Focus the last window in z-order (bring to front)
    local lastWin = orderedWindows[#orderedWindows]
    if lastWin then lastWin:focus() end
end

-- Close window
function obj.actions.closeWindow()
    local win = window.focusedWindow()
    if win then win:close() end
end

---------------------------------------------------------------------------
-- Zellij Mode: Pure Resize Actions (no snapping/moving)
---------------------------------------------------------------------------

-- Generic grid action helper (applies grid settings, calls action, cascades)
local function withGridAction(actionFn)
    local win = window.focusedWindow()
    if not win then return end
    local scr = win:screen()
    if not scr then return end
    recordFrameForUndo(win)  -- Record for undo before changes
    applyGridForScreen(scr)
    actionFn()
    cascadeAllOverlapping(obj.cascadeSpacing, obj.slowResizeApps)
end

-- Pure resize actions
function obj.actions.pureResizeShrinkWidth() withGridAction(grid.resizeWindowThinner) end
function obj.actions.pureResizeGrowWidth() withGridAction(grid.resizeWindowWider) end
function obj.actions.pureResizeShrinkHeight() withGridAction(grid.resizeWindowShorter) end
function obj.actions.pureResizeGrowHeight() withGridAction(grid.resizeWindowTaller) end

---------------------------------------------------------------------------
-- Zellij Mode: Pure Move Actions (no resizing)
---------------------------------------------------------------------------

-- Pure move actions (single step, using existing moveInDirection helper)
function obj.actions.pureMoveLeft() moveInDirection("left", false) end
function obj.actions.pureMoveRight() moveInDirection("right", false) end
function obj.actions.pureMoveUp() moveInDirection("up", false) end
function obj.actions.pureMoveDown() moveInDirection("down", false) end

---------------------------------------------------------------------------
-- Zellij Mode: Spaces Actions
---------------------------------------------------------------------------

function obj.actions.spaceLeft()
    if hs.spaces and hs.spaces.gotoSpace then
        local currentSpace = hs.spaces.focusedSpace()
        local allSpaces = hs.spaces.spacesForScreen()
        if allSpaces and currentSpace then
            for i, space in ipairs(allSpaces) do
                if space == currentSpace and i > 1 then
                    hs.spaces.gotoSpace(allSpaces[i - 1])
                    return
                end
            end
        end
    end
    -- Fallback: simulate Ctrl+Left arrow
    hs.eventtap.keyStroke({"ctrl"}, "left", 0)
end

function obj.actions.spaceRight()
    if hs.spaces and hs.spaces.gotoSpace then
        local currentSpace = hs.spaces.focusedSpace()
        local allSpaces = hs.spaces.spacesForScreen()
        if allSpaces and currentSpace then
            for i, space in ipairs(allSpaces) do
                if space == currentSpace and i < #allSpaces then
                    hs.spaces.gotoSpace(allSpaces[i + 1])
                    return
                end
            end
        end
    end
    -- Fallback: simulate Ctrl+Right arrow
    hs.eventtap.keyStroke({"ctrl"}, "right", 0)
end

function obj.actions.spaceNew()
    -- Open Mission Control and click the + button to create a new Space
    -- This requires accessibility permissions
    hs.osascript.applescript([[
        tell application "System Events"
            -- Open Mission Control (Ctrl+Up or F3 depending on settings)
            key code 126 using control down
            delay 0.5
            -- Click the "+" button to add a new space
            -- The button is in the spaces bar at the top
            try
                click button 1 of group 2 of group 1 of group 1 of process "Dock"
            end try
        end tell
    ]])
end

---------------------------------------------------------------------------
-- Spoon Methods
---------------------------------------------------------------------------

---------------------------------------------------------------------------
-- Modal System (for zellij mode)
---------------------------------------------------------------------------

-- Helper to create a modal with common setup
local function createModal(spoonObj, name, hints)
    local modal = hotkey.modal.new()

    function modal:entered()
        spoonObj._currentModal = name
        hs.alert.show(name .. " Mode", 0.5)
        if spoon.CheatSheet and spoon.CheatSheet.showModeHints then
            spoon.CheatSheet:showModeHints(name, hints)
        end
    end

    function modal:exited()
        spoonObj._currentModal = nil
        if spoon.CheatSheet and spoon.CheatSheet.hideModeHints then
            spoon.CheatSheet:hideModeHints()
        end
    end

    modal:bind({}, "escape", function() modal:exit() end)
    modal:bind({}, "return", function() modal:exit() end)

    return modal
end

-- Set up modal bindings for zellij mode
function obj:_setupModals()
    for _, modal in pairs(self._modals) do
        modal:exit()
    end
    self._modals = {}

    local mods = self.modifiers

    -- Focus mode (Super+p): hjkl focus, f maximize, x close
    local focusHints = {
        {"h", "Focus left"}, {"j", "Focus down / next in stack"},
        {"k", "Focus up / prev in stack"}, {"l", "Focus right"},
        {"f", "Maximize"}, {"x", "Close window"},
        {"Esc/Enter", "Exit mode"},
    }
    local focusModal = createModal(self, "Focus", focusHints)
    focusModal:bind({}, "h", function() self.actions.focusWest() end)
    focusModal:bind({}, "j", function() self.actions.focusNextInStack() end)
    focusModal:bind({}, "k", function() self.actions.focusPrevInStack() end)
    focusModal:bind({}, "l", function() self.actions.focusEast() end)
    focusModal:bind({}, "f", function() self.actions.maximize(); focusModal:exit() end)
    focusModal:bind({}, "x", function() self.actions.closeWindow(); focusModal:exit() end)
    self._modals.focus = focusModal

    local focusEntry = hotkey.new(mods, "p", "Focus Mode", function() focusModal:enter() end)
    table.insert(self._hotkeys, focusEntry)

    -- Resize mode (Super+n): hjkl pure resize
    local resizeHints = {
        {"h", "Shrink width"}, {"l", "Grow width"},
        {"j", "Shrink height"}, {"k", "Grow height"},
        {"Esc/Enter", "Exit mode"},
    }
    local resizeModal = createModal(self, "Resize", resizeHints)
    resizeModal:bind({}, "h", function() self.actions.pureResizeShrinkWidth() end)
    resizeModal:bind({}, "l", function() self.actions.pureResizeGrowWidth() end)
    resizeModal:bind({}, "j", function() self.actions.pureResizeShrinkHeight() end)
    resizeModal:bind({}, "k", function() self.actions.pureResizeGrowHeight() end)
    self._modals.resize = resizeModal

    local resizeEntry = hotkey.new(mods, "n", "Resize Mode", function() resizeModal:enter() end)
    table.insert(self._hotkeys, resizeEntry)

    -- Move mode (Super+h): hjkl move, 1/2/3 screen, c/a cascade
    local moveHints = {
        {"h/j/k/l", "Move in grid"},
        {"1/2/3", "Move to screen"},
        {"c", "Cascade all"}, {"a", "Cascade app"},
        {"Esc/Enter", "Exit mode"},
    }
    local moveModal = createModal(self, "Move", moveHints)
    moveModal:bind({}, "h", function() self.actions.pureMoveLeft() end)
    moveModal:bind({}, "l", function() self.actions.pureMoveRight() end)
    moveModal:bind({}, "j", function() self.actions.pureMoveDown() end)
    moveModal:bind({}, "k", function() self.actions.pureMoveUp() end)
    moveModal:bind({}, "1", function() self.actions.moveToScreen1(); moveModal:exit() end)
    moveModal:bind({}, "2", function() self.actions.moveToScreen2(); moveModal:exit() end)
    moveModal:bind({}, "3", function() self.actions.moveToScreen3(); moveModal:exit() end)
    moveModal:bind({}, "c", function() self.actions.cascadeAll(); moveModal:exit() end)
    moveModal:bind({}, "a", function() self.actions.cascadeApp(); moveModal:exit() end)
    self._modals.move = moveModal

    local moveEntry = hotkey.new(mods, "h", "Move Mode", function() moveModal:enter() end)
    table.insert(self._hotkeys, moveEntry)

    -- Spaces mode (Super+t): h/l switch, n new
    local spacesHints = {
        {"h", "Previous Space"}, {"l", "Next Space"},
        {"n", "New Space"},
        {"Esc/Enter", "Exit mode"},
    }
    local spacesModal = createModal(self, "Spaces", spacesHints)
    spacesModal:bind({}, "h", function() self.actions.spaceLeft() end)
    spacesModal:bind({}, "l", function() self.actions.spaceRight() end)
    spacesModal:bind({}, "n", function() self.actions.spaceNew(); spacesModal:exit() end)
    self._modals.spaces = spacesModal

    local spacesEntry = hotkey.new(mods, "t", "Spaces Mode", function() spacesModal:enter() end)
    table.insert(self._hotkeys, spacesEntry)
end

--- WinMan:bindHotkeys(mapping)
--- Method
--- Binds hotkeys for WinMan actions
---
--- Parameters:
---  * mapping - (optional) Table mapping action names to keys.
---              If nil, uses defaultBindings. Set a binding to `false` to disable it.
---              Keys use obj.modifiers as the modifier keys.
---              Only used in "simple" mode; "zellij" mode uses fixed modal bindings.
---
--- Returns:
---  * The WinMan object
function obj:bindHotkeys(mapping)
    -- Clear existing hotkeys
    for _, hk in ipairs(self._hotkeys) do
        hk:delete()
    end
    self._hotkeys = {}

    -- Clear existing modals
    for _, modal in pairs(self._modals) do
        modal:exit()
        -- Note: hs.hotkey.modal doesn't have delete(), just exit and clear reference
    end
    self._modals = {}

    -- Setup based on mode
    if self.mode == "zellij" then
        self:_setupModals()
    else
        -- Simple mode: use direct bindings (original behavior)
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
    -- Apply grid settings
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
--- Stops WinMan - disables all hotkeys, modals, screen watcher, and window filter
---
--- Returns:
---  * The WinMan object
function obj:stop()
    for _, hk in ipairs(self._hotkeys) do
        hk:disable()
    end

    -- Exit and clean up modals
    for _, modal in pairs(self._modals) do
        modal:exit()
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
