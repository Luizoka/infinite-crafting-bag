function include(path) return dofile(path .. ".lua") end
local savedPayload
local function clone(t)
    if type(t) ~= "table" then return t end
    local r = {}; for k,v in pairs(t) do r[k]=clone(v) end; return r
end
package.preload.json = function() return {
    encode=function(t) savedPayload=clone(t); return "payload" end,
    decode=function() return clone(savedPayload), 8 end,
} end
local raw
local mod={HasData=function() return raw ~= nil end, SaveData=function(_,s) raw=s end, LoadData=function() return raw end}
local players={}
local config={Type=1, AchievementID=-1, IsAvailable=function() return true end}
-- Isaac can return distinct Lua wrappers for the same underlying entity.
function GetPtrHash(p) return p.identity or p end
local function wrapper(p) return p and setmetatable({identity=p}, {__index=p}) end
local unlocked = true
Isaac={DebugString=function() end, GetPlayer=function(i) return wrapper(players[i+1]) end,
    GetPersistentGameData=function() return {Unlocked=function() return unlocked end} end,
    GetItemConfig=function() return {GetCollectible=function() return config end} end}
function Game() return {GetNumPlayers=function() return #players end, GetFrameCount=function() return 0 end,
    GetSeeds=function() return {GetStartSeed=function() return 42 end} end, IsPaused=function() return false end} end
ItemType={ITEM_ACTIVE=2}; ActiveSlot={SLOT_PRIMARY=0}
PlayerType={PLAYER_ISAAC_B=21, PLAYER_CAIN_B=23}
CollectibleType={COLLECTIBLE_BAG_OF_CRAFTING=1}
local output=101
EntityPlayer={CalculateBagOfCraftingOutput=function() return output, 1 end}
local storage=include('scripts/storage'); storage:Init(mod); storage:OnGameStarted(false)
local crafting=include('scripts/crafting').new(storage)
local function player(index)
    local p={index=index, given={}, ControllerIndex=0}
    function p:GetPlayerIndex() return self.index end
    function p:Exists() return true end
    function p:IsDead() return false end
    function p:HasCollectible() return true end
    function p:GetPlayerType() return self.playerType or PlayerType.PLAYER_CAIN_B end
    function p:CanAddCollectibleToInventory() return false end
    function p:GetActiveItem() return self.active or 0 end
    function p:GetBagOfCraftingContent() return self.bag or {} end
    function p:ToPlayer() return self end
    function p:AddCollectible(id) self.given[#self.given+1]=id; crafting:Observe(id,wrapper(self.identity or self)) end
    return p
end
local p, other=player(0), player(1); players={p,other}
local recipe={1,1,1,1,2,2,2,2}
local item={id=101,recipe=recipe}
storage:Add(p,recipe); storage:Add(other,recipe)
p.playerType=PlayerType.PLAYER_ISAAC_B
assert(crafting:Prepare(p,item))
crafting:Tick(false,false,0); crafting:Tick(false,true,1); crafting:Tick(false,true,1201)
assert(crafting.message=="Item nao cabe no inventario" and storage:Count(p)==8 and #p.given==0)
p.playerType=PlayerType.PLAYER_CAIN_B
config.AchievementID=7; unlocked=false
local valid, reason=crafting:Prepare(p,item)
assert(not valid and reason=="Item nao desbloqueado")
unlocked=true; config.IsAvailable=function() return false end
assert(crafting:Prepare(p,item), 'run restriction must not prevent preparation')
crafting:Tick(false,false,0); crafting:Tick(false,true,1); crafting:Tick(false,true,1201)
assert(storage:Count(p)==8 and #p.given==0 and crafting.message=="Item indisponivel nesta partida")
config.IsAvailable=function() return true end
config.Type=ItemType.ITEM_ACTIVE; p.active=55
assert(crafting:Prepare(p,item), 'occupied active slot must not prevent preparation')
crafting:Tick(false,false,1300); crafting:Tick(false,true,1301); crafting:Tick(false,true,2501)
assert(storage:Count(p)==8 and #p.given==0 and crafting.message=="Esvazie o espaco de item ativo")
config.Type=1; p.active=0
assert(crafting:Prepare(wrapper(p),item)); assert(storage:Count(p)==8 and #p.given==0)
assert(crafting:ShouldBlock(wrapper(p),true))
crafting:Tick(false,false,0); crafting:Tick(false,true,1); crafting:Tick(false,true,500)
assert(storage:Count(p)==8 and #p.given==0 and crafting:Progress(500)>0)
crafting:Tick(false,false,501); assert(crafting:Progress(600)==0)
crafting:Tick(false,true,600); crafting:Tick(false,true,1800)
assert(storage:Count(p)==0 and #p.given==1 and storage:Count(other)==8)
for t=1801,4000,100 do crafting:Tick(false,true,t) end
assert(#p.given==1 and crafting:ShouldBlock(wrapper(p),true))
crafting:Tick(false,false,4001); assert(not crafting:ShouldBlock(wrapper(p),true))
storage:OnGameStarted(true); assert(storage:Count(p)==0 and storage:Count(other)==8)
storage:Add(p,recipe); assert(crafting:Prepare(p,item)); output=102
crafting:Tick(false,false,5000); crafting:Tick(false,true,5001); crafting:Tick(false,true,6201)
assert(storage:Count(p)==8 and #p.given==1); output=101
assert(crafting:Prepare(p,item)); p.bag={1}
crafting:Tick(false,false,7000); crafting:Tick(false,true,7001); crafting:Tick(false,true,8201)
assert(storage:Count(p)==8 and #p.given==1); p.bag={}
assert(crafting:Prepare(p,item)); local oldSave=mod.SaveData; mod.SaveData=function() error('failed') end
crafting:Tick(false,false,9000); crafting:Tick(false,true,9001); crafting:Tick(false,true,10201)
assert(storage:Count(p)==8 and #p.given==1); mod.SaveData=oldSave
assert(crafting:Prepare(p,item)); crafting:Tick(true,false,11000); crafting:Tick(true,true,12000)
crafting:Tick(false,true,14000); assert(#p.given==1, 'must release Q after closing')
print('PASS crafting: hold, cancel, release, stale recipe, save failure and multiplayer')
