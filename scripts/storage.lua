local json = require("json")
local Storage = { VERSION = 1, players = {}, initialized = false }

local TEST_MARKER = { test = "persistencia", value = 12345 }

local function playerKey(player)
	return tostring(player:GetPlayerIndex())
end

local function summarize(players)
	local parts = {}
	if type(players) ~= "table" then return "(estrutura inválida)" end
	for key, data in pairs(players or {}) do
		local count = type(data) == "table" and type(data.ingredients) == "table" and #data.ingredients or 0
		parts[#parts + 1] = tostring(key) .. "=" .. tostring(count)
	end
	table.sort(parts)
	return #parts > 0 and table.concat(parts, ",") or "(nenhum jogador)"
end

local function validPlayers(players)
	for key, playerData in pairs(players) do
		if type(key) ~= "string" or not key:match("^%d+$") then return false end
		if type(playerData) ~= "table" or type(playerData.ingredients) ~= "table" then return false end
		local count, maxIndex = 0, 0
		for index, ingredientId in pairs(playerData.ingredients) do
			if type(index) ~= "number" or index < 1 or index % 1 ~= 0
				or type(ingredientId) ~= "number" or ingredientId <= 0 or ingredientId % 1 ~= 0 then
				return false
			end
			count = count + 1
			maxIndex = math.max(maxIndex, index)
		end
		if count ~= maxIndex then return false end
	end
	return true
end

local function startSeed()
	local ok, seed = pcall(function() return Game():GetSeeds():GetStartSeed() end)
	if ok then return seed end
	return nil
end

local function gameFrame()
	local ok, frame = pcall(function() return Game():GetFrameCount() end)
	return ok and tostring(frame) or "indisponível"
end

local function log(message)
	local line = "[ICB DEBUG] " .. message
	print(line)
	Isaac.DebugString(line)
end

function Storage:Init(mod)
	self.mod = mod
	self.players = {}
	self.revisions = {}
	self.typeCounts = {}
	self.runRevision = 0
	self.initialized = false
	self.isContinued = nil
	self.runSeed = nil
	self.pendingCraft = nil
	self.craftNotice = nil
	log("Storage:Init; memória zerada para inicialização, persistência não alterada")
	log("JSON importado; encode=" .. type(json.encode) .. ", decode=" .. type(json.decode))
end

function Storage:GetPlayer(player)
	local key = playerKey(player)
	if not self.players[key] then self.players[key] = { ingredients = {} } end
	return self.players[key]
end

function Storage:Add(player, pickupIds)
	local inventory = self:GetPlayer(player).ingredients
	local counts = self:GetTypeCounts(player)
	local added = false
	for _, pickupId in ipairs(pickupIds) do
		if type(pickupId) == "number" and pickupId > 0 then
			table.insert(inventory, pickupId)
			counts[pickupId] = (counts[pickupId] or 0) + 1
			added = true
		end
	end
	if added then
		local key = playerKey(player)
		self.revisions[key] = (self.revisions[key] or 0) + 1
	end
end

function Storage:GetRevision(player)
	return tostring(self.runRevision) .. ":" .. tostring(self.revisions[playerKey(player)] or 0)
end

function Storage:Count(player)
	return #self:GetPlayer(player).ingredients
end

function Storage:GetTypeCounts(player)
	local key = playerKey(player)
	if not self.typeCounts[key] then
		local counts = {}
		for _, pickupId in ipairs(self:GetPlayer(player).ingredients) do
			counts[pickupId] = (counts[pickupId] or 0) + 1
		end
		self.typeCounts[key] = counts
	end
	return self.typeCounts[key]
end

function Storage:CountsByType(player)
	local snapshot = {}
	for id, count in pairs(self:GetTypeCounts(player)) do snapshot[id] = count end
	return snapshot
end

-- Validate the whole multiset before changing the inventory.
function Storage:ConsumeRecipe(player, recipe)
	if type(recipe) ~= "table" or #recipe ~= 8 then return nil, "Receita invalida" end
	local needed, entries = {}, 0
	for key, id in pairs(recipe) do
		entries = entries + 1
		if type(key) ~= "number" or key % 1 ~= 0 or key < 1 or key > 8
			or type(id) ~= "number" or id % 1 ~= 0 or id <= 0 then return nil, "Receita invalida" end
		needed[id] = (needed[id] or 0) + 1
	end
	if entries ~= 8 then return nil, "Receita invalida" end
	local counts = self:GetTypeCounts(player)
	for id, amount in pairs(needed) do
		if (counts[id] or 0) < amount then return nil, "Ingredientes insuficientes" end
	end
	local key, data = playerKey(player), self:GetPlayer(player)
	local original, remaining = data.ingredients, {}
	for _, id in ipairs(original) do
		if (needed[id] or 0) > 0 then needed[id] = needed[id] - 1
		else remaining[#remaining + 1] = id end
	end
	data.ingredients = remaining
	self.typeCounts[key] = nil
	self.revisions[key] = (self.revisions[key] or 0) + 1
	return {key = key, original = original, revision = self.revisions[key]}
end

function Storage:RollbackRecipe(transaction)
	if not transaction or self.revisions[transaction.key] ~= transaction.revision then return false end
	self.players[transaction.key].ingredients = transaction.original
	self.typeCounts[transaction.key] = nil
	self.revisions[transaction.key] = transaction.revision + 1
	return true
end

function Storage:InspectSavedData(source)
	local hasData = self.mod:HasData()
	log(source .. "; HasData=" .. tostring(hasData))
	if not hasData then return nil, "missing" end

	local okLoad, raw = pcall(function() return self.mod:LoadData() end)
	if not okLoad then
		log(source .. "; LoadData ERRO=" .. tostring(raw))
		return nil, "load-error"
	end
	if type(raw) ~= "string" then
		log(source .. "; LoadData tipo=" .. type(raw) .. ", conteúdo não-string")
		return nil, "invalid-data"
	end
	local preview = string.sub(raw, 1, 180):gsub("[%c]", " ")
	log(source .. "; LoadData bytes=" .. #raw .. ", preview=" .. preview)
	if raw == "" then return nil, "empty" end

	local okDecode, data, nextPos = pcall(function() return json.decode(raw) end)
	if not okDecode then
		log(source .. "; JSON decode ERRO=" .. tostring(data))
		return nil, "invalid-json"
	end
	if type(data) ~= "table" then
		log(source .. "; JSON decode=ok, raiz=" .. type(data))
		return nil, "invalid-structure"
	end
	if type(nextPos) ~= "number" or not raw:sub(nextPos):match("^%s*$") then
		log(source .. "; JSON inválido: conteúdo após o objeto; dados preservados")
		return nil, "invalid-json"
	end
	local diagnostic = data.diagnostic
	local diagText = type(diagnostic) == "table"
		and (tostring(diagnostic.test) .. "/" .. tostring(diagnostic.value)) or "ausente"
	log(source .. "; JSON decode=ok, version=" .. tostring(data.version)
		.. ", jogadores=" .. summarize(data.players) .. ", diagnostic=" .. diagText
		.. ", runSeed=" .. tostring(data.runSeed))
	if data.version ~= self.VERSION or type(data.players) ~= "table" or not validPlayers(data.players)
		or type(data.runSeed) ~= "number" or data.runSeed % 1 ~= 0 or data.runSeed < 0 then
		log(source .. "; payload inválido ou sem seed válida; dados preservados")
		return nil, "invalid-structure"
	end
	local pending = data.pendingCraft
	if pending ~= nil then
		if type(pending) ~= "table" or (pending.phase ~= "debited" and pending.phase ~= "delivering")
			or type(pending.player) ~= "string" or not pending.player:match("^%d+$")
			or type(pending.item) ~= "number" or pending.item <= 0 or pending.item % 1 ~= 0
			or type(pending.recipe) ~= "table" or #pending.recipe ~= 8 then return nil, "invalid-structure" end
		local n = 0
		for key, id in pairs(pending.recipe) do
			n = n + 1
			if type(key) ~= "number" or key % 1 ~= 0 or key < 1 or key > 8
				or type(id) ~= "number" or id <= 0 or id % 1 ~= 0 then return nil, "invalid-structure" end
		end
		if n ~= 8 then return nil, "invalid-structure" end
	end
	return data, "ok"
end

function Storage:OnGameStarted(isContinued)
	self.runRevision = self.runRevision + 1
	self.revisions = {}
	self.typeCounts = {}
	local seed = startSeed()
	log("MC_POST_GAME_STARTED; isContinued=" .. tostring(isContinued)
		.. ", gameFrame=" .. gameFrame() .. ", runSeed=" .. tostring(seed)
		.. ", HasData=" .. tostring(self.mod:HasData()))
	self.isContinued = isContinued
	self.runSeed = seed
	self.pendingCraft, self.craftNotice = nil, nil

	if isContinued then
		local data, status = self:InspectSavedData("MC_POST_GAME_STARTED Continue")
		if data then
			if seed == nil or data.runSeed ~= seed then
				log("Continue seed mismatch; estoque persistido preservado e não aplicado. saved="
					.. tostring(data.runSeed) .. ", current=" .. tostring(seed))
				self.players = {}
				self.preserveSavedData = true
			else
				self.players = data.players
				self.pendingCraft = data.pendingCraft
				self.preserveSavedData = false
				log("Continue restaurado; jogadores=" .. summarize(self.players))
			end
		else
			self.players = {}
			self.preserveSavedData = status ~= "missing"
			log("Continue sem payload válido (" .. tostring(status) .. "); proteção=" .. tostring(self.preserveSavedData))
		end
	else
		log("Estoque zerado em MC_POST_GAME_STARTED (partida nova), gameFrame=" .. gameFrame()
			.. "; antes=" .. summarize(self.players))
		self.players = {}
		local _, status = self:InspectSavedData("MC_POST_GAME_STARTED partida nova")
		self.preserveSavedData = status ~= "ok" and status ~= "missing"
		if self.preserveSavedData then log("Dados anteriores inválidos; gravação bloqueada para preservá-los") end
	end

	self.initialized = true
	if self.pendingCraft and self.pendingCraft.phase == "debited" then
		local pending = self.pendingCraft
		local data = self.players[pending.player] or {ingredients = {}}
		self.players[pending.player] = data
		for _, id in ipairs(pending.recipe) do data.ingredients[#data.ingredients + 1] = id end
		self.pendingCraft = nil
		self.craftNotice = "Fabricacao interrompida: ingredientes restaurados"
		if not self:Save("recover interrupted craft", true) then
			self.craftNotice = "Estorno em memoria; falha ao salvar"
		end
	elseif self.pendingCraft then
		self.craftNotice = "Fabricacao interrompida: entrega incerta; veja o log"
		log("Fabricacao interrompida durante entrega; jogador=" .. self.pendingCraft.player
			.. ", item=" .. tostring(self.pendingCraft.item) .. "; sem reentrega ou estorno automatico")
	end
	log("Estado pronto; continued=" .. tostring(isContinued) .. ", jogadores=" .. summarize(self.players))
end

function Storage:OnGameExit(shouldSave)
	if shouldSave then self:Save("MC_PRE_GAME_EXIT ShouldSave=true", true) end
	self.initialized = false
	log("MC_PRE_GAME_EXIT; armazenamento desativado até MC_POST_GAME_STARTED")
end

function Storage:Save(reason, allowEmpty)
	local hasData = self.mod and self.mod:HasData() or false
	log("Save solicitado; callback=" .. tostring(reason) .. ", initialized=" .. tostring(self.initialized)
		.. ", isContinued=" .. tostring(self.isContinued) .. ", HasData=" .. tostring(hasData)
		.. ", jogadores=" .. summarize(self.players))
	if not self.mod or not self.initialized then
		log("Save ignorado antes de MC_POST_GAME_STARTED; persistência mantida")
		return
	end
	if self.preserveSavedData then
		log("Save bloqueado para não sobrescrever dados durante Continue sem restauração válida")
		return
	end
	if self.runSeed == nil then
		log("Save bloqueado: seed da partida indisponível")
		return
	end
	local total = 0
	for _, data in pairs(self.players) do total = total + #data.ingredients end
	if total == 0 and not allowEmpty then
		log("Save vazio ignorado; estoque vazio será gravado apenas ao salvar a partida na saída")
		return
	end

	local payload = {
		version = self.VERSION,
		players = self.players,
		pendingCraft = self.pendingCraft,
		runSeed = self.runSeed,
		-- A marker in the same envelope verifies JSON serialization and SaveData/LoadData
		-- across Continue without introducing another save file or replacing inventory.
		diagnostic = { test = TEST_MARKER.test, value = TEST_MARKER.value },
	}
	local okEncode, encoded = pcall(function() return json.encode(payload) end)
	if not okEncode or type(encoded) ~= "string" then
		log("Save JSON encode=ERRO: " .. tostring(encoded))
		return
	end
	log("JSON encode=ok; ingredientes=" .. tostring(total) .. ", bytes=" .. #encoded)
	local okSave, saveError = pcall(function() self.mod:SaveData(encoded) end)
	if not okSave then
		log("SaveData=ERRO: " .. tostring(saveError))
		return
	end
	local okHasAfter, hasAfter = pcall(function() return self.mod:HasData() end)
	log("SaveData chamado; jogadores=" .. summarize(self.players) .. ", bytes=" .. #encoded
		.. ", diagnostic=" .. TEST_MARKER.test .. "/" .. TEST_MARKER.value
		.. ", HasDataAfter=" .. (okHasAfter and tostring(hasAfter) or "ERRO:" .. tostring(hasAfter)))
	return true
end

return Storage
