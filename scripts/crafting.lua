local Crafting = {}
Crafting.__index = Crafting

local function log(message)
    Isaac.DebugString("[ICB CRAFT] " .. tostring(message))
end

function Crafting.new(storage)
    return setmetatable({storage = storage, busy = false, duration = 1200}, Crafting)
end

function Crafting:Reset()
    self:StopHoldAnimation()
    self:EndPreviewRender()
    self:ClearPreview()
    self.prepared, self.started, self.armed, self.blockUntilRelease = nil, nil, false, false
    self.message, self.messageUntil = nil, nil
    self.deliveryGuard = nil
end

function Crafting:ClearPreview()
    local player = self:FindPlayer()
    if player and self.prepared then
        local ok, err = pcall(function()
            local empty = true
            for _, id in ipairs(player:GetBagOfCraftingContent()) do if id ~= 0 then empty = false; break end end
            if empty and player:GetBagOfCraftingOutput() == self.prepared.item.id then
                -- Recalculating an empty bag clears both output and item pool,
                -- and invalidates the native HUD's cached crafting item.
                player:SetBagOfCraftingContent({})
            end
        end)
        if not ok then log("falha ao limpar previa: " .. tostring(err)) end
    end
end

function Crafting:Cancel(down)
    if not self.prepared then return end
    self:StopHoldAnimation()
    self:EndPreviewRender()
    self:ClearPreview()
    self.prepared, self.started, self.armed = nil, nil, false
    self.blockUntilRelease = down or false
    self.message, self.messageUntil = nil, nil
end

function Crafting:StartHoldAnimation(player)
    if not player then return end
    local ok, err = pcall(function()
        player:AnimateCollectible(CollectibleType.COLLECTIBLE_BAG_OF_CRAFTING, "LiftItem", "PlayerPickup")
    end)
    if ok then self.holdAnimationPlayer = player else log("animacao da bolsa indisponivel: " .. tostring(err)) end
end

function Crafting:StopHoldAnimation()
    local player = self.holdAnimationPlayer
    self.holdAnimationPlayer = nil
    if not player then return end
    local ok, err = pcall(function()
        local animation = player:GetSprite():GetAnimation()
        if animation:find("Pickup", 1, true) or animation:find("LiftItem", 1, true) then
            player:AnimateCollectible(CollectibleType.COLLECTIBLE_BAG_OF_CRAFTING, "HideItem")
        end
    end)
    if not ok then log("falha ao encerrar animacao da bolsa: " .. tostring(err)) end
end

-- The native HUD reads the eight bag slots directly. Mirror the recipe only
-- around its render callback; gameplay and pickup capture keep an empty bag.
function Crafting:BeginPreviewRender(player)
    local prepared = self.prepared
    if self.renderMirror or not self.storage.initialized or not prepared or not player
        or GetPtrHash(player) ~= prepared.hash then return end
    local ok, err = pcall(function()
        for _, id in ipairs(player:GetBagOfCraftingContent()) do if id ~= 0 then return end end
        local recipe = {}
        for i, id in ipairs(prepared.item.recipe) do recipe[i] = id end
        self.renderMirror = {player = player, hash = prepared.hash, recipe = recipe, id = prepared.item.id}
        player:SetBagOfCraftingContent(recipe)
        if player:GetBagOfCraftingOutput() ~= prepared.item.id then
            player:SetBagOfCraftingOutput(prepared.item.id)
        end
    end)
    if not ok then
        log("falha ao preparar renderizacao: " .. tostring(err))
        self:EndPreviewRender()
    end
end

function Crafting:EndPreviewRender(player)
    local mirror = self.renderMirror
    if not mirror or (player and GetPtrHash(player) ~= mirror.hash) then return end
    self.renderMirror = nil
    local ok, err = pcall(function()
        local current = mirror.player:GetBagOfCraftingContent()
        for i = 1, 8 do if current[i] ~= mirror.recipe[i] then return end end
        mirror.player:SetBagOfCraftingContent({})
        if self.prepared and self.prepared.hash == mirror.hash and self.prepared.item.id == mirror.id then
            mirror.player:SetBagOfCraftingOutput(mirror.id)
        end
    end)
    if not ok then log("falha ao restaurar bolsa apos renderizacao: " .. tostring(err)) end
end

function Crafting:SyncPreview()
    if not self.prepared then return end
    local player = self:FindPlayer()
    if not player or not self.storage.initialized then return end
    local ok, err = pcall(function()
        local counts, needed = self.storage:CountsByType(player), {}
        for _, id in ipairs(self.prepared.item.recipe) do needed[id] = (needed[id] or 0) + 1 end
        for id, count in pairs(needed) do
            if (counts[id] or 0) < count then
                self:StopHoldAnimation()
                self:ClearPreview()
                self.prepared, self.started, self.armed = nil, nil, false
                self.message, self.messageUntil = "Ingredientes insuficientes", Isaac.GetTime() + 4000
                return
            end
        end
        -- A populated native bag belongs to the game or another mod.
        for _, id in ipairs(player:GetBagOfCraftingContent()) do if id ~= 0 then return end end
        if player:GetBagOfCraftingOutput() ~= self.prepared.item.id then
            player:SetBagOfCraftingOutput(self.prepared.item.id)
        end
    end)
    if not ok then log("falha ao sincronizar previa: " .. tostring(err)) end
end

function Crafting:Prepare(player, item)
    local valid, reason = self:Validate(player, item, self.storage:GetRevision(player))
    if not valid then log("preparacao recusada: " .. tostring(reason)); return false, reason end
    local checked, empty = pcall(function()
        for _, id in ipairs(player:GetBagOfCraftingContent()) do if id ~= 0 then return false end end
        return true
    end)
    if not checked or not empty then return false, "Bolsa nativa ocupada ou indisponivel" end
    self:StopHoldAnimation()
    self:ClearPreview()
    local recipe = {}; for i, id in ipairs(item.recipe) do recipe[i] = id end
    self.prepared = {hash = GetPtrHash(player), item = {id = item.id, name = item.name, recipe = recipe}}
    self.started, self.armed = nil, false
    self:SyncPreview()
    local synced, nativeOutput = pcall(player.GetBagOfCraftingOutput, player)
    if not synced or nativeOutput ~= item.id then
        self:ClearPreview()
        self.prepared = nil
        return false, "Previa nativa indisponivel"
    end
    log("receita preparada; jogador=" .. tostring(player:GetPlayerIndex()) .. ", hash=" .. tostring(GetPtrHash(player))
        .. ", ingredientes=" .. tostring(self.storage:Count(player)) .. ", item=" .. tostring(item.id))
    return true, "Receita pronta: segure Q"
end

function Crafting:Observe(id, player)
    if self.attempt and player and GetPtrHash(player) == self.attempt.hash then
        self.attempt.observed = id
    elseif self.prepared and player and GetPtrHash(player) == self.prepared.hash
        and id == self.prepared.item.id and Input.IsButtonPressed(Keyboard.KEY_Q, 0) then
        -- An outside delivery won the race. Never grant the same item again.
        log("item selecionado entregue externamente durante Q; fabricacao propria cancelada")
        self:Cancel(true)
    end
end

function Crafting:ShouldPreventExternalDelivery(id, player, down)
    if not down or not player or self.attempt then return false end
    local selection = self.prepared or self.deliveryGuard
    return selection and GetPtrHash(player) == selection.hash and id == selection.item.id or false
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
    if not down then self.blockUntilRelease = false; self.deliveryGuard = nil end
    if not self.prepared then self:StopHoldAnimation(); self.started = nil; return end
    if open or Game():IsPaused() or not self.storage.initialized then
        self:StopHoldAnimation()
        self.started, self.armed = nil, false
        return
    end
    if not down then self:StopHoldAnimation(); self.started, self.armed = nil, true; return end
    if not self.armed then return end
    if not self.started then
        self.started = now
        self:StartHoldAnimation(self:FindPlayer())
    end
    if now - self.started < self.duration then return end
    self.blockUntilRelease = true
    self:StopHoldAnimation()
    self.armed, self.started = false, nil
    local player, item = self:FindPlayer(), self.prepared.item
    self.deliveryGuard = self.prepared
    log("Q concluido; jogador_encontrado=" .. tostring(player ~= nil) .. ", hash=" .. tostring(self.prepared.hash)
        .. ", item=" .. tostring(item.id) .. (player and (", jogador=" .. tostring(player:GetPlayerIndex())
        .. ", ingredientes=" .. tostring(self.storage:Count(player))) or ""))
    local ok, message = self:Execute(player, item)
    if ok or message == "Entrega incerta; consulte o log" then
        self:ClearPreview()
        self.prepared = nil
    else
        self:SyncPreview()
    end
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
    local transaction, deliveryStarted
    local function refund()
        local rolledBack, restored = pcall(self.storage.RollbackRecipe, self.storage, transaction)
        if not rolledBack or not restored then return false end
        transaction = nil
        local saved, persisted = pcall(self.storage.Save, self.storage, "craft rollback", true)
        return saved and persisted == true
    end
    local ok, success, message = pcall(function()
        if not player then return false, "Jogador indisponivel" end
        local valid, pool, slot = self:Validate(player, item, self.storage:GetRevision(player), true)
        if not valid then return false, pool end
        -- Never compete with a native bag that already contains ingredients.
        for _, id in ipairs(player:GetBagOfCraftingContent()) do
            if id ~= 0 then return false, "Bolsa nativa ocupada" end
        end
        local config = Isaac.GetItemConfig():GetCollectible(item.id)
        local primary, secondary, schoolbag = 0, 0, false
        if config.Type == ItemType.ITEM_ACTIVE then
            primary = player:GetActiveItem(ActiveSlot.SLOT_PRIMARY)
            secondary = player:GetActiveItem(ActiveSlot.SLOT_SECONDARY)
            schoolbag = player:HasCollectible(CollectibleType.COLLECTIBLE_SCHOOLBAG)
            if primary ~= 0 and primary == secondary and not player:CanOverrideActiveItem(slot) then
                return false, "Troca de ativos iguais indisponivel"
            end
        end
        local err
        transaction, err = self.storage:ConsumeRecipe(player, item.recipe)
        if not transaction then return false, err end
        log("consumo aplicado; jogador=" .. tostring(player:GetPlayerIndex()) .. ", restantes=" .. tostring(self.storage:Count(player)))
        local saved, result = pcall(self.storage.Save, self.storage, "craft debit", true)
        if not saved or not result then
            if not refund() then return false, "Entrega incerta; consulte o log" end
            log("save falhou antes da entrega; estorno salvo")
            return false, "Falha ao salvar; nada entregue"
        end
        local oldActive = primary
        local hasFreeSchoolbagSlot = schoolbag and secondary == 0
        if oldActive ~= 0 and not player:CanOverrideActiveItem(slot) and not hasFreeSchoolbagSlot then
            -- DropCollectible uses the game's pedestal handling. Never add the
            -- replacement unless the drop succeeded and the target slot is usable.
            local dropped, pedestal = pcall(player.DropCollectible, player, oldActive, nil, false)
            local readPrimary, currentPrimary = pcall(player.GetActiveItem, player, ActiveSlot.SLOT_PRIMARY)
            local readSecondary, currentSecondary = pcall(player.GetActiveItem, player, ActiveSlot.SLOT_SECONDARY)
            -- Removing the selected item may promote the Schoolbag item to
            -- primary; AddCollectible will move it back to secondary.
            local promoted = schoolbag and secondary ~= 0 and currentPrimary == secondary and currentSecondary == 0
            local checked, slotAvailable = pcall(player.CanOverrideActiveItem, player, slot)
            local empty = checked and slotAvailable and currentSecondary == secondary
            if not dropped or not pedestal or not readPrimary or not readSecondary or not (promoted or empty) then
                if not refund() then
                    log("falha ao salvar estorno apos tentativa de soltar item ativo")
                    return false, "Entrega incerta; consulte o log"
                end
                log("troca de ativo interrompida; pedestal=" .. tostring(pedestal) .. ", erro=" .. tostring(not dropped and pedestal or nil))
                return false, "Troca de item ativo indisponivel"
            end
        end
        self.attempt = {hash = GetPtrHash(player)}
        deliveryStarted = true
        local delivered, failure = pcall(function() player:AddCollectible(item.id, 0, true, slot, 0, pool) end)
        local observed = self.attempt.observed
        self.attempt = nil
        if delivered and observed == item.id then
            if schoolbag and primary ~= 0 and secondary ~= 0 and oldActive ~= 0 then
                local checked, newPrimary, newSecondary = pcall(function()
                    return player:GetActiveItem(ActiveSlot.SLOT_PRIMARY), player:GetActiveItem(ActiveSlot.SLOT_SECONDARY)
                end)
                if not checked or newPrimary ~= item.id or newSecondary ~= secondary then
                    log("entrega de ativo divergente; esperado=" .. tostring(item.id) .. "/" .. tostring(secondary)
                        .. ", atual=" .. tostring(newPrimary) .. "/" .. tostring(newSecondary))
                    return false, "Entrega incerta; consulte o log"
                end
            end
            -- Visual only: QueueItem would grant the collectible a second time.
            local animated, animationError = pcall(function() player:AnimateCollectible(item.id) end)
            if not animated then log("animacao indisponivel: " .. tostring(animationError)) end
            log("entrega confirmada; jogador=" .. tostring(player:GetPlayerIndex()) .. ", item=" .. tostring(item.id))
            return true, "Item fabricado!"
        end
        log("entrega incerta; item=" .. tostring(item.id) .. " observado=" .. tostring(observed) .. " erro=" .. tostring(failure))
        return false, "Entrega incerta; consulte o log"
    end)
    self.attempt, self.busy = nil, false
    if not ok then
        log("erro inesperado: " .. tostring(success))
        if transaction and not deliveryStarted and refund() then return false, "Erro; ingredientes restaurados" end
        if transaction then return false, "Entrega incerta; consulte o log" end
        return false, "Erro; consulte o log"
    end
    if not success then log(message) end
    return success, message
end

return Crafting
