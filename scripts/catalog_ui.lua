local Catalog = include("scripts/catalog")
local InputState = include("scripts/catalog_input")
local Crafting = include("scripts/crafting")
local UI = { open = false, focus = "closed", playerNumber = 0, epoch = 0, query = "", editing = false,
    availability = "all", quality = -1, selected = 1, inventoryView = false, inventoryOffset = 0 }

local ingredientNames = {
    "Coracao vermelho", "Coracao de alma", "Coracao negro", "Coracao eterno", "Coracao dourado",
    "Coracao de osso", "Coracao podre", "Moeda", "Moeda de 5", "Moeda de 10", "Moeda da sorte",
    "Chave", "Chave dourada", "Chave carregada", "Bomba", "Bomba dourada", "Giga bomba",
    "Pilha pequena", "Pilha", "Pilha grande", "Carta", "Pilula", "Runa", "Fragmento de dado",
    "Chave rachada", "Moeda dourada", "Pilula dourada", "Pilha dourada", "Coco"
}
local function ingredientName(id) return ingredientNames[id] or ("Ingrediente " .. tostring(id)) end
local function shortName(name, limit)
    local length = utf8.len(name)
    if length and length > limit then
        local nextCharacter = utf8.offset(name, limit + 1)
        if nextCharacter then return name:sub(1, nextCharacter - 1) .. "..." end
    end
    return name
end
local function describe(id)
    local config = Isaac.GetItemConfig():GetCollectible(id)
    if not config then return nil end
    local name = config.Name or ("Item " .. tostring(id))
    if name:sub(1, 1) == "#" then
        local ok, translated = pcall(Isaac.GetString, "Items", name)
        if ok and type(translated) == "string" and translated ~= "StringTable::InvalidKey" and translated ~= "" then
            name = translated
        else
            name = name:sub(2):gsub("_NAME$", ""):gsub("_", " ")
        end
    end
    return { name = name, quality = config.Quality, available = config:IsAvailable(), gfx = config.GfxFileName }
end

function UI:Init(mod, storage)
    self.storage = storage
    self.crafting = Crafting.new(storage)
    self.font = Font()
    self.font:Load("font/pftempestasevencondensed.fnt")
    self.catalog = Catalog.new(function(recipe)
        self.calculating = true
        local ok, id, pool = pcall(EntityPlayer.CalculateBagOfCraftingOutput, recipe)
        self.calculating = false
        if not ok then error(id) end
        return id, pool
    end, describe)
    self.icons, self.iconCount = {}, 0
    local keys = {Keyboard.KEY_I, Keyboard.KEY_ENTER, Keyboard.KEY_ESCAPE, Keyboard.KEY_TAB,
        Keyboard.KEY_P, Keyboard.KEY_R, Keyboard.KEY_Q, Keyboard.KEY_UP, Keyboard.KEY_DOWN,
        Keyboard.KEY_PAGE_UP, Keyboard.KEY_PAGE_DOWN, Keyboard.KEY_BACKSPACE, Keyboard.KEY_SPACE}
    for code = string.byte("A"), string.byte("Z") do keys[#keys + 1] = code end
    for code = string.byte("0"), string.byte("9") do keys[#keys + 1] = code end
    self.input = InputState.new(keys, {[Keyboard.KEY_UP] = true, [Keyboard.KEY_DOWN] = true})
    mod:AddCallback(ModCallbacks.MC_POST_UPDATE, function() self:Update() end)
    mod:AddCallback(ModCallbacks.MC_POST_RENDER, function() self:HandleInput() end)
    mod:AddCallback(ModCallbacks.MC_POST_HUD_RENDER, function() self:Render() end)
    mod:AddCallback(ModCallbacks.MC_POST_NEW_ROOM, function() self.epoch = self.epoch + 1 end)
    mod:AddCallback(ModCallbacks.MC_POST_ADD_COLLECTIBLE, function(_, id, _, _, _, _, player)
        self.epoch = self.epoch + 1
        self.crafting:Observe(id, player)
    end)
    mod:AddCallback(ModCallbacks.MC_POST_ACHIEVEMENT_UNLOCK, function() self.epoch = self.epoch + 1 end)
    mod:AddCallback(ModCallbacks.MC_POST_GET_COLLECTIBLE, function(_, _, _, decrease)
        if decrease and not self.calculating then self.epoch = self.epoch + 1 end
    end)
    mod:AddCallback(ModCallbacks.MC_POST_GAME_STARTED, function() self:SetFocus("closed"); self.epoch = self.epoch + 1 end)
    mod:AddCallback(ModCallbacks.MC_PRE_GAME_EXIT, function() self:SetFocus("closed") end)
    mod:AddCallback(ModCallbacks.MC_INPUT_ACTION, function(_, entity, hook, action)
        -- Keyboard navigation belongs to controller zero; do not suppress other players.
        if not self.open then return end
        if not entity then
            if action == ButtonAction.ACTION_MAP or action == ButtonAction.ACTION_RESTART then
                if hook == InputHook.GET_ACTION_VALUE then return 0 end
                return false
            end
            return
        end
        local player = entity:ToPlayer()
        if not player or player.ControllerIndex ~= 0 then return end
        if (action >= ButtonAction.ACTION_LEFT and action <= ButtonAction.ACTION_DROP) or action == ButtonAction.ACTION_MAP then
            if hook == InputHook.GET_ACTION_VALUE then return 0 end
            return false
        end
    end)
end

function UI:GetPlayer()
    local count = Game():GetNumPlayers()
    if count < 1 then return nil end
    self.playerNumber = self.playerNumber % count
    return Isaac.GetPlayer(self.playerNumber)
end

function UI:SetFocus(focus)
    if self.focus == focus then return end
    self.focus = focus
    self.open = focus ~= "closed"
    self.editing = focus == "search"
    self.inventoryView = focus == "inventory"
    if self.input then self.input:SuppressHeld() end
    if focus == "closed" then
        self.pending, self.message, self.preferredId = nil, nil, nil
        self.query, self.searchBefore = "", nil
        self.availability, self.quality = "all", -1
        self.selected, self.inventoryOffset = 1, 0
        self.list, self.listKey = nil, nil
    end
end

function UI:FilteredList()
    local c = self.catalog
    local listKey = table.concat({c.version, self.query, self.availability, self.quality}, "|")
    if self.listKey ~= listKey then
        local oldItem = self.list and self.list[self.selected]
        local quality = self.quality >= 0 and self.quality or nil
        self.list = c:Filter(self.query, self.availability, quality)
        self.listKey = listKey
        local restored = false
        if self.preferredId then
            for i, item in ipairs(self.list) do
                if item.id == self.preferredId then self.selected = i; self.preferredId = nil; restored = true; break end
            end
            if c.state ~= "working" then self.preferredId = nil end
        end
        if oldItem and not restored then
            for i, item in ipairs(self.list) do
                if item.id == oldItem.id then self.selected = i; break end
            end
        end
    end
    self.selected = math.max(1, math.min(self.selected, #self.list))
    return self.list
end

function UI:ResetListSelection()
    self.list, self.listKey, self.selected = nil, nil, 1
end

function UI:HandleInput()
    local enabled = self.storage.initialized and not Game():IsPaused()
    local event = self.input:Poll(Isaac.GetTime(), enabled)
    if not enabled then
        if not self.storage.initialized then self:SetFocus("closed") end
        return
    end
    if self.focus == "search" then
        if event[Keyboard.KEY_ENTER] then
            self.searchBefore = nil
            self:SetFocus("results")
        elseif event[Keyboard.KEY_ESCAPE] then
            self.query = self.searchBefore or ""
            self.searchBefore = nil
            self:ResetListSelection()
            self:SetFocus("results")
        elseif event[Keyboard.KEY_BACKSPACE] then
            self.query = self.query:sub(1, -2)
            self:ResetListSelection()
        elseif #self.query < 32 then
            for code = string.byte("A"), string.byte("Z") do
                if event[code] then
                    self.query = self.query .. string.char(code + 32)
                    self:ResetListSelection()
                    return
                end
            end
            for code = string.byte("0"), string.byte("9") do
                if event[code] then
                    self.query = self.query .. string.char(code)
                    self:ResetListSelection()
                    return
                end
            end
            if event[Keyboard.KEY_SPACE] then
                self.query = self.query .. " "
                self:ResetListSelection()
            end
        end
        return
    end
    if self.focus == "confirm" then
        if event[Keyboard.KEY_ESCAPE] then
            self.pending = nil
            self:SetFocus("results")
        elseif event[Keyboard.KEY_ENTER] and self.pending then
            local pending = self.pending
            self.pending = nil
            local success, message
            local currentPlayer = self:GetPlayer()
            if not currentPlayer or GetPtrHash(currentPlayer) ~= GetPtrHash(pending.player) then
                success, message = false, "Jogador alterado"
            else
                success, message = self.crafting:Execute(pending.player, pending.item, pending.revision)
            end
            self.message, self.messageUntil = message, Isaac.GetTime() + 4000
            if success then self.preferredId = pending.item.id end
            self:SetFocus("results")
        end
        return
    end
    if event[Keyboard.KEY_I] then
        self:SetFocus(self.open and "closed" or "results")
    elseif not self.open then
        return
    elseif event[Keyboard.KEY_ESCAPE] then
        self:SetFocus("closed")
    elseif event[Keyboard.KEY_TAB] then
        self:SetFocus(self.inventoryView and "results" or "inventory")
    elseif event[Keyboard.KEY_P] then
        self.playerNumber = self.playerNumber + 1
        self.lastSnapshot = nil
        self:ResetListSelection()
    elseif self.focus == "results" and event[Keyboard.KEY_ENTER] then
        local item = self:FilteredList()[self.selected]
        local player = self:GetPlayer()
        if item and player then
            local copy = {}; for i, id in ipairs(item.recipe) do copy[i] = id end
            local chosen = {id = item.id, name = item.name, quality = item.quality, gfx = item.gfx, recipe = copy}
            local revision = self.storage:GetRevision(player)
            local valid, reason = self.crafting:Validate(player, chosen, revision)
            self.pending = {player = player, item = chosen, revision = revision, valid = valid, reason = reason}
            self:SetFocus("confirm")
        end
    elseif self.focus == "results" and event[Keyboard.KEY_S] then
        self.searchBefore = self.query
        self:SetFocus("search")
    elseif self.focus == "results" and event[Keyboard.KEY_R] then
        self.availability = self.availability == "all" and "available" or self.availability == "available" and "locked" or "all"
        self:ResetListSelection()
    elseif self.focus == "results" and event[Keyboard.KEY_Q] then
        self.quality = (self.quality + 2) % 6 - 1
        self:ResetListSelection()
    elseif event[Keyboard.KEY_UP] then
        if self.inventoryView then self.inventoryOffset = math.max(0, self.inventoryOffset - 2)
        else self.selected = math.max(1, self.selected - 1) end
    elseif event[Keyboard.KEY_DOWN] then
        if self.inventoryView then
            self.inventoryOffset = math.min(math.max(0, #(self.inventoryIds or {}) - 16), self.inventoryOffset + 2)
        else
            self.selected = math.min(math.max(1, #self:FilteredList()), self.selected + 1)
        end
    elseif self.focus == "results" and event[Keyboard.KEY_PAGE_UP] then
        self.selected = math.max(1, self.selected - 8)
    elseif self.focus == "results" and event[Keyboard.KEY_PAGE_DOWN] then
        self.selected = math.min(math.max(1, #self:FilteredList()), self.selected + 8)
    end
end

function UI:Update()
    if not self.storage.initialized then self:SetFocus("closed"); return end
    if not self.open then return end
    local player = self:GetPlayer()
    if not player then return end
    local seed = Game():GetSeeds():GetStartSeed()
    local revision = self.storage:GetRevision(player)
    local snapshot = tostring(player:GetPlayerIndex()) .. ":" .. revision .. ":" .. tostring(seed) .. ":" .. tostring(self.epoch)
    if snapshot ~= self.lastSnapshot then
        self.counts = self.storage:CountsByType(player)
        self.inventoryIds = {}
        for id in pairs(self.counts) do self.inventoryIds[#self.inventoryIds + 1] = id end
        table.sort(self.inventoryIds)
        self.catalog:Refresh(self.counts, snapshot)
        self.lastSnapshot = snapshot
        self.inventoryOffset = 0
        self.listKey = nil
    end
    self.catalog:Step(128, 8)
end

function UI:Draw(text, x, y, size, color)
    self.font:DrawStringScaledUTF8(tostring(text), x, y, size, size, color or KColor(1, 1, 1, 1), 0, true)
end

function UI:Icon(item, x, y, scale)
    if not item.gfx or item.gfx == "" then return end
    local sprite = self.icons[item.id]
    if sprite == nil then
        if self.iconCount >= 64 then self.icons, self.iconCount = {}, 0 end
        local ok, created = pcall(function()
            local s = Sprite()
            s:Load("gfx/005.100_collectible.anm2", false)
            s:ReplaceSpritesheet(1, item.gfx)
            s:LoadGraphics()
            s:SetFrame("Idle", 0)
            return s
        end)
        sprite = ok and created or false
        self.icons[item.id] = sprite
        self.iconCount = self.iconCount + 1
    end
    if sprite then
        sprite.Scale = Vector(scale * 0.38, scale * 0.38)
        sprite:RenderLayer(1, Vector(x, y))
    end
end

function UI:Render()
    if not self.storage.initialized then return end
    local player = self:GetPlayer()
    if not player then return end
    if not self.open then
        self.font:DrawString("Infinite Crafting Bag: " .. self.storage:Count(player) .. " ingredientes (I)", 12, 42, KColor(1, 1, 1, 1), 0, true)
        return
    end
    local w, h = Isaac.GetScreenWidth(), Isaac.GetScreenHeight()
    local s = math.min(1, (w - 12) / 410, (h - 12) / 260)
    local x, y = (w - 410 * s) / 2, (h - 260 * s) / 2
    local function draw(text, dx, dy, size, color) self:Draw(text, x + dx * s, y + dy * s, size * s, color) end
    local bg, gold, white = KColor(0.06, 0.045, 0.04, 0.94), KColor(1, 0.84, 0.52, 1), KColor(1, 1, 1, 1)
    Isaac.DrawQuad(Vector(x,y), Vector(x+410*s,y), Vector(x,y+260*s), Vector(x+410*s,y+260*s), bg, 1)
    draw("INFINITE CRAFTING BAG", 12, 8, 1, gold)
    draw("Jogador " .. (self.playerNumber + 1) .. "  |  Ingredientes: " .. self.storage:Count(player), 12, 24, 0.8, white)
    draw("I fechar  Enter fabricar  S buscar  Tab estoque  P jogador", 12, 39, 0.68, white)
    draw("Setas: navegar   PgUp/PgDn: paginas", 12, 247, 0.68, white)
    if self.focus == "confirm" and self.pending then
        local pending, item = self.pending, self.pending.item
        self:Icon(item, x + 28*s, y + 78*s, s)
        draw("CONFIRMAR FABRICACAO", 12, 55, 0.9, gold)
        draw(shortName(item.name, 38) .. "  [Q" .. tostring(item.quality) .. "]", 48, 72, 0.85, white)
        local counts = self.storage:CountsByType(pending.player)
        local used = {}; for _, id in ipairs(item.recipe) do used[id] = (used[id] or 0) + 1 end
        for n, id in ipairs(item.recipe) do
            local col, row = (n - 1) % 2, math.floor((n - 1) / 2)
            draw(ingredientName(id) .. " " .. (counts[id] or 0) .. "/" .. used[id], 12 + col * 195, 100 + row * 20, 0.74, white)
        end
        local stale = self.storage:GetRevision(pending.player) ~= pending.revision
        draw(stale and "ESTOQUE ALTERADO" or pending.valid and "RECEITA VALIDA" or (pending.reason or "INDISPONIVEL"), 12, 196, 0.8, gold)
        draw("Enter confirmar    Esc cancelar", 12, 220, 0.8, white)
        return
    end
    if self.inventoryView then
        draw("ESTOQUE - setas para rolar", 12, 57, 0.9, gold)
        local ids = self.inventoryIds or {}
        self.inventoryOffset = math.min(self.inventoryOffset, math.max(0, #ids - 16))
        for n = 1, 16 do
            local id = ids[self.inventoryOffset + n]
            if id then
                local col, row = (n - 1) % 2, math.floor((n - 1) / 2)
                draw(ingredientName(id) .. " x" .. self.counts[id], 12 + col * 195, 76 + row * 19, 0.8, white)
            end
        end
        return
    end
    local c = self.catalog
    local list = self:FilteredList()
    local av = self.availability == "all" and "todos" or self.availability == "available" and "liberados" or "bloqueados"
    draw("Busca: " .. self.query .. (self.editing and "_" or ""), 12, 55, 0.78, gold)
    draw("R: " .. av .. "  Q: " .. (self.quality < 0 and "todas" or tostring(self.quality)), 12, 68, 0.75, white)
    local status = c.state == "working" and "BUSCA EM ANDAMENTO" or c.state == "limited" and "LIMITE - BUSCA INCOMPLETA"
        or c.state == "error" and "ERRO - BUSCA INCOMPLETA" or "BUSCA COMPLETA"
    draw(status .. "  " .. (c.evaluated or 0) .. "/" .. (c.total or 0), 12, 81, 0.75, gold)
    local start = math.max(1, self.selected - 5)
    start = math.min(start, math.max(1, #list - 7))
    for row = 0, 7 do
        local index = start + row
        local item = list[index]
        if item then
            local rowY = 96 + row * 14
            self:Icon(item, x + 24*s, y + (rowY+5)*s, s)
            draw((index == self.selected and "> " or "  ") .. shortName(item.name, 38) .. "  [Q" .. tostring(item.quality) .. "]", 36, rowY, 0.78, index == self.selected and gold or white)
        end
    end
    local selected = list[self.selected]
    if selected then
        draw("RECEITA: " .. shortName(selected.name, 35) .. "  (" .. (selected.available and "liberado" or "bloqueado") .. ")", 12, 210, 0.78, gold)
        local used = {}
        for _, id in ipairs(selected.recipe) do used[id] = (used[id] or 0) + 1 end
        local ids = {}; for id in pairs(used) do ids[#ids + 1] = id end; table.sort(ids)
        for n, id in ipairs(ids) do
            draw(ingredientName(id) .. " x" .. used[id], 12 + ((n - 1) % 4) * 98, 225 + math.floor((n - 1) / 4) * 11, 0.62, white)
        end
    elseif #list == 0 then draw(self.storage:Count(player) < 8 and "Ingredientes insuficientes (minimo 8)" or "Nenhum item encontrado", 12, 103, 0.8, white) end
    if self.message and Isaac.GetTime() < self.messageUntil then draw(self.message, 210, 68, 0.7, gold) end
end

return UI
