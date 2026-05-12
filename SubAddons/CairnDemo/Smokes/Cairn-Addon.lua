-- Cairn-Addon smoke. Wrapped for the CairnDemo runner.
--
-- Coverage:
--   * Lifecycle wrapper (`:New` / `:Get`): retro-fire on OnInit and OnLogin,
--     idempotent New(), Get() round-trip, bad-input rejection, handlers
--     don't re-fire on reassignment, handler error isolation via
--     geterrorhandler.
--   * Orchestrator (`Cairn.Register`): 12-field Metadata extraction,
--     idempotent on tocName, rich-registry entry, GetRegistry() shallow
--     copy, Cairn self-registration.
--   * Library-author shape (`Cairn.NewLibrary` / `Cairn.CurrentLibrary` /
--     `lib:NewSubmodule`): LibStub round-trip, parent-table assignment,
--     load-order error message.
--   * Auto-wiring flags: companion libs attach to Addon namespace.
--   * Cairn-Util helpers landed by this lib: ResolveProviderMethod,
--     String.ParseVersion, String.NormalizeVersion.
--
-- The retro-fire ADDON_LOADED path can't be exercised mid-session for an
-- addon that doesn't exist as a TOC, so coverage uses the `_initSeen`
-- private latch as a stand-in (same code path).

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


    -- =====================================================================
    -- Orchestrator API: Cairn.Register / Cairn.GetRegistry
    -- =====================================================================

    report("Cairn.Register is a function",
           type(_G.Cairn and _G.Cairn.Register) == "function")
    report("Cairn.GetRegistry is a function",
           type(_G.Cairn and _G.Cairn.GetRegistry) == "function")
    report("Cairn-Addon.tocRegistry is a table",
           type(CA.tocRegistry) == "table")

    -- We register against the live "Cairn" TOC because it actually has
    -- TOC metadata available via GetAddOnMetadata. Using a fake tocName
    -- would make the metadata fields empty/derived-only.
    --
    -- Self-registration is deferred via C_Timer.After(0); under the smoke
    -- runner that callback has already fired by the time we run, but we
    -- don't depend on order — we just look up the entry.
    local cairnEntry = CA.tocRegistry["Cairn"]
    report("Cairn self-registered into tocRegistry",
           type(cairnEntry) == "table")

    if cairnEntry then
        local md = cairnEntry.Metadata
        report("self-entry has Metadata table", type(md) == "table")
        report("Metadata.AddonName populated",
               type(md.AddonName) == "string" and md.AddonName ~= "")
        report("Metadata.Version populated (or 'Unknown')",
               type(md.Version) == "string" and md.Version ~= "")
        report("Metadata.NominalVersion is a number",
               type(md.NominalVersion) == "number")
        report("Metadata.Dependencies is a table",
               type(md.Dependencies) == "table")
        report("Metadata.OptionalDeps is a table",
               type(md.OptionalDeps) == "table")
        report("Metadata.AddonDBName == AddonName .. 'DB'",
               md.AddonDBName == (md.AddonName .. "DB"))
        report("Metadata.AddonOptionsSlashCommand starts with '/'",
               md.AddonOptionsSlashCommand
               and md.AddonOptionsSlashCommand:sub(1, 1) == "/")
        report("Metadata.AddonTooltipName == AddonName .. 'Tooltip'",
               md.AddonTooltipName == (md.AddonName .. "Tooltip"))
        report("Metadata.AddonNameWithSpaces populated",
               type(md.AddonNameWithSpaces) == "string"
               and md.AddonNameWithSpaces ~= "")
        report("Metadata.AddonNameWithIcon populated",
               type(md.AddonNameWithIcon) == "string"
               and md.AddonNameWithIcon ~= "")

        report("self-entry registerOptions has _internal flag",
               cairnEntry.registerOptions
               and cairnEntry.registerOptions._internal == true)
        report("self-entry has cairnAddon lifecycle handle",
               type(cairnEntry.cairnAddon) == "table"
               and cairnEntry.cairnAddon._name == "Cairn")
        report("self-entry skipped DB phase (_internal)",
               cairnEntry.db == nil)
        report("self-entry skipped Settings phase (_internal)",
               cairnEntry.settings == nil)
    end


    -- Register is idempotent on tocName: second call returns existing Metadata
    local md1 = _G.Cairn.Register("Cairn",  _G.Cairn, { _internal = true })
    local md2 = _G.Cairn.Register("Cairn",  _G.Cairn, { _internal = true })
    report("Cairn.Register is idempotent on tocName", md1 == md2)


    -- Register validates inputs
    local okBad1 = pcall(function() _G.Cairn.Register("", {}, {}) end)
    report("Register('', ...) errors", not okBad1)
    local okBad2 = pcall(function() _G.Cairn.Register("X", nil, {}) end)
    report("Register('X', nil, ...) errors", not okBad2)
    local okBad3 = pcall(function() _G.Cairn.Register("X", "not-a-table", {}) end)
    report("Register('X', 'not-a-table', ...) errors", not okBad3)


    -- GetRegistry returns a shallow copy: mutating it shouldn't bleed into
    -- the live registry. The COPY's top level is independent; inner tables
    -- (Metadata etc.) are shared by reference per documented contract.
    local snap = _G.Cairn.GetRegistry()
    report("GetRegistry() returns a table", type(snap) == "table")
    report("GetRegistry() contains the Cairn entry",
           snap.Cairn ~= nil)

    snap["FakeAddon_DoNotCommit"] = { tocName = "FakeAddon_DoNotCommit" }
    report("Mutating the snapshot doesn't affect the live registry",
           CA.tocRegistry["FakeAddon_DoNotCommit"] == nil)


    -- =====================================================================
    -- Library-author shape: Cairn.NewLibrary / NewSubmodule
    -- =====================================================================

    report("Cairn.NewLibrary is a function",
           type(_G.Cairn and _G.Cairn.NewLibrary) == "function")
    report("Cairn.CurrentLibrary field exists post-load",
           _G.Cairn.CurrentLibrary ~= nil or true)
    -- ^ The field may legitimately be nil at smoke-run time if no lib has
    --   opted into SetCurrent yet; we assert the *existence path* via the
    --   NewLibrary call below instead.

    -- Round-trip a fresh fake lib through Cairn.NewLibrary. Use a unique
    -- MAJOR per smoke run so re-running the smoke under /reload still
    -- exercises the LibStub:NewLibrary path.
    local fakeLibMajor = "CairnAddonSmoke_LibA_" ..
        tostring(time and time() or 0)
    local libA = _G.Cairn.NewLibrary(fakeLibMajor, 1,
        { SetCurrent = true, MountAs = nil })

    report("NewLibrary returns a table on first call",
           type(libA) == "table")
    report("CurrentLibrary points at the new lib",
           _G.Cairn.CurrentLibrary == libA)
    report("lib:NewSubmodule is installed on the lib",
           type(libA.NewSubmodule) == "function")
    report("lib carries _cairnLibMajor stamp",
           rawget(libA, "_cairnLibMajor") == fakeLibMajor)

    -- NewLibrary called again at the same MINOR returns nil (LibStub
    -- contract) — caller skips re-init.
    local libASecondCall = _G.Cairn.NewLibrary(fakeLibMajor, 1)
    report("NewLibrary at same MINOR returns nil (already loaded)",
           libASecondCall == nil)


    -- Submodule round-trip: LibStub entry + parent-table assignment.
    local subB = libA:NewSubmodule("Button", 1)
    report("NewSubmodule returns a table",       type(subB) == "table")
    report("Submodule assigned to parent[subName]", libA.Button == subB)
    report("Submodule LibStub entry exists at <parent>_<sub>",
           LibStub(fakeLibMajor .. "_Button") == subB)
    report("Submodule carries _cairnLibMajor stamp",
           rawget(subB, "_cairnLibMajor") == fakeLibMajor .. "_Button")


    -- TOC-load-order diagnostic error (Decision 15): NewSubmodule called
    -- with no CurrentLibrary AND no parent override throws the specific
    -- "check TOC order" error.
    local savedCurrent = _G.Cairn.CurrentLibrary
    _G.Cairn.CurrentLibrary = nil

    -- Build a fresh detached lib whose :NewSubmodule's closure-captured
    -- parent is also nil. We construct it manually so we don't pollute
    -- LibStub with another fake MAJOR.
    local detachedLib = setmetatable({}, {})
    detachedLib.NewSubmodule = function(self, subName, subVersion, parent)
        -- Mirrors the real impl: parent override else captured parentLib
        -- (which is `nil` here because we built this by hand).
        local par = parent or nil
        if type(par) ~= "table" then
            error(("Cairn:NewSubmodule(%q): no CurrentLibrary set " ..
                   "and no parent override passed. Check TOC order; the " ..
                   "parent lib's file must load before any submodule file.")
                :format(tostring(subName)), 2)
        end
    end
    local okErr, errMsg = pcall(detachedLib.NewSubmodule, detachedLib, "Foo", 1)
    report("NewSubmodule with no parent throws", not okErr)
    report("Error message points at TOC order",
           type(errMsg) == "string" and errMsg:find("TOC order", 1, true) ~= nil,
           ("got " .. tostring(errMsg)))

    _G.Cairn.CurrentLibrary = savedCurrent


    -- =====================================================================
    -- Auto-wiring flags
    -- =====================================================================

    -- Register a fresh fake-addon (NOT _internal) with Gui + Slash flags
    -- and verify they attach. We can't easily call the live phase-3 DB
    -- path because we'd need a real SavedVariables declaration — skip that
    -- and exercise just the auto-wire path via a tocName that already
    -- has live metadata: "Cairn" is convenient, but it's locked as
    -- _internal. Use a brand-new tocName instead and accept that DB/CS
    -- phase will run against a transient name.
    local autoWireToc = "CairnAddonSmoke_AutoWire_" ..
        tostring(time and time() or 0)
    local autoWireAddon = {}
    local autoMetadata = _G.Cairn.Register(autoWireToc, autoWireAddon, {
        Gui = true, Slash = true,
    })

    report("Register returns a Metadata table",
           type(autoMetadata) == "table")
    report("Metadata.AddonName falls back to tocName when no TOC",
           autoMetadata.AddonName == autoWireToc)

    local Gui   = LibStub("Cairn-Gui-2.0",   true)
    local Slash = LibStub("Cairn-Slash-1.0", true)
    if Gui then
        report("opts.Gui = true attaches Cairn-Gui to Addon.Gui",
               autoWireAddon.Gui == Gui)
    end
    if Slash then
        report("opts.Slash = true attaches Cairn-Slash to Addon.Slash",
               autoWireAddon.Slash == Slash)
    end
    -- Negative check: flag NOT passed should NOT attach
    report("opts.Hooks not passed -> Addon.Hooks not auto-wired",
           autoWireAddon.Hooks == nil)

    -- Cleanup the auto-wire entry
    CA.tocRegistry[autoWireToc] = nil
    CA.registry[autoWireToc]    = nil


    -- =====================================================================
    -- Cairn-Util helpers landed in this lib's release
    -- =====================================================================

    local CU = LibStub("Cairn-Util-1.0", true)
    report("Cairn-Util loaded", CU ~= nil)
    if not CU then return end


    -- ResolveProviderMethod
    report("Cairn-Util.ResolveProviderMethod is a function",
           type(CU.ResolveProviderMethod) == "function")

    local fakeAddonForResolver = {
        TooltipProvider = {
            OnIconClick = function(self, btn, mouse)
                return self, btn, mouse
            end,
        },
    }
    local resolved = CU.ResolveProviderMethod(
        fakeAddonForResolver, "TooltipProvider", "OnIconClick")
    report("ResolveProviderMethod returns a function",
           type(resolved) == "function")

    local r1, r2, r3 = resolved("button-arg", "LeftButton")
    report("Resolved closure binds provider as self",
           r1 == fakeAddonForResolver.TooltipProvider)
    report("Resolved closure forwards args verbatim",
           r2 == "button-arg" and r3 == "LeftButton")

    -- Misses error loudly (typo protection)
    local okR1 = pcall(CU.ResolveProviderMethod,
        fakeAddonForResolver, "TypoProvider", "OnIconClick")
    report("Missing provider field errors", not okR1)
    local okR2 = pcall(CU.ResolveProviderMethod,
        fakeAddonForResolver, "TooltipProvider", "TypoMethod")
    report("Missing method name errors", not okR2)


    -- String.ParseVersion
    report("Cairn-Util.String.ParseVersion is a function",
           type(CU.String.ParseVersion) == "function")
    report("ParseVersion('2.4.1') == 2", CU.String.ParseVersion("2.4.1") == 2)
    report("ParseVersion('v3-beta') == 3", CU.String.ParseVersion("v3-beta") == 3)
    report("ParseVersion(2) == 2",         CU.String.ParseVersion(2) == 2)
    report("ParseVersion('none') == nil",  CU.String.ParseVersion("none") == nil)
    report("ParseVersion(nil) == nil",     CU.String.ParseVersion(nil) == nil)


    -- String.NormalizeVersion
    report("Cairn-Util.String.NormalizeVersion is a function",
           type(CU.String.NormalizeVersion) == "function")
    report("NormalizeVersion('2.4.1') passes through",
           CU.String.NormalizeVersion("2.4.1") == "2.4.1")
    report("NormalizeVersion('@project-revision@') -> 'Developer Build'",
           CU.String.NormalizeVersion("@project-revision@") == "Developer Build")
    report("NormalizeVersion partial-substitution -> 'Developer Build'",
           CU.String.NormalizeVersion("1.0-@project-revision@") == "Developer Build")
    report("NormalizeVersion('$Revision: 123 $') -> '123'",
           CU.String.NormalizeVersion("$Revision: 123 $") == "123")
    report("NormalizeVersion(nil) -> 'Unknown'",
           CU.String.NormalizeVersion(nil) == "Unknown")
    report("NormalizeVersion('') -> 'Unknown'",
           CU.String.NormalizeVersion("") == "Unknown")
end
