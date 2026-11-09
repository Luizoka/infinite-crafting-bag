local Storage = { VERSION = 1, players = {}, initialized = false }

local TEST_MARKER = { test = "persistencia", value = 12345 }

local function playerKey(player)
	return tostring(player:GetPlayerIndex())
end

local function summarize(players)
	local parts = {}
	for key, data in pairs(players or {}) do
		local count = type(data) == "table" and type(data.ingredients) == "table" and #data.ingredients or 0
		parts[#parts + 1] = tostring(key) .. "=" .. tostring(count)
	end
	table.sort(parts)
	return #parts > 0 and table.concat(parts, ",") or "(nenhum jogador)"
end

local function validPlayers(players)
	for _, playerData in pairs(players) do
		if type(playerData) ~= "table" or type(playerData.ingredients) ~= "table" then return false end
		for _, ingredientId in ipairs(playerData.ingredients) do
			if type(ingredientId) ~= "number" or ingredientId <= 0 then return false end
		end
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
	print("[ICB DEBUG] " .. message)
end

function Storage:Init(mod)
	self.mod = mod
	self.players = {}
	self.initialized = false
	self.isContinued = nil
	self.runSeed = nil
	log("Storage:Init; memória zerada para inicialização, persistência não alterada")
end

function Storage:GetPlayer(player)
	local key = playerKey(player)
	if not self.players[key] then self.players[key] = { ingredients = {} } end
	return self.players[key]
end

function Storage:Add(player, pickupIds)
	local inventory = self:GetPlayer(player).ingredients
	for _, pickupId in ipairs(pickupIds) do
		if type(pickupId) == "number" and pickupId > 0 then table.insert(inventory, pickupId) end
	end
end

function Storage:Count(player)
	return #self:GetPlayer(player).ingredients
end

function Storage:CountsByType(player)
	local counts = {}
	for _, pickupId in ipairs(self:GetPlayer(player).ingredients) do
		counts[pickupId] = (counts[pickupId] or 0) + 1
	end
	return counts
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

	local okDecode, data = pcall(function() return json.decode(raw) end)
	if not okDecode then
		log(source .. "; JSON decode ERRO=" .. tostring(data))
		return nil, "invalid-json"
	end
	if type(data) ~= "table" then
		log(source .. "; JSON decode=ok, raiz=" .. type(data))
		return nil, "invalid-structure"
	end
	local diagnostic = data.diagnostic
	local diagText = type(diagnostic) == "table"
		and (tostring(diagnostic.test) .. "/" .. tostring(diagnostic.value)) or "ausente"
	log(source .. "; JSON decode=ok, version=" .. tostring(data.version)
		.. ", jogadores=" .. summarize(data.players) .. ", diagnostic=" .. diagText
		.. ", runSeed=" .. tostring(data.runSeed))
	if data.version ~= self.VERSION or type(data.players) ~= "table" or not validPlayers(data.players) then
		return nil, "invalid-structure"
	end
	return data, "ok"
end

function Storage:OnSaveSlotLoaded(saveSlot, isSelected, rawSlot)
	-- This callback also fires for internal/default slots and before a run exists.
	-- Inspect for diagnostics only; it must never restore or reset the active run.
	local source = "MC_POST_SAVESLOT_LOAD saveSlot=" .. tostring(saveSlot)
		.. ", isSelected=" .. tostring(isSelected) .. ", rawSlot=" .. tostring(rawSlot)
	if rawSlot == 0 then
		log(source .. "; estado padrão/fora de sincronia; somente diagnóstico, não será restaurado")
		self:InspectSavedData(source .. "; inspeção somente slot padrão")
		return
	end
	self:InspectSavedData(source .. "; inspeção somente")
end

function Storage:OnGameStarted(isContinued)
	local seed = startSeed()
	log("MC_POST_GAME_STARTED; isContinued=" .. tostring(isContinued)
		.. ", gameFrame=" .. gameFrame() .. ", runSeed=" .. tostring(seed)
		.. ", HasData=" .. tostring(self.mod:HasData()))
	self.isContinued = isContinued
	self.runSeed = seed

	if isContinued then
		local data, status = self:InspectSavedData("MC_POST_GAME_STARTED Continue")
		if data then
			if data.runSeed ~= nil and seed ~= nil and data.runSeed ~= seed then
				log("Continue seed mismatch; estoque persistido preservado e não aplicado. saved="
					.. tostring(data.runSeed) .. ", current=" .. tostring(seed))
				self.players = {}
				self.preserveSavedData = true
			else
				self.players = data.players
				self.preserveSavedData = false
				log("Continue restaurado; jogadores=" .. summarize(self.players))
			end
		else
			self.players = {}
			self.preserveSavedData = true
			log("Continue sem payload válido (" .. tostring(status) .. "); estoque não será salvo vazio")
		end
	else
		log("Estoque zerado em MC_POST_GAME_STARTED (partida nova), gameFrame=" .. gameFrame()
			.. "; antes=" .. summarize(self.players))
		self.players = {}
		self.preserveSavedData = false
	end

	self.initialized = true
	log("Estado pronto; continued=" .. tostring(isContinued) .. ", jogadores=" .. summarize(self.players))
	if not isContinued then self:Save("MC_POST_GAME_STARTED partida nova") end
end

function Storage:Save(reason)
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

	local payload = {
		version = self.VERSION,
		players = self.players,
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
	local okSave, saveError = pcall(function() self.mod:SaveData(encoded) end)
	if not okSave then
		log("SaveData=ERRO: " .. tostring(saveError))
		return
	end
	local okHasAfter, hasAfter = pcall(function() return self.mod:HasData() end)
	log("SaveData chamado; jogadores=" .. summarize(self.players) .. ", bytes=" .. #encoded
		.. ", diagnostic=" .. TEST_MARKER.test .. "/" .. TEST_MARKER.value
		.. ", HasDataAfter=" .. (okHasAfter and tostring(hasAfter) or "ERRO:" .. tostring(hasAfter)))
end

return Storage
