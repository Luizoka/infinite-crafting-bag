local mod = RegisterMod("Infinite Crafting Bag", 1)

local Storage = include("scripts/storage")
local Capture = include("scripts/capture")
local UI = include("scripts/diagnostics")

Storage:Init(mod)
Capture:Init(mod, Storage)
UI:Init(mod, Storage)

mod:AddCallback(ModCallbacks.MC_POST_GAME_STARTED, function(_, isContinued)
	Storage:OnGameStarted(isContinued)
	Capture:ResetPending()
	print("[ICB DEBUG] callback=MC_POST_GAME_STARTED; Capture:ResetPending executado")
	print("[Infinite Crafting Bag] Mod carregado!")
end)

mod:AddCallback(ModCallbacks.MC_POST_SAVESLOT_LOAD, function(_, saveSlot, isSelected, rawSlot)
	print("[ICB DEBUG] callback=MC_POST_SAVESLOT_LOAD; saveSlot=" .. tostring(saveSlot)
		.. ", isSelected=" .. tostring(isSelected) .. ", rawSlot=" .. tostring(rawSlot))
	Storage:OnSaveSlotLoaded(saveSlot, isSelected, rawSlot)
end)

mod:AddCallback(ModCallbacks.MC_PRE_GAME_EXIT, function(_, shouldSave)
	print("[ICB DEBUG] callback=MC_PRE_GAME_EXIT; ShouldSave=" .. tostring(shouldSave))
	if shouldSave then
		Storage:Save("MC_PRE_GAME_EXIT ShouldSave=true")
	else
		print("[ICB DEBUG] MC_PRE_GAME_EXIT; ShouldSave=false; nenhum SaveData na saída")
	end
end)

mod:AddCallback(ModCallbacks.MC_POST_NEW_ROOM, function()
	print("[ICB DEBUG] callback=MC_POST_NEW_ROOM")
	Storage:Save("MC_POST_NEW_ROOM")
end)
