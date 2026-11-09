function include(path) return dofile(path .. ".lua") end
Keyboard = {KEY_I=73, KEY_ENTER=257, KEY_ESCAPE=256, KEY_BACKSPACE=259, KEY_SPACE=32,
    KEY_TAB=258, KEY_P=80, KEY_F=70, KEY_R=82, KEY_Q=81, KEY_UP=265, KEY_DOWN=264, KEY_PAGE_UP=266, KEY_PAGE_DOWN=267}
ButtonAction = { ACTION_LEFT=0, ACTION_DROP=11, ACTION_MAP=13, ACTION_FULLSCREEN=16, ACTION_RESTART=18 }
InputHook = { GET_ACTION_VALUE=2 }
ModCallbacks = { MC_POST_UPDATE=1, MC_POST_HUD_RENDER=2, MC_POST_NEW_ROOM=3, MC_POST_ADD_COLLECTIBLE=4,
    MC_POST_ACHIEVEMENT_UNLOCK=5, MC_POST_GET_COLLECTIBLE=6, MC_POST_GAME_STARTED=7, MC_INPUT_ACTION=8,
    MC_POST_RENDER=9, MC_PRE_GAME_EXIT=10 }
local held, now, nativeCalls, paused = {}, 0, 0, false
Input = {IsButtonPressed=function(k) return held[k] or false end}
EntityPlayer = {CalculateBagOfCraftingOutput=function(recipe)
    nativeCalls=nativeCalls+1; assert(#recipe==8)
    local n=0; for _, ingredient in ipairs(recipe) do if ingredient==2 then n=n+1 end end
    return 123+n, 1
end}
local player = {ControllerIndex=0, GetPlayerIndex=function() return 0 end, ToPlayer=function(self) return self end}
function Game() return {GetNumPlayers=function() return 1 end, IsPaused=function() return paused end,
    GetSeeds=function() return {GetStartSeed=function() return 42 end} end} end
function KColor(...) return {...} end
function Vector(...) return {...} end
function Font() return {Load=function() end, DrawString=function() end, DrawStringScaledUTF8=function() end} end
function Sprite() return {Load=function() end, ReplaceSpritesheet=function() end, LoadGraphics=function() end,
    SetFrame=function() end, RenderLayer=function() end} end
Isaac = {GetPlayer=function() return player end, GetTime=function() return now end, GetScreenWidth=function() return 442 end,
    GetScreenHeight=function() return 286 end, DrawQuad=function() end,
    GetItemConfig=function() return {GetCollectible=function(_,id) return {Name="Test Item "..id,Quality=2,
        GfxFileName="gfx/test.png",IsAvailable=function() return true end} end} end}
local callbacks = {}
local mod = {AddCallback=function(_, id, fn) callbacks[id]=fn end}
local counts, revision = {[1]=8,[2]=8}, 1
local storage = {initialized=true, Count=function() return 16 end, GetRevision=function() return revision end,
    CountsByType=function() return counts end}
local ui=include("scripts/catalog_ui"); ui:Init(mod, storage)
local function tick(ms, update)
    now = now + (ms or 16)
    callbacks[ModCallbacks.MC_POST_RENDER]()
    if update ~= false then callbacks[ModCallbacks.MC_POST_UPDATE]() end
    callbacks[ModCallbacks.MC_POST_HUD_RENDER]()
end
local function press(k)
    held[k]=true; tick(); held[k]=nil; tick()
end
press(Keyboard.KEY_I)
assert(ui.open and ui.focus=="results")
while ui.catalog.state == "working" do tick() end
assert(ui.catalog.state == "complete" and nativeCalls == 9 and #ui.list == 9)
held[Keyboard.KEY_DOWN]=true; tick(16, false)
held[Keyboard.KEY_DOWN]=nil; tick(16, false)
assert(ui.selected == 2, "short press between game updates must move exactly one")
held[Keyboard.KEY_DOWN]=true; tick(); assert(ui.selected == 3)
tick(200); assert(ui.selected == 3, "repeat started too early")
tick(151); assert(ui.selected == 4, "held arrow must repeat after delay")
tick(100); assert(ui.selected == 5)
tick(2000); assert(ui.selected == 6, "stalled frame must not produce multiple steps")
held[Keyboard.KEY_DOWN]=nil; tick()
press(Keyboard.KEY_UP); assert(ui.selected == 5)
press(Keyboard.KEY_F); assert(ui.availability == "all", "F must not change the availability filter")
assert(callbacks[ModCallbacks.MC_INPUT_ACTION](nil,player,0,ButtonAction.ACTION_FULLSCREEN) == nil)
assert(callbacks[ModCallbacks.MC_INPUT_ACTION](nil,nil,0,ButtonAction.ACTION_FULLSCREEN) == nil)
press(Keyboard.KEY_R); assert(ui.availability == "available")
press(Keyboard.KEY_Q); assert(ui.quality == 0)
press(Keyboard.KEY_ENTER); assert(ui.focus == "search")
press(Keyboard.KEY_R); press(Keyboard.KEY_Q); press(Keyboard.KEY_F)
assert(ui.query == "rqf" and ui.availability == "available" and ui.quality == 0)
press(Keyboard.KEY_ESCAPE); assert(ui.focus == "results" and ui.query == "")
press(Keyboard.KEY_ENTER); press(Keyboard.KEY_I); press(Keyboard.KEY_ENTER)
assert(ui.focus == "results" and ui.query == "i", "Enter must confirm search and I must type in search")
press(Keyboard.KEY_TAB); assert(ui.focus == "inventory")
press(Keyboard.KEY_ENTER); assert(ui.focus == "inventory", "inventory must not enter invisible search")
press(Keyboard.KEY_TAB); assert(ui.focus == "results")
assert(callbacks[ModCallbacks.MC_INPUT_ACTION](nil,player,0,0) == false)
assert(callbacks[ModCallbacks.MC_INPUT_ACTION](nil,player,2,0) == 0)
local other = {ControllerIndex=1, ToPlayer=function(self) return self end}
assert(callbacks[ModCallbacks.MC_INPUT_ACTION](nil,other,0,0) == nil)
held[Keyboard.KEY_I]=true; tick(); assert(not ui.open and ui.focus == "closed")
for _=1,6 do tick() end
assert(not ui.open, "holding toggle must not reopen catalog")
held[Keyboard.KEY_I]=nil; tick()
assert(ui.query == "" and ui.availability == "all" and ui.quality == -1 and ui.selected == 1)
assert(callbacks[ModCallbacks.MC_INPUT_ACTION](nil,player,0,0) == nil)
local oldCalls=nativeCalls
press(Keyboard.KEY_I); assert(ui.open and nativeCalls == oldCalls, "reopen should reuse cache")
counts={}; for id=1,15 do counts[id]=8 end; revision=2; tick()
assert(ui.catalog.state == "working")
press(Keyboard.KEY_Q); assert(ui.quality == 0 and ui.catalog.state == "working", "input during search")
press(Keyboard.KEY_ESCAPE); assert(not ui.open)
paused=true; held[Keyboard.KEY_I]=true; tick(); assert(not ui.open)
paused=false; tick(); assert(not ui.open, "held key while paused must not open")
held[Keyboard.KEY_I]=nil; tick(); press(Keyboard.KEY_I); assert(ui.open)
callbacks[ModCallbacks.MC_PRE_GAME_EXIT](); assert(not ui.open)
assert(callbacks[ModCallbacks.MC_INPUT_ACTION](nil,player,0,0) == nil)
print("PASS UI input: edges, held repeat, focus, filters, search, pause, busy search and release")
