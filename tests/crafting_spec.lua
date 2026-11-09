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
local config={Type=1, IsAvailable=function() return true end}
-- Isaac can return distinct Lua wrappers for the same underlying entity.
function GetPtrHash(p) return p.identity or p end
local function wrapper(p) return p and setmetatable({identity=p}, {__index=p}) end
Isaac={DebugString=function() end, GetPlayer=function(i) return wrapper(players[i+1]) end,
    GetItemConfig=function() return {GetCollectible=function() return config end} end}
function Game() return {GetNumPlayers=function() return #players end, GetFrameCount=function() return 0 end,
    GetSeeds=function() return {GetStartSeed=function() return 42 end} end} end
ItemType={ITEM_ACTIVE=2}; ActiveSlot={SLOT_PRIMARY=0}
CollectibleType={COLLECTIBLE_BAG_OF_CRAFTING=1}
local output=101
EntityPlayer={CalculateBagOfCraftingOutput=function() return output, 1 end}
local storage=include('scripts/storage'); storage:Init(mod); storage:OnGameStarted(false)
local crafting=include('scripts/crafting').new(storage)
local function player(index)
    local p={index=index, given={}}
    function p:GetPlayerIndex() return self.index end
    function p:Exists() return true end
    function p:IsDead() return false end
    function p:HasCollectible() return true end
    function p:CanAddCollectibleToInventory() return true end
    function p:GetActiveItem() return self.active or 0 end
    function p:AddCollectible(id) self.given[#self.given+1]=id; crafting:Observe(id,wrapper(self.identity or self)) end
    return p
end
local p, other=player(0), player(1); players={p,other}
local recipe={1,1,1,1,2,2,2,2}
local item={id=101,recipe=recipe}
local function execute(who, target, rev) return crafting:Execute(who,target or item,rev or storage:GetRevision(who)) end
storage:Add(p,recipe); storage:Add(other,recipe)
assert(execute(wrapper(p))); assert(storage:Count(p)==0 and #p.given==1 and storage:Count(other)==8)
assert(raw and savedPayload.players['0'] and #savedPayload.players['0'].ingredients==0)
storage:OnGameStarted(true); assert(storage:Count(p)==0 and storage:Count(other)==8, 'restore consumed stock')
storage:Add(p,{1,1,1,1,2,2,2,2,3,3,3,3,3,3,3,3})
assert(execute(p)); assert(storage:Count(p)==8 and storage:CountsByType(p)[3]==8)
local before=storage:GetRevision(p)
assert(not execute(p)); assert(storage:Count(p)==8 and storage:GetRevision(p)==before)
storage:Add(p,recipe); local stale=storage:GetRevision(p); storage:Add(p,{4})
assert(not execute(p,item,stale)); assert(storage:Count(p)==17)
output=102; assert(not execute(p)); assert(storage:Count(p)==17); output=101
assert(not crafting:Execute(nil,item,"x")); assert(storage:Count(p)==17)
config.IsAvailable=function() return false end
assert(not execute(p)); assert(storage:Count(p)==17)
config.IsAvailable=function() return true end
config.Type=ItemType.ITEM_ACTIVE; p.active=55; assert(not execute(p)); assert(storage:Count(p)==17)
p.active=0; config.Type=1
local oldSave=mod.SaveData; mod.SaveData=function() error('save failed') end
assert(not execute(p)); assert(storage:Count(p)==17 and #p.given==2, 'save failure must roll back before delivery')
mod.SaveData=oldSave
assert(execute(p)); assert(storage:Count(p)==9)
local second={id=102,recipe={3,3,3,3,3,3,3,3}}; output=102
assert(execute(p,second)); assert(storage:Count(p)==1 and #p.given==4 and p.given[4]==102)
assert(execute(other)==false, 'result mismatch for other player')
output=101; assert(execute(other)); assert(storage:Count(other)==0 and storage:Count(p)==1)
storage:OnGameStarted(true); assert(storage:Count(p)==1 and storage:Count(other)==0)
-- A recursive confirmation from another callback cannot grant another item.
storage:Add(other,recipe)
other.AddCollectible=function(self,id)
    assert(not execute(self)); self.given[#self.given+1]=id; crafting:Observe(id,self)
end
assert(execute(other)); assert(#other.given==2 and storage:Count(other)==0)
-- An exception after granting is ambiguous: do not refund it.
storage:Add(p,recipe); p.AddCollectible=function(self,id) self.given[#self.given+1]=id; error('after grant') end
assert(not execute(p)); assert(storage:Count(p)==1 and #p.given == 5)
print('PASS crafting: validation, consumption, save/continue, failures and players')
