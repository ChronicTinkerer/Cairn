-- Cairn-Addon smoke. Wrapped for the CairnDemo runner.
--
-- Coverage: load, basic API surface, retro-fire on OnInit and OnLogin,
-- idempotent New(), Get() round-trip, bad-input rejection, handlers
-- don't re-fire on reassignment, handler error isolation via
-- geterrorhandler.

_G.CairnDemo       = _G.CairnDemo or {}
_G.CairnDemo.Smokes = _G.CairnDemo.Smokes or {}

_G.CairnDemo.Smokes["Cairn-Addon"] = function(report)
    -- 1. Library loaded with public API
    local CA = LibStub and LibStub("Cairn-Addon-1.0", true)
    report("Cairn-Addon is loaded under LibStub", CA ~= nil)
    if not CA then return end

    report("Cairn-Addon:New exists",     type(CA.New) == "function")
    report("Cairn-Addon:Get exists",     type(CA.Get) == "function")
    report("Cairn-Addon.registry is a table", type(CA.registry) == "table")
    report("Cairn-Addon._loginFired is a bool", type(CA._loginFired) == "boolean")
    report("_loginFired is TRUE post-login (we're running this after PLAYER_LOGIN)",
           CA._loginFired == true,
           ("got " .. tostring(CA._loginFired)))


    -- 2. New() returns a table and registers it
    local testName = "CairnAddonSmoke_" .. tostring(time and time() or 0)
    local fake = CA:New(testName)
    report("New(name) returns a table",                  type(fake) == "table")
    report("registry[name] == returned instance",        CA.registry[testName] == fake)
    report("instance carries the supplied _name",        fake._name == testName)
    report("New(same name) is idempotent",               CA:New(testName) == fake)
    report("Get(name) returns the registered instance",  CA:Get(testName) == fake)
    report("Get(unknown) returns nil",                   CA:Get("DefinitelyNotRegisteredX") == nil)


    -- 3. Bad input rejected
    local ok1 = pcall(function() return CA:New("") end)
    report("New('') errors", not ok1)
    local ok2 = pcall(function() return CA:New(nil) end)
    report("New(nil) errors", not ok2)
    local ok3 = pcall(function() return CA:New(42) end)
    report("New(42) errors",  not ok3)


    -- 4. OnInit retro-fires when assigned after ADDON_LOADED was already seen
    rawset(fake, "_initSeen", true)

    local initCalled, initSelf = false, nil
    function fake:OnInit()
        initCalled, initSelf = true, self
    end
    report("OnInit retro-fires after _initSeen=true",   initCalled)
    report("OnInit handler received the addon as self", initSelf == fake)
    report("_initFired flipped to true after dispatch", rawget(fake, "_initFired") == true)


    -- 5. OnLogin retro-fires when assigned after PLAYER_LOGIN already happened
    local loginCalled, loginSelf = false, nil
    function fake:OnLogin()
        loginCalled, loginSelf = true, self
    end
    report("OnLogin retro-fires after PLAYER_LOGIN",    loginCalled)
    report("OnLogin handler received the addon as self", loginSelf == fake)
    report("_loginFired flipped to true after dispatch", rawget(fake, "_loginFired") == true)


    -- 6. Handlers do NOT re-fire on reassignment (each fires at most once)
    local initCallCount = 0
    function fake:OnInit() initCallCount = initCallCount + 1 end
    function fake:OnInit() initCallCount = initCallCount + 1 end
    report("Reassigning OnInit does NOT re-fire", initCallCount == 0)


    -- 7. Handler errors are isolated (one bad handler doesn't break dispatch)
    local secondName  = testName .. "_err"
    local fake2       = CA:New(secondName)
    rawset(fake2, "_initSeen", true)

    local originalGetErrorHandler = geterrorhandler
    local errorHandlerCalled, capturedError = false, nil
    geterrorhandler = function()
        return function(err)
            errorHandlerCalled, capturedError = true, err
        end
    end

    function fake2:OnInit()
        error("intentional smoke-test error")
    end

    geterrorhandler = originalGetErrorHandler

    report("Handler error didn't crash the lib",     rawget(fake2, "_initFired") == true)
    report("geterrorhandler() was invoked on throw", errorHandlerCalled == true)
    report("Captured error mentions the lib + key",
           type(capturedError) == "string"
           and capturedError:find("Cairn%-Addon", 1, false)
           and capturedError:find(":OnInit",      1, false),
           ("got " .. tostring(capturedError)))


    -- Cleanup
    CA.registry[testName]   = nil
    CA.registry[secondName] = nil
end
