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
    function p:AddCollectible() error("unexpected collectible delivery") end
    return p
end
local p, other=player(0), player(1); players={p,other}
local recipe={1,1,1,1,2,2,2,2}
local item={id=101,recipe=recipe}
assert(crafting.Execute == nil and crafting.Observe == nil, "direct crafting must be unavailable")
storage:Add(p,recipe); storage:Add(other,recipe)
local revision=storage:GetRevision(p)
assert(crafting:Validate(wrapper(p),item,revision))
assert(storage:Count(p)==8 and storage:Count(other)==8 and #p.given==0)
output=102; assert(not crafting:Validate(p,item,revision)); output=101
storage:Add(p,{3}); assert(not crafting:Validate(p,item,revision))
assert(storage:Count(p)==9 and #p.given==0)
print('PASS recipe validation: no delivery, no consumption, players isolated')
