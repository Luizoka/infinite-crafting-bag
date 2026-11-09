local function trace(message)
	print(message)
	Isaac.DebugString(message)
end

trace("[ICB BUILD 2026-11-09-prepare-q-02] main.lua iniciado")

local mod = RegisterMod("Infinite Crafting Bag", 1)

local Storage = include("scripts/storage")
local Capture = include("scripts/capture")
local UI = include("scripts/catalog_ui")

Storage:Init(mod)
Capture:Init(mod, Storage)
UI:Init(mod, Storage)
trace("[ICB DEBUG] Modulos inicializados: storage=" .. type(Storage)
	.. ", capture=" .. type(Capture) .. ", diagnostics=" .. type(UI))

mod:AddCallback(ModCallbacks.MC_POST_GAME_STARTED, function(_, isContinued)
	Storage:OnGameStarted(isContinued)
	Capture:ResetPending()
	trace("[ICB DEBUG] callback=MC_POST_GAME_STARTED; Capture:ResetPending executado")
	print("[Infinite Crafting Bag] Mod carregado!")
end)

mod:AddCallback(ModCallbacks.MC_PRE_GAME_EXIT, function(_, shouldSave)
	trace("[ICB DEBUG] callback=MC_PRE_GAME_EXIT; ShouldSave=" .. tostring(shouldSave))
	if not shouldSave then
		trace("[ICB DEBUG] MC_PRE_GAME_EXIT; ShouldSave=false; nenhum SaveData na saída")
	end
	Storage:OnGameExit(shouldSave)
end)

mod:AddCallback(ModCallbacks.MC_POST_NEW_ROOM, function()
	trace("[ICB DEBUG] callback=MC_POST_NEW_ROOM")
	Storage:Save("MC_POST_NEW_ROOM")
end)
