local Catalog = include("scripts/catalog")
local UI = { open = false, playerNumber = 0, epoch = 0, query = "", editing = false,
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
    mod:AddCallback(ModCallbacks.MC_POST_UPDATE, function() self:Update() end)
    mod:AddCallback(ModCallbacks.MC_POST_HUD_RENDER, function() self:Render() end)
    mod:AddCallback(ModCallbacks.MC_POST_NEW_ROOM, function() self.epoch = self.epoch + 1 end)
    mod:AddCallback(ModCallbacks.MC_POST_ADD_COLLECTIBLE, function() self.epoch = self.epoch + 1 end)
    mod:AddCallback(ModCallbacks.MC_POST_ACHIEVEMENT_UNLOCK, function() self.epoch = self.epoch + 1 end)
    mod:AddCallback(ModCallbacks.MC_POST_GET_COLLECTIBLE, function(_, _, _, decrease)
        if decrease and not self.calculating then self.epoch = self.epoch + 1 end
    end)
    mod:AddCallback(ModCallbacks.MC_POST_GAME_STARTED, function() self.open = false; self.editing = false; self.epoch = self.epoch + 1 end)
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

local function pressed(key) return key ~= nil and Input.IsButtonTriggered(key, 0) end

function UI:Update()
    if not self.storage.initialized then self.open = false; self.editing = false; return end
    if self.editing then
        if pressed(Keyboard.KEY_ENTER) or pressed(Keyboard.KEY_ESCAPE) then self.editing = false; return end
        if pressed(Keyboard.KEY_BACKSPACE) then self.query = self.query:sub(1, -2) end
        if #self.query < 32 then
            for code = string.byte("A"), string.byte("Z") do
                if pressed(code) then self.query = self.query .. string.char(code + 32) end
            end
            for code = string.byte("0"), string.byte("9") do
                if pressed(code) then self.query = self.query .. string.char(code) end
            end
            if pressed(Keyboard.KEY_SPACE) then self.query = self.query .. " " end
        end
    elseif pressed(Keyboard.KEY_I) then
        self.open = not self.open
    elseif self.open then
        if pressed(Keyboard.KEY_ESCAPE) then self.open = false end
        if pressed(Keyboard.KEY_ENTER) then self.editing = true end
        if pressed(Keyboard.KEY_TAB) then self.inventoryView = not self.inventoryView end
        if pressed(Keyboard.KEY_P) then self.playerNumber = self.playerNumber + 1; self.lastSnapshot = nil; self.selected = 1 end
        if pressed(Keyboard.KEY_F) then
            self.availability = self.availability == "all" and "available" or self.availability == "available" and "locked" or "all"
            self.selected = 1
        end
        if pressed(Keyboard.KEY_Q) then self.quality = (self.quality + 2) % 6 - 1; self.selected = 1 end
        if pressed(Keyboard.KEY_UP) then
            if self.inventoryView then self.inventoryOffset = math.max(0, self.inventoryOffset - 2)
            else self.selected = math.max(1, self.selected - 1) end
        end
        if pressed(Keyboard.KEY_DOWN) then
            if self.inventoryView then self.inventoryOffset = self.inventoryOffset + 2
            else self.selected = self.selected + 1 end
        end
        if pressed(Keyboard.KEY_PAGE_UP) then self.selected = math.max(1, self.selected - 8) end
        if pressed(Keyboard.KEY_PAGE_DOWN) then self.selected = self.selected + 8 end
    end
    if not self.open then return end
    local player = self:GetPlayer()
    if not player then return end
    local seed = Game():GetSeeds():GetStartSeed()
    local revision = self.storage:GetRevision(player)
    local snapshot = tostring(player:GetPlayerIndex()) .. ":" .. revision .. ":" .. tostring(seed) .. ":" .. tostring(self.epoch)
    if snapshot ~= self.lastSnapshot then
        self.counts = self.storage:CountsByType(player)
        self.catalog:Refresh(self.counts, snapshot)
        self.lastSnapshot = snapshot
        self.inventoryOffset = 0
        self.selected = 1
    end
    self.catalog:Step(256, 16)
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
    draw("I fechar   Enter buscar   Tab estoque   P jogador", 12, 39, 0.72, white)
    draw("Setas: navegar   PgUp/PgDn: paginas", 12, 247, 0.68, white)
    if self.inventoryView then
        draw("ESTOQUE - setas para rolar", 12, 57, 0.9, gold)
        local ids = {}
        for id in pairs(self.counts or {}) do ids[#ids + 1] = id end
        table.sort(ids)
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
    local listKey = table.concat({c.version, self.query, self.availability, self.quality}, "|")
    if self.listKey ~= listKey then
        local quality = self.quality >= 0 and self.quality or nil
        self.list = c:Filter(self.query, self.availability, quality)
        self.listKey = listKey
    end
    local list = self.list or {}
    self.selected = math.max(1, math.min(self.selected, #list))
    local av = self.availability == "all" and "todos" or self.availability == "available" and "liberados" or "bloqueados"
    draw("Busca: " .. self.query .. (self.editing and "_" or ""), 12, 55, 0.78, gold)
    draw("F: " .. av .. "  Q: " .. (self.quality < 0 and "todas" or tostring(self.quality)), 12, 68, 0.75, white)
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
    elseif #list == 0 then draw("Nenhum item encontrado", 12, 103, 0.8, white) end
end

return UI
