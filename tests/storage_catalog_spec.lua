package.preload.json = function() return {encode=function() return "{}" end, decode=function() return {}, 3 end} end
Isaac = {DebugString=function() end}
function Game() return {GetFrameCount=function() return 0 end, GetSeeds=function() return {GetStartSeed=function() return 42 end} end} end
local mod = {HasData=function() return false end}
local player = {GetPlayerIndex=function() return 0 end}
local other = {GetPlayerIndex=function() return 1 end}
local storage = dofile("scripts/storage.lua")
storage:Init(mod); storage:OnGameStarted(false)
local before = storage:GetRevision(player)
storage:Add(player, {1,1,2})
assert(storage:GetRevision(player) ~= before)
assert(storage:Count(player) == 3)
local counts = storage:CountsByType(player)
assert(counts[1] == 2 and counts[2] == 1)
counts[1] = 900
assert(storage:CountsByType(player)[1] == 2, "snapshot must not mutate storage")
storage:Add(other, {2})
assert(storage:CountsByType(other)[2] == 1 and storage:CountsByType(player)[2] == 1)
local old = storage:GetRevision(player)
storage:OnGameStarted(false)
assert(storage:GetRevision(player) ~= old and storage:Count(player) == 0 and next(storage:CountsByType(player)) == nil)
print("PASS storage counts: independent players, snapshots and run revisions")
