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

local cacheCalls = 0
local memo = Catalog.new(function(recipe)
    cacheCalls=cacheCalls+1
    return recipe[8] == 1 and 1 or 2, 1
end, function(id)
    return {name=id == 1 and "Coração Eterno" or "LÁGRIMA azul", quality=id == 1 and 4 or 1, available=id == 1}
end, 50000, 10)
local function finish() while memo.state == 'working' do memo:Step(100, 8) end end
memo:Refresh({[1]=8,[2]=1}, 'stock-1', 'run-a'); finish(); eq(cacheCalls,2)
eq(#memo:Filter('coracao', 'available', 4),1)
eq(#memo:Filter('lagrima', 'locked', 1),1)
eq(#memo:Filter('lagrima', 'available', 1),0)
eq(#memo:Filter('coracao', 'all', 1),0)
memo:Refresh({[1]=8,[2]=2}, 'stock-2', 'run-a'); finish(); eq(cacheCalls,3)
memo:Refresh({[1]=8}, 'stock-3', 'run-a'); finish(); eq(cacheCalls,3)
eq(#memo:Filter('', 'all', nil),1)
memo:Refresh({[1]=8,[2]=2}, 'stock-4', 'run-b'); finish(); eq(cacheCalls,6)
local attempts=0
local retry = Catalog.new(function() attempts=attempts+1; if attempts==1 then error('temporary') end; return 1 end,
    function() return {name='test',quality=1,available=true} end)
retry:Refresh({[1]=8}, 'one', 'same'); while retry.state=='working' do retry:Step(64,8) end
eq(retry.state,'error')
retry:Refresh({[1]=8}, 'two', 'same'); while retry.state=='working' do retry:Step(64,8) end
eq(retry.state,'complete'); eq(attempts,2)
local boundedCalls=0
local bounded=Catalog.new(function(recipe) boundedCalls=boundedCalls+1; return recipe[8] end,
    function(id) return {name=tostring(id),quality=0,available=true} end, 50000, 2)
bounded:Refresh({[1]=8,[2]=2}, 'stock-a', 'run')
while bounded.state=='working' do bounded:Step(100,8,64) end
eq(boundedCalls,3)
bounded:Refresh({[1]=8}, 'stock-b', 'run')
while bounded.state=='working' do bounded:Step(100,8,64) end
eq(boundedCalls,4) -- The oldest of three combinations was evicted.

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
