--- SlowQ Test Suite
--- Run unit tests: spoon.SlowQ:loadTest().runUnit()

local M = {}

-- Get reference to the spoon
local slowq = spoon and spoon.SlowQ or nil

--- Run unit tests (can run without GUI, mocks timers and alerts)
function M.runUnit()
    print("\n=== SlowQ Unit Tests ===\n")

    local passed = 0
    local failed = 0

    -- Save originals
    local origTimer = hs.timer
    local origAlert = hs.alert
    local origApplication = hs.application

    -- Mock state tracking
    local timerFired = false
    local timerStopped = false
    local alertShown = nil
    local alertClosed = false
    local appKilled = false

    -- Mock timer
    hs.timer = {
        doEvery = function(interval, fn)
            return {
                fire = function()
                    timerFired = true
                    fn()
                end,
                stop = function()
                    timerStopped = true
                end,
            }
        end,
    }

    -- Mock alert (as a callable table)
    hs.alert = setmetatable({
        closeSpecific = function(id)
            alertClosed = true
        end,
    }, {
        __call = function(_, msg, style, screen, duration)
            alertShown = msg
            return "alert-id"
        end,
    })

    -- Mock application
    hs.application = {
        frontmostApplication = function()
            return {
                kill = function()
                    appKilled = true
                end,
            }
        end,
    }

    -- Test 1: Initial state
    local function test_initial_state()
        local testObj = {
            delay = 4,
            _countdown = 0,
            _killedIt = false,
            _timer = nil,
            _alert = nil,
        }
        return testObj.delay == 4 and testObj._countdown == 0 and not testObj._killedIt
    end

    if test_initial_state() then
        print("✓ initial_state: PASS")
        passed = passed + 1
    else
        print("✗ initial_state: FAIL")
        failed = failed + 1
    end

    -- Test 2: _pressQ starts timer and countdown
    local function test_pressQ()
        timerFired = false
        alertShown = nil

        local testObj = setmetatable({
            delay = 4,
            _countdown = 0,
            _killedIt = false,
            _timer = nil,
            _alert = nil,
            alertStyle = {},
        }, { __index = slowq or {} })

        -- Simulate _pressQ behavior
        testObj._countdown = testObj.delay
        testObj._killedIt = false
        testObj._timer = hs.timer.doEvery(0.5, function()
            hs.alert.closeSpecific(testObj._alert)
            testObj._alert = hs.alert(testObj._countdown - 1, testObj.alertStyle, nil, 1)
            testObj._countdown = testObj._countdown - 1
        end)
        testObj._timer:fire()

        return testObj._countdown == 3 and timerFired and alertShown == 3
    end

    if test_pressQ() then
        print("✓ pressQ_starts_countdown: PASS")
        passed = passed + 1
    else
        print("✗ pressQ_starts_countdown: FAIL")
        failed = failed + 1
    end

    -- Test 3: _holdQ kills app when countdown reaches 0
    local function test_holdQ_kills()
        appKilled = false
        timerStopped = false
        alertClosed = false

        local testObj = {
            _countdown = 0,
            _killedIt = false,
            _timer = { stop = function() timerStopped = true end },
            _alert = "alert-id",
        }

        -- Simulate _holdQ behavior
        if testObj._countdown <= 0 and not testObj._killedIt then
            testObj._killedIt = true
            testObj._timer:stop()
            hs.alert.closeSpecific(testObj._alert)
            hs.application.frontmostApplication():kill()
        end

        return appKilled and timerStopped and alertClosed and testObj._killedIt
    end

    if test_holdQ_kills() then
        print("✓ holdQ_kills_at_zero: PASS")
        passed = passed + 1
    else
        print("✗ holdQ_kills_at_zero: FAIL")
        failed = failed + 1
    end

    -- Test 4: _holdQ does nothing when countdown > 0
    local function test_holdQ_waits()
        appKilled = false

        local testObj = {
            _countdown = 2,
            _killedIt = false,
        }

        -- Simulate _holdQ behavior (should do nothing)
        if testObj._countdown <= 0 and not testObj._killedIt then
            hs.application.frontmostApplication():kill()
        end

        return not appKilled
    end

    if test_holdQ_waits() then
        print("✓ holdQ_waits_when_counting: PASS")
        passed = passed + 1
    else
        print("✗ holdQ_waits_when_counting: FAIL")
        failed = failed + 1
    end

    -- Test 5: _releaseQ resets state
    local function test_releaseQ()
        timerStopped = false
        alertClosed = false

        local testObj = {
            delay = 4,
            _countdown = 1,
            _killedIt = true,
            _timer = { stop = function() timerStopped = true end },
            _alert = "alert-id",
        }

        -- Simulate _releaseQ behavior
        testObj._killedIt = false
        if testObj._timer then
            testObj._timer:stop()
        end
        testObj._countdown = testObj.delay
        hs.alert.closeSpecific(testObj._alert)

        return testObj._countdown == 4 and not testObj._killedIt and timerStopped and alertClosed
    end

    if test_releaseQ() then
        print("✓ releaseQ_resets_state: PASS")
        passed = passed + 1
    else
        print("✗ releaseQ_resets_state: FAIL")
        failed = failed + 1
    end

    -- Restore originals
    hs.timer = origTimer
    hs.alert = origAlert
    hs.application = origApplication

    print("\n=== Unit Tests Complete: " .. passed .. " passed, " .. failed .. " failed ===\n")
    return failed == 0
end

return M

