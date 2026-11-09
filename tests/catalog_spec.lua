-- Run with Lua 5.3+ from the project root: lua tests/catalog_spec.lua
function include(path) return dofile(path .. ".lua") end
local Recipes = include("scripts/recipes")
local Catalog = include("scripts/catalog")
local function enumerate(counts)
    local generator, found = Recipes.new(counts), {}
    while coroutine.status(generator.thread) ~= "dead" do
        local ok, value = coroutine.resume(generator.thread)
        assert(ok, value)
        if value then found[#found + 1] = table.concat(value, ",") end
    end
    assert(#found == generator.total)
    return found
end
local function eq(a,b) assert(a == b, tostring(a) .. " ~= " .. tostring(b)) end

eq(#enumerate({[1]=7}), 0)
local exact = enumerate({[1]=8}); eq(#exact, 1); eq(exact[1], "1,1,1,1,1,1,1,1")
local stock = {[1]=8,[2]=1}
local varied = enumerate(stock); eq(#varied, 2); eq(stock[1], 8); eq(stock[2], 1)
local repeated = enumerate({[1]=4,[2]=4,[3]=2}); eq(#repeated, 6)
local first = enumerate({[3]=2,[1]=4,[2]=4})
for i=1,#first do eq(first[i], repeated[i]) end

local calls = 0
local cat = Catalog.new(function(recipe)
    calls = calls + 1
    if recipe[8] == 1 then return 100, 1 end
    return 101, 2
end, function(id)
    return {name = id == 100 and "Godhead" or "Another Item", quality = id == 100 and 4 or 1, available = id == 100}
end)
assert(cat:Refresh({[1]=8,[2]=2}, "seed-a"))
while cat.state == "working" do
    local nodes, recipes = cat:Step(5, 1)
    assert(nodes <= 5 and recipes <= 1)
end
eq(cat.state, "complete"); eq(calls, 3)
local all = cat:Filter("", "all", nil); eq(#all, 2)
eq(#cat:Filter("god", "all", nil), 1)
eq(#cat:Filter("GODHEAD", "all", 4), 1)
eq(#cat:Filter("god", "all", 1), 0)
eq(#cat:Filter("", "available", nil), 1)
eq(#cat:Filter("", "locked", nil), 1)
assert(not cat:Refresh({[2]=2,[1]=8}, "seed-a"))
assert(cat:Refresh({[1]=8,[2]=3}, "seed-a")); eq(cat.evaluated, 0); eq(next(cat.items), nil)
assert(cat:Refresh({[1]=8,[2]=3}, "seed-b")); eq(cat.evaluated, 0)

local capped = Catalog.new(function() return 100 end, function() return {name="x", quality=1, available=true} end, 2)
local huge = {}; for i=1,29 do huge[i]=100 end
capped:Refresh(huge, "seed")
local nodes, outputs = capped:Step(3, 2); assert(nodes <= 3 and outputs <= 2); eq(capped.state, "working")
while capped.state == "working" do capped:Step(64, 2) end
eq(capped.state, "limited"); eq(capped.evaluated, 2)
local broken = Catalog.new(function() error("unavailable") end, function() end)
broken:Refresh({[1]=8}, "seed")
while broken.state == "working" do broken:Step(64, 8) end
eq(broken.state, "error")
print("PASS catalog: counts, combinations, deduplication, filters, invalidation, budgets, limits and errors")
