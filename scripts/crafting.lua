-- The native AddCollectible call returns void. A post callback is our evidence of
-- delivery; a cancelled/changed call is ambiguous, so never refund it blindly.
local Crafting = {}
Crafting.__index = Crafting

local function log(message)
    Isaac.DebugString("[ICB CRAFT] " .. tostring(message))
end

function Crafting.new(storage)
    return setmetatable({storage = storage, busy = false}, Crafting)
end

function Crafting:Observe(id, player)
    if self.attempt and player == self.attempt.player then
        self.attempt.observed = id
    end
end

function Crafting:Validate(player, item, expectedRevision)
    if not self.storage.initialized or not player or not item then return false, "Jogador indisponivel" end
    local ok, result, pool, slot = pcall(function()
        if not player:Exists() or player:IsDead() then return nil, "Jogador indisponivel" end
        local found = false
        for i = 0, Game():GetNumPlayers() - 1 do
            if Isaac.GetPlayer(i) == player then found = true; break end
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

function Crafting:Execute(player, item, revision)
    if self.busy then return false, "Fabricacao em andamento" end
    self.busy = true
    local ok, success, message = pcall(function()
        local valid, pool, slot = self:Validate(player, item, revision)
        if not valid then return false, pool end
        local transaction, err = self.storage:ConsumeRecipe(player, item.recipe)
        if not transaction then return false, err end
        -- Persist the debit before invoking callbacks that may grant an item.
        local saved, savedResult = pcall(self.storage.Save, self.storage, "craft debit", true)
        if not saved or not savedResult then
            self.storage:RollbackRecipe(transaction)
            return false, "Falha ao salvar; nada entregue"
        end
        self.attempt = {player = player}
        local delivered, failure = pcall(function()
            player:AddCollectible(item.id, 0, true, slot, 0, pool)
        end)
        local observed = self.attempt.observed
        self.attempt = nil
        if delivered and observed == item.id then return true, "Item fabricado!" end
        -- Once AddCollectible has been entered other mods may have run effects,
        -- changed the item, or thrown after granting it. Its void return cannot
        -- prove absence of side effects; retaining the debit avoids duplication.
        log("entrega incerta; item=" .. tostring(item.id) .. " observado=" .. tostring(observed) .. " erro=" .. tostring(failure))
        return false, "Entrega incerta; consulte o log"
    end)
    self.attempt, self.busy = nil, false
    if not ok then log("erro inesperado: " .. tostring(success)); return false, "Erro; consulte o log" end
    if not success then log(message) end
    return success, message
end

return Crafting
