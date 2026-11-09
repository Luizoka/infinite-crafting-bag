local UI = { open = {}, renderCallbackLogged = false, playerLogged = {} }

local function getLabel(id)
	local name = BagOfCraftingPickup[id]
	if type(name) == "string" then return name end
	return "Ingrediente " .. tostring(id)
end

function UI:Init(mod, storage)
	self.storage = storage
	self.font = Font()
	self.font:Load("font/pftempestasevencondensed.fnt")
	mod:AddCallback(ModCallbacks.MC_POST_HUD_RENDER, function() self:Render() end)
end

function UI:Render()
	if not self.renderCallbackLogged then
		print("[ICB DEBUG] callback=MC_POST_HUD_RENDER; interface temporary; open-state não persistido")
		self.renderCallbackLogged = true
	end
	for i = 0, Game():GetNumPlayers() - 1 do
		local player = Isaac.GetPlayer(i)
		if player then
			local index = tostring(player:GetPlayerIndex())
			if self.storage.initialized and not self.playerLogged[index] then
				print("[ICB DEBUG] HUD player identity; index=" .. index
					.. ", controller=" .. tostring(player.ControllerIndex)
					.. ", type=" .. tostring(player:GetPlayerType())
					.. ", memory=" .. tostring(self.storage:Count(player)))
				self.playerLogged[index] = true
			end
			if Input.IsButtonTriggered(Keyboard.KEY_I, player.ControllerIndex) then
				self.open[index] = not self.open[index]
			end
			local total = self.storage:Count(player)
			local x, y = 12, 42 + player:GetPlayerIndex() * 72
			self.font:DrawString("Infinite Crafting Bag: " .. total .. " ingredientes (I)", x, y,
				KColor(1, 1, 1, 1), 0, true)
			if self.open[index] then
				local counts = self.storage:CountsByType(player)
				local ids = {}
				for id in pairs(counts) do ids[#ids + 1] = id end
				table.sort(ids)
				self.font:DrawString("Estoque por tipo:", x, y + 12, KColor(1, 1, 1, 1), 0, true)
				for i = 1, math.min(#ids, 10) do
					local id = ids[i]
					self.font:DrawString(getLabel(id) .. " x" .. counts[id], x, y + 24 + (i - 1) * 10,
						KColor(1, 1, 1, 1), 0, true)
				end
				if #ids > 10 then
					self.font:DrawString("... e mais " .. (#ids - 10) .. " tipos", x, y + 124,
						KColor(1, 1, 1, 1), 0, true)
				end
			end
		end
	end
end

return UI
