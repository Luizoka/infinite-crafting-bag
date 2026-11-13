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
local qHeld=false
Keyboard={KEY_Q=81}
Input={IsButtonPressed=function(key) return key==Keyboard.KEY_Q and qHeld end}
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
ItemType={ITEM_ACTIVE=2}; ActiveSlot={SLOT_PRIMARY=0, SLOT_SECONDARY=1}
PlayerType={PLAYER_ISAAC_B=21, PLAYER_CAIN_B=23}
CollectibleType={COLLECTIBLE_BAG_OF_CRAFTING=1, COLLECTIBLE_SCHOOLBAG=2}
local output=101
EntityPlayer={CalculateBagOfCraftingOutput=function() return output, 1 end}
local storage=include('scripts/storage'); storage:Init(mod); storage:OnGameStarted(false)
local crafting=include('scripts/crafting').new(storage)
local function player(index)
    local p={index=index, given={}, ControllerIndex=0}
    function p:GetPlayerIndex() return self.index end
    function p:Exists() return true end
    function p:IsDead() return false end
    function p:HasCollectible(id) return id == CollectibleType.COLLECTIBLE_BAG_OF_CRAFTING or self.schoolbag == true end
    function p:GetPlayerType() return self.playerType or PlayerType.PLAYER_CAIN_B end
    function p:CanAddCollectibleToInventory() return false end
    function p:GetActiveItem(slot) if slot == ActiveSlot.SLOT_SECONDARY then return self.secondary or 0 end; return self.active or 0 end
    function p:CanOverrideActiveItem() return (self.identity or self).active == nil or (self.identity or self).active == 0 end
    function p:DropCollectible(id)
        local owner = self.identity or self
        if owner.dropFails then return nil end
        assert(owner.active==id)
        owner.dropped={id=id, charge=owner.charge}
        owner.active, owner.charge = owner.secondary or 0, owner.secondaryCharge or 0
        owner.secondary, owner.secondaryCharge = 0, 0
        return owner.dropped
    end
    function p:GetBagOfCraftingContent() return self.bag or {} end
    function p:GetBagOfCraftingOutput() return (self.identity or self).nativeOutput or 0 end
    function p:SetBagOfCraftingOutput(id) local owner = self.identity or self; owner.nativeOutput=id; owner.writes=(owner.writes or 0)+1 end
    function p:SetBagOfCraftingContent(content)
        local owner = self.identity or self
        owner.bag=content; owner.nativeOutput=0; owner.writes=(owner.writes or 0)+1
    end
    function p:ToPlayer() return self end
    function p:AddCollectible(id)
        if config.Type == ItemType.ITEM_ACTIVE then
            if self.schoolbag and (self.secondary or 0) == 0 and (self.active or 0) ~= 0 then
                self.secondary, self.secondaryCharge = self.active, self.charge
            end
            self.active, self.charge = id, 0
        end
        self.given[#self.given+1]=id; crafting:Observe(id,wrapper(self.identity or self))
    end
    function p:AnimateCollectible(id, animation)
        local owner = self.identity or self
        owner.animated, owner.animation = id, animation
    end
    function p:GetSprite() return {GetAnimation=function() return "PickupWalkDown" end} end
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
config.Type=1; p.active=0
assert(crafting:Prepare(wrapper(p),item)); assert(storage:Count(p)==8 and #p.given==0)
assert(p.nativeOutput==101)
local writes=p.writes; crafting:SyncPreview(); assert(p.writes==writes, "unchanged output must not be rewritten")
p.nativeOutput=0; crafting:SyncPreview(); assert(p.nativeOutput==101, "restore output after native recalculation")
assert(crafting:ShouldBlock(wrapper(p),true))
crafting:Tick(false,false,0); crafting:Tick(false,true,1); crafting:Tick(false,true,500)
assert(p.animated==CollectibleType.COLLECTIBLE_BAG_OF_CRAFTING and p.animation=='LiftItem')
assert(storage:Count(p)==8 and #p.given==0 and crafting:Progress(500)>0)
crafting:Tick(false,false,501); assert(crafting:Progress(600)==0 and p.animation=='HideItem')
crafting:Tick(false,true,600); crafting:Tick(false,true,1800)
assert(storage:Count(p)==0 and #p.given==1 and storage:Count(other)==8 and p.nativeOutput==0)
assert(p.animated==item.id, 'confirmed crafting animates the selected collectible')
assert(not crafting.prepared and crafting:ShouldPreventExternalDelivery(item.id,wrapper(p),true))
assert(not crafting:ShouldPreventExternalDelivery(item.id,wrapper(other),true))
for t=1801,4000,100 do crafting:Tick(false,true,t) end
assert(#p.given==1 and crafting:ShouldBlock(wrapper(p),true))
crafting:Tick(false,false,4001); assert(not crafting:ShouldBlock(wrapper(p),true))
assert(not crafting:ShouldPreventExternalDelivery(item.id,wrapper(p),false))
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
output=102
local second={id=102,recipe=recipe}
assert(crafting:Prepare(p,second) and p.nativeOutput==102, 'replacing a selection updates native output')
assert(storage:ConsumeRecipe(p, recipe))
crafting:SyncPreview()
assert(not crafting.prepared and p.nativeOutput==0, 'insufficient stock clears the selection and preview')
storage:Add(p,recipe)
assert(crafting:Prepare(p,second))
crafting:Tick(false,false,15000); crafting:Tick(false,true,15001)
assert(crafting:Progress(15500)>0)
crafting:Cancel(true)
assert(not crafting.prepared and not crafting.started and not crafting.armed and p.nativeOutput==0)
assert(storage:Count(p)==8 and crafting:ShouldBlock(wrapper(p),true))
crafting:Tick(false,true,18000); assert(#p.given==1 and storage:Count(p)==8)
crafting:Tick(false,false,18001); assert(not crafting:ShouldBlock(wrapper(p),true))
assert(crafting:Prepare(p,second), 'can prepare again immediately')
crafting:BeginPreviewRender(wrapper(other)); assert(not crafting.renderMirror)
crafting:BeginPreviewRender(wrapper(p))
assert(crafting.renderMirror and #p.bag==8 and p.nativeOutput==102 and storage:Count(p)==8)
for i=1,8 do assert(p.bag[i]==recipe[i]) end
crafting:EndPreviewRender(wrapper(other)); assert(#p.bag==8)
crafting:EndPreviewRender(wrapper(p))
assert(#p.bag==0 and p.nativeOutput==102 and storage:Count(p)==8)
crafting:BeginPreviewRender(wrapper(p))
crafting.message='old'; crafting.messageUntil=20000; crafting:Cancel(false)
assert(not crafting.message and not crafting.messageUntil and #p.bag==0 and p.nativeOutput==0)
assert(crafting:Prepare(p,second))
crafting:Tick(false,false,21000); crafting:Tick(false,true,21001)
qHeld=true; crafting:Observe(second.id,wrapper(p)); qHeld=false
assert(not crafting.prepared and p.nativeOutput==0, 'external delivery cancels the pending grant')
crafting:Tick(false,true,23000)
assert(#p.given==1 and storage:Count(p)==8, 'external delivery must not trigger a second grant or debit')
config.Type=ItemType.ITEM_ACTIVE; other.active=55; other.charge=3
assert(crafting:Prepare(other,second))
crafting:Tick(false,false,24000); crafting:Tick(false,true,24001); crafting:Tick(false,true,25201)
assert(other.dropped and other.dropped.id==55 and other.dropped.charge==3)
assert(#other.given==1 and other.given[1]==102 and storage:Count(other)==0)
storage:Add(other,recipe); other.active=56; other.dropFails=true
assert(crafting:Prepare(other,second))
crafting:Tick(false,false,26000); crafting:Tick(false,true,26001); crafting:Tick(false,true,27201)
assert(other.active==56 and #other.given==1 and storage:Count(other)==8, 'failed drop refunds ingredients and does not deliver')
storage:OnGameStarted(true); assert(storage:Count(other)==8, 'failed drop refund must be persisted')
other.dropFails=false; other.schoolbag=true; other.active=57; other.charge=5; other.secondary=0; other.dropped=nil
assert(crafting:Execute(other,second))
assert(other.active==102 and other.secondary==57 and other.secondaryCharge==5 and not other.dropped)
assert(storage:Count(other)==0 and #other.given==2, 'free schoolbag slot delivers once')
storage:Add(other,recipe); other.active=58; other.charge=4; other.secondary=59; other.secondaryCharge=6
other.dropped=nil
assert(crafting:Execute(other,second))
assert(other.active==102 and other.secondary==59 and other.secondaryCharge==6)
assert(other.dropped.id==58 and other.dropped.charge==4)
assert(storage:Count(other)==0 and #other.given==3, 'full schoolbag drops the selected active and delivers once')
storage:Add(other,recipe); other.active=59; other.charge=6; other.secondary=102; other.secondaryCharge=2
assert(crafting:Execute(other,second))
assert(other.dropped.id==59 and other.dropped.charge==6 and other.active==102 and other.secondary==102 and other.secondaryCharge==2)
assert(storage:Count(other)==0 and #other.given==4, 'swapping selection drops the newly selected active')
storage:Add(other,recipe); other.active=60; other.secondary=60; other.dropped=nil
local swapped, swapReason=crafting:Execute(other,second)
assert(not swapped and swapReason=='Troca de ativos iguais indisponivel' and not other.dropped)
assert(other.active==60 and other.secondary==60 and storage:Count(other)==8 and #other.given==4)
other.schoolbag=false; other.active=61; other.secondary=0
local originalSave, originalOverride = storage.Save, other.CanOverrideActiveItem
storage.Save=function(self, reason, allowEmpty)
    local result=originalSave(self, reason, allowEmpty)
    if reason=='craft debit' then other.CanOverrideActiveItem=function() error('API failure after debit') end end
    return result
end
local succeeded, failure=crafting:Execute(other,second)
storage.Save, other.CanOverrideActiveItem = originalSave, originalOverride
assert(not succeeded and failure=='Erro; ingredientes restaurados' and storage:Count(other)==8 and #other.given==4)
storage:OnGameStarted(true); assert(storage:Count(other)==8, 'unexpected failure refund survives Continue')
local originalAdd=other.AddCollectible
other.active=0; other.AddCollectible=function() error('uncertain delivery') end
succeeded, failure=crafting:Execute(other,second)
other.AddCollectible=originalAdd
assert(not succeeded and failure=='Entrega incerta; consulte o log' and storage:Count(other)==0)
storage:OnGameStarted(true); assert(storage:Count(other)==0, 'uncertain delivery must not be refunded')
print('PASS crafting: hold, cancel, release, stale recipe, save failure and multiplayer')
