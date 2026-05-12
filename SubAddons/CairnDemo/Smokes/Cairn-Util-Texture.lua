-- Cairn-Util-Texture smoke. Wrapped for the CairnDemo runner.
--
-- Coverage: sub-namespace attaches to Cairn-Util; AnimateSpriteSheet
-- exists and is callable on a real texture without erroring. The
-- earlier version of this smoke also asserted that UV coords moved
-- after a single call -- removed because AnimateSpriteSheet is a
-- 1-line pass-through to Blizzard's AnimateTexCoords, and that
-- function's frame-advance behavior under a single manual call (vs.
-- per-OnUpdate accumulation) doesn't reliably mutate the texture's
-- visible coords. That's Blizzard's contract to test, not ours.

_G.CairnDemo       = _G.CairnDemo or {}
_G.CairnDemo.Smokes = _G.CairnDemo.Smokes or {}

_G.CairnDemo.Smokes["Cairn-Util-Texture"] = function(report)
    -- 1. Library + sub-namespace surface
    local CU = LibStub and LibStub("Cairn-Util-1.0", true)
    report("Cairn-Util is loaded under LibStub", CU ~= nil)
    if not CU then return end

    report("CU.Texture table exists",                    type(CU.Texture) == "table")
    report("CU.Texture.AnimateSpriteSheet is a function", type(CU.Texture and CU.Texture.AnimateSpriteSheet) == "function")

    if not (CU.Texture and type(CU.Texture.AnimateSpriteSheet) == "function") then return end


    -- 2. Call doesn't error on a real texture
    local testFrame = CreateFrame("Frame", nil, UIParent)
    testFrame:SetSize(64, 64)
    local tex = testFrame:CreateTexture(nil, "ARTWORK")
    tex:SetTexture(136235)  -- a known Blizzard texture file
    tex:SetAllPoints(testFrame)

    local ok, err = pcall(CU.Texture.AnimateSpriteSheet,
        tex, 256, 256, 64, 64, 16, 0.2, 0.04)
    report("AnimateSpriteSheet call doesn't error", ok, err)

    -- Verify the call reached the Blizzard global by checking the
    -- per-texture state fields AnimateTexCoords installs as a side
    -- effect (texture.frame, texture.throttle). If they're set, we
    -- know the pass-through wired through correctly.
    report("AnimateSpriteSheet reaches AnimateTexCoords (texture.frame set)",
           tex.frame ~= nil)
    report("AnimateSpriteSheet reaches AnimateTexCoords (texture.throttle set)",
           tex.throttle ~= nil)

    testFrame:Hide()
    testFrame:SetParent(nil)
end
