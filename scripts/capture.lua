local Capture = { pending = {} }

function Capture:Init(mod, storage)
	self.mod = mod
	self.storage = storage
	mod:AddCallback(ModCallbacks.MC_TRY_ADD_TO_BAG_OF_CRAFTING, function(_, player, pickup, ingredients)
		local identity = "index=" .. tostring(player:GetPlayerIndex())
			.. ",controller=" .. tostring(player.ControllerIndex)
			.. ",type=" .. tostring(player:GetPlayerType())
		-- The callback table contains the effective ingredient IDs; a pickup can
		-- contribute several ingredients or none. Keep a copy until success is confirmed.
		if type(ingredients) ~= "table" or #ingredients == 0 then
			print("[ICB DEBUG] callback=MC_TRY_ADD_TO_BAG_OF_CRAFTING; player=" .. identity .. ", ingredients=0")
			return nil
		end
		local copy = {}
		for _, id in ipairs(ingredients) do copy[#copy + 1] = id end
		self.pending[tostring(player:GetPlayerIndex())] = copy
		print("[ICB DEBUG] callback=MC_TRY_ADD_TO_BAG_OF_CRAFTING; player=" .. identity
			.. ", ingredientCount=" .. tostring(#copy) .. ", memoryBeforePost=" .. tostring(self.storage:Count(player)))
		return nil -- Preserve the game's normal add/collect behavior.
	end)

	mod:AddCallback(ModCallbacks.MC_POST_ADD_TO_BAG_OF_CRAFTING, function(_, player)
		local identity = "index=" .. tostring(player:GetPlayerIndex())
			.. ",controller=" .. tostring(player.ControllerIndex)
			.. ",type=" .. tostring(player:GetPlayerType())
		local key = tostring(player:GetPlayerIndex())
		local ingredients = self.pending[key]
		if not ingredients then
			print("[ICB DEBUG] callback=MC_POST_ADD_TO_BAG_OF_CRAFTING; player=" .. identity .. ", pending=ausente")
			return
		end
		self.pending[key] = nil
		self.storage:Add(player, ingredients)
		print("[ICB DEBUG] callback=MC_POST_ADD_TO_BAG_OF_CRAFTING; player=" .. identity
			.. ", added=" .. tostring(#ingredients) .. ", memoryAfter=" .. tostring(self.storage:Count(player)))
		-- The native bag remains a transient, at-most-eight-item buffer. Clearing
		-- only after the engine confirms collection prevents rejecting/duplicating pickups.
		player:SetBagOfCraftingContent({})
		self.storage:Save()
	end)
end

function Capture:ResetPending()
	self.pending = {}
	print("[ICB DEBUG] Capture:ResetPending; captura temporária limpa, estoque não alterado")
end

return Capture
