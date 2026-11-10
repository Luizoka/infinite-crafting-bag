local Crafting = {}
Crafting.__index = Crafting

local function log(message)
    Isaac.DebugString("[ICB CRAFT] " .. tostring(message))
end

function Crafting.new(storage)
    return setmetatable({storage = storage, busy = false, duration = 1200}, Crafting)
end

function Crafting:Reset()
    self.prepared, self.started, self.armed, self.blockUntilRelease = nil, nil, false, false
    self.message, self.messageUntil = nil, nil
end

function Crafting:Prepare(player, item)
    local valid, reason = self:Validate(player, item, self.storage:GetRevision(player))
    if not valid then log("preparacao recusada: " .. tostring(reason)); return false, reason end
    local recipe = {}; for i, id in ipairs(item.recipe) do recipe[i] = id end
    self.prepared = {hash = GetPtrHash(player), item = {id = item.id, name = item.name, recipe = recipe}}
    self.started, self.armed = nil, false
    log("receita preparada; jogador=" .. tostring(player:GetPlayerIndex()) .. ", hash=" .. tostring(GetPtrHash(player))
        .. ", ingredientes=" .. tostring(self.storage:Count(player)) .. ", item=" .. tostring(item.id))
    return true, "Receita pronta: feche e segure Q"
end

function Crafting:Observe(id, player)
    if self.attempt and player and GetPtrHash(player) == self.attempt.hash then
        self.attempt.observed = id
    end
end

function Crafting:FindPlayer()
    if not self.prepared then return nil end
    for i = 0, Game():GetNumPlayers() - 1 do
        local player = Isaac.GetPlayer(i)
        if player and GetPtrHash(player) == self.prepared.hash then return player end
    end
end

function Crafting:ShouldBlock(entity, down)
    if not down or not (self.prepared or self.blockUntilRelease) then return false end
    if not entity then return true end
    local player = entity:ToPlayer()
    return player and player.ControllerIndex == 0
end

function Crafting:Tick(open, down, now)
    if not down then self.blockUntilRelease = false end
    if not self.prepared then self.started = nil; return end
    if open or Game():IsPaused() or not self.storage.initialized then
        self.started, self.armed = nil, false
        return
    end
    if not down then self.started, self.armed = nil, true; return end
    if not self.armed then return end
    self.started = self.started or now
    if now - self.started < self.duration then return end
    self.blockUntilRelease = true
    self.armed, self.started = false, nil
    local player, item = self:FindPlayer(), self.prepared.item
    log("Q concluido; jogador_encontrado=" .. tostring(player ~= nil) .. ", hash=" .. tostring(self.prepared.hash)
        .. ", item=" .. tostring(item.id) .. (player and (", jogador=" .. tostring(player:GetPlayerIndex())
        .. ", ingredientes=" .. tostring(self.storage:Count(player))) or ""))
    self.prepared = nil
    local ok, message = self:Execute(player, item)
    self.message, self.messageUntil = message, now + 4000
    return ok, message
end

function Crafting:Progress(now)
    if not self.started then return 0 end
    return math.min(1, math.max(0, (now - self.started) / self.duration))
end

function Crafting:Validate(player, item, expectedRevision, forDelivery)
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
        if not config then return nil, "Item nao encontrado" end
        local achievement = config.AchievementID
        if achievement ~= -1 and not Isaac.GetPersistentGameData():Unlocked(achievement) then
            return nil, "Item nao desbloqueado"
        end
        local activeSlot = ActiveSlot.SLOT_PRIMARY
        local id, itemPool = EntityPlayer.CalculateBagOfCraftingOutput(item.recipe)
        if id ~= item.id then return nil, "Receita alterada; selecione novamente" end
        if forDelivery then
            if not config:IsAvailable() then return nil, "Item indisponivel nesta partida" end
            -- This API describes Tainted Isaac's limited item inventory, not
            -- the virtual bag or general collectible eligibility.
            if player:GetPlayerType() == PlayerType.PLAYER_ISAAC_B and not player:CanAddCollectibleToInventory(item.id) then
                log("CanAddCollectibleToInventory=false; personagem=Tainted Isaac, jogador="
                    .. tostring(player:GetPlayerIndex()) .. ", item=" .. tostring(item.id))
                return nil, "Item nao cabe no inventario"
            end
            if config.Type == ItemType.ITEM_ACTIVE and player:GetActiveItem(activeSlot) ~= 0 then
                return nil, "Esvazie o espaco de item ativo"
            end
        end
        return true, itemPool, activeSlot
    end)
    if not ok then log("validacao falhou: " .. tostring(result)); return false, "Erro de validacao" end
    if not result then return false, pool end
    return true, pool, slot
end

function Crafting:Execute(player, item)
    if self.busy then return false, "Fabricacao em andamento" end
    self.busy = true
    local ok, success, message = pcall(function()
        if not player then return false, "Jogador indisponivel" end
        local valid, pool, slot = self:Validate(player, item, self.storage:GetRevision(player), true)
        if not valid then return false, pool end
        -- Never compete with a native bag that already contains ingredients.
        for _, id in ipairs(player:GetBagOfCraftingContent()) do
            if id ~= 0 then return false, "Bolsa nativa ocupada" end
        end
        local transaction, err = self.storage:ConsumeRecipe(player, item.recipe)
        if not transaction then return false, err end
        log("consumo aplicado; jogador=" .. tostring(player:GetPlayerIndex()) .. ", restantes=" .. tostring(self.storage:Count(player)))
        local saved, result = pcall(self.storage.Save, self.storage, "craft debit", true)
        if not saved or not result then
            self.storage:RollbackRecipe(transaction)
            log("save falhou antes da entrega; ingredientes restaurados em memoria")
            return false, "Falha ao salvar; nada entregue"
        end
        self.attempt = {hash = GetPtrHash(player)}
        local delivered, failure = pcall(function() player:AddCollectible(item.id, 0, true, slot, 0, pool) end)
        local observed = self.attempt.observed
        self.attempt = nil
        if delivered and observed == item.id then
            log("entrega confirmada; jogador=" .. tostring(player:GetPlayerIndex()) .. ", item=" .. tostring(item.id))
            return true, "Item fabricado!"
        end
        log("entrega incerta; item=" .. tostring(item.id) .. " observado=" .. tostring(observed) .. " erro=" .. tostring(failure))
        return false, "Entrega incerta; consulte o log"
    end)
    self.attempt, self.busy = nil, false
    if not ok then log("erro inesperado: " .. tostring(success)); return false, "Erro; consulte o log" end
    if not success then log(message) end
    return success, message
end

return Crafting
