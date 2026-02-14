--- === SlowQ ===
---
--- Require holding Command+Q for a delay before quitting apps, preventing accidental closes.
--- Shows a visual countdown while holding. Replaces apps like CommandQ and SlowQuitApps.
---
--- Download: [https://github.com/dbmrq/Spoons/raw/master/Spoons/SlowQ.spoon.zip](https://github.com/dbmrq/Spoons/raw/master/Spoons/SlowQ.spoon.zip)

local obj = {}
obj.__index = obj

-- Metadata
obj.name = "SlowQ"
obj.version = "1.0"
obj.author = "Daniel Marques <danielbmarques@gmail.com>"
obj.license = "MIT"
obj.homepage = "https://github.com/dbmrq/Spoons"

--- SlowQ.delay
--- Variable
--- Number of seconds to hold Cmd+Q before quitting. Default: 4
obj.delay = 4

--- SlowQ.alertStyle
--- Variable
--- Style table for the countdown alert. See hs.alert for options.
obj.alertStyle = {
    strokeWidth = 0,
    strokeColor = { white = 0, alpha = 0 },
    fillColor = { white = 0, alpha = 0 },
    textColor = { red = 1, green = 0, blue = 0, alpha = 1 },
    textFont = "SF Pro Display Bold",
    textSize = 200,
    radius = 0,
    atScreenEdge = 0,
    fadeInDuration = 0.15,
    fadeOutDuration = 0.15,
    padding = -50,
}

-- Internal state
obj._countdown = 0
obj._killedIt = false
obj._timer = nil
obj._alert = nil
obj._hotkey = nil

--- SlowQ:_tick()
--- Method
--- Internal: Called every 0.5s while holding Cmd+Q to update countdown
function obj:_tick()
    hs.alert.closeSpecific(self._alert)
    self._alert = hs.alert(self._countdown - 1, self.alertStyle, nil, 1)
    self._countdown = self._countdown - 1
end

--- SlowQ:_pressQ()
--- Method
--- Internal: Called when Cmd+Q is pressed
function obj:_pressQ()
    self._countdown = self.delay
    self._killedIt = false
    self._timer = hs.timer.doEvery(0.5, function() self:_tick() end)
    self._timer:fire()
end

--- SlowQ:_holdQ()
--- Method
--- Internal: Called repeatedly while Cmd+Q is held
function obj:_holdQ()
    if self._countdown <= 0 and not self._killedIt then
        self._killedIt = true
        self._timer:stop()
        hs.alert.closeSpecific(self._alert)
        hs.application.frontmostApplication():kill()
    end
end

--- SlowQ:_releaseQ()
--- Method
--- Internal: Called when Cmd+Q is released
function obj:_releaseQ()
    self._killedIt = false
    if self._timer then
        self._timer:stop()
    end
    self._countdown = self.delay
    hs.alert.closeSpecific(self._alert)
end

--- SlowQ:start()
--- Method
--- Enables SlowQ, intercepting Cmd+Q
---
--- Returns:
---  * The SlowQ object
function obj:start()
    if self._hotkey then
        self._hotkey:enable()
    else
        self._hotkey = hs.hotkey.bind("cmd", "Q",
            function() self:_pressQ() end,
            function() self:_releaseQ() end,
            function() self:_holdQ() end)
    end
    return self
end

--- SlowQ:stop()
--- Method
--- Disables SlowQ, restoring normal Cmd+Q behavior
---
--- Returns:
---  * The SlowQ object
function obj:stop()
    if self._hotkey then
        self._hotkey:disable()
    end
    return self
end

--- SlowQ:loadTest()
--- Method
--- Loads the test module. Run tests with spoon.SlowQ:loadTest().runUnit()
---
--- Returns:
---  * The test module
function obj:loadTest()
    local spoonPath = hs.spoons.scriptPath()
    return dofile(spoonPath .. "/test.lua")
end

return obj

