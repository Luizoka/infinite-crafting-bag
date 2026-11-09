local Crafting = {}
Crafting.__index = Crafting

local function log(message)
    Isaac.DebugString("[ICB CRAFT] " .. tostring(message))
end

function Crafting.new(storage)
    return setmetatable({storage = storage, busy = false}, Crafting)
end

function Crafting:Validate(player, item, expectedRevision)
    if not self.storage.initialized or not player or not item then return false, "Jogador indisponivel" end
    local ok, result, pool, slot = pcall(function()
        if not player:Exists() or player:IsDead() then return nil, "Jogador indisponivel" end
        local found = false
        for i = 0, Game():GetNumPlayers() - 1 do
            if GetPtrHash(Isaac.GetPlayer(i)) == GetPtrHash(player) then found = true; break end
        end
        if not found then return nil, "Jogador indisponivel" end
        if self.storage.preserveSavedData or self.storage.runSeed == nil then return nil, "Save indisponivel" end
        if Game():GetSeeds():GetStartSeed() ~= self.storage.runSeed then return nil, "Partida alterada" end
        if not player:HasCollectible(CollectibleType.COLLECTIBLE_BAG_OF_CRAFTING) then return nil, "Bag of Crafting indisponivel" end
        if expectedRevision ~= self.storage:GetRevision(player) then return nil, "Estoque alterado; selecione novamente" end
        if type(item.recipe) ~= "table" or #item.recipe ~= 8 then return nil, "Receita invalida" end
        local needed, entries = {}, 0
        for k, id in pairs(item.recipe) do
            entries = entries + 1
            if type(k) ~= "number" or k % 1 ~= 0 or k < 1 or k > 8 or type(id) ~= "number" or id <= 0 or id % 1 ~= 0 then
                return nil, "Receita invalida"
            end
            needed[id] = (needed[id] or 0) + 1
        end
        if entries ~= 8 then return nil, "Receita invalida" end
        local counts = self.storage:CountsByType(player)
        for id, count in pairs(needed) do if (counts[id] or 0) < count then return nil, "Ingredientes insuficientes" end end
        local config = Isaac.GetItemConfig():GetCollectible(item.id)
        if not config or not config:IsAvailable() then return nil, "Item bloqueado ou indisponivel" end
        if not player:CanAddCollectibleToInventory(item.id) then return nil, "Inventario indisponivel" end
        local activeSlot = ActiveSlot.SLOT_PRIMARY
        if config.Type == ItemType.ITEM_ACTIVE and player:GetActiveItem(activeSlot) ~= 0 then
            return nil, "Esvazie o espaco de item ativo"
        end
        local id, itemPool = EntityPlayer.CalculateBagOfCraftingOutput(item.recipe)
        if id ~= item.id then return nil, "Receita alterada; selecione novamente" end
        return true, itemPool, activeSlot
    end)
    if not ok then log("validacao falhou: " .. tostring(result)); return false, "Erro de validacao" end
    if not result then return false, pool end
    return true, pool, slot
end

return Crafting
