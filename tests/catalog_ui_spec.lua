function include(path) return dofile(path .. ".lua") end
local keyboardKeys = {"I","ENTER","ESCAPE","BACKSPACE","SPACE","TAB","P","F","Q","UP","DOWN","PAGE_UP","PAGE_DOWN"}
Keyboard = {}; for i, name in ipairs(keyboardKeys) do Keyboard["KEY_" .. name] = 300 + i end
ButtonAction = { ACTION_LEFT=0, ACTION_DROP=11, ACTION_MAP=13, ACTION_RESTART=18 }
InputHook = { GET_ACTION_VALUE=2 }
ModCallbacks = { MC_POST_UPDATE=1, MC_POST_HUD_RENDER=2, MC_POST_NEW_ROOM=3, MC_POST_ADD_COLLECTIBLE=4,
    MC_POST_ACHIEVEMENT_UNLOCK=5, MC_POST_GET_COLLECTIBLE=6, MC_POST_GAME_STARTED=7, MC_INPUT_ACTION=8 }
local key, nativeCalls = nil, 0
Input = { IsButtonTriggered = function(k) return k == key end }
EntityPlayer = { CalculateBagOfCraftingOutput = function(recipe) nativeCalls=nativeCalls+1; assert(#recipe==8); return 123, 1 end }
local player = {ControllerIndex=0, GetPlayerIndex=function() return 0 end, ToPlayer=function(self) return self end}
function Game() return {GetNumPlayers=function() return 1 end, GetSeeds=function() return {GetStartSeed=function() return 42 end} end} end
function KColor(...) return {...} end
function Vector(...) return {...} end
function Font() return {Load=function() end, DrawString=function() end, DrawStringScaledUTF8=function() end} end
function Sprite() return {Load=function() end, ReplaceSpritesheet=function() end, LoadGraphics=function() end,
    SetFrame=function() end, RenderLayer=function() end} end
Isaac = {GetPlayer=function() return player end, GetScreenWidth=function() return 442 end,
    GetScreenHeight=function() return 286 end, DrawQuad=function() end,
    GetItemConfig=function() return {GetCollectible=function(_,id) return {Name="Test Item",Quality=2,GfxFileName="gfx/test.png",IsAvailable=function() return true end} end} end}
local callbacks = {}
local mod = {AddCallback=function(_, id, fn) callbacks[id]=fn end}
local counts, revision = {[1]=8}, 1
local storage = { initialized=true, Count=function() return 8 end, GetRevision=function() return revision end,
    CountsByType=function() return counts end }
local ui=include("scripts/catalog_ui"); ui:Init(mod, storage)
key=Keyboard.KEY_I; callbacks[ModCallbacks.MC_POST_UPDATE](); key=nil
assert(ui.open)
while ui.catalog.state == "working" do callbacks[ModCallbacks.MC_POST_UPDATE]() end
assert(ui.catalog.state == "complete" and nativeCalls == 1)
callbacks[ModCallbacks.MC_POST_HUD_RENDER]()
assert(#ui.list == 1 and ui.list[1].id == 123)
key=Keyboard.KEY_ENTER; callbacks[ModCallbacks.MC_POST_UPDATE](); key=nil
assert(ui.editing)
key=string.byte("T"); callbacks[ModCallbacks.MC_POST_UPDATE](); key=nil
assert(ui.query == "t")
key=Keyboard.KEY_ENTER; callbacks[ModCallbacks.MC_POST_UPDATE](); key=nil
assert(not ui.editing)
callbacks[ModCallbacks.MC_POST_HUD_RENDER](); assert(#ui.list == 1)
key=Keyboard.KEY_Q; callbacks[ModCallbacks.MC_POST_UPDATE](); key=nil
assert(ui.quality == 0)
callbacks[ModCallbacks.MC_POST_HUD_RENDER](); assert(#ui.list == 0)
ui.quality = -1
assert(callbacks[ModCallbacks.MC_INPUT_ACTION](nil,player,0,0) == false)
assert(callbacks[ModCallbacks.MC_INPUT_ACTION](nil,player,2,0) == 0)
key=Keyboard.KEY_I; callbacks[ModCallbacks.MC_POST_UPDATE](); key=nil
assert(not ui.open and callbacks[ModCallbacks.MC_INPUT_ACTION](nil,player,0,0) == nil)
key=Keyboard.KEY_I; callbacks[ModCallbacks.MC_POST_UPDATE](); key=nil
assert(nativeCalls == 1, "reopening should reuse cached results")
counts, revision = {[1]=8,[2]=1}, 2
callbacks[ModCallbacks.MC_POST_UPDATE]()
while ui.catalog.state == "working" do callbacks[ModCallbacks.MC_POST_UPDATE]() end
assert(nativeCalls == 3, "new inventory must invalidate results")
callbacks[ModCallbacks.MC_POST_NEW_ROOM]()
callbacks[ModCallbacks.MC_POST_UPDATE]()
assert(ui.catalog.evaluated <= 2 and ui.catalog.key ~= nil)
print("PASS UI integration: open/close, result, input capture, cache and invalidation")
