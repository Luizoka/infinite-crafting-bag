-- Enumerates bounded multisets of eight ingredients in sorted order.
local Recipes = {}

function Recipes.new(counts)
    local ids, limits, totalIngredients = {}, {}, 0
    for id, count in pairs(counts) do
        if type(id) == "number" and id > 0 and type(count) == "number" and count > 0 then
            ids[#ids + 1] = id
            totalIngredients = totalIngredients + count
        end
    end
    table.sort(ids)
    for i, id in ipairs(ids) do limits[i] = math.min(8, math.floor(counts[id])) end

    -- Number of unique multisets, not the number of permutations.
    local dp = {[0] = 1}
    for _, limit in ipairs(limits) do
        local nextDP = {}
        for used = 0, 8 do
            for n = 0, math.min(limit, 8 - used) do
                nextDP[used + n] = (nextDP[used + n] or 0) + (dp[used] or 0)
            end
        end
        dp = nextDP
    end
    local total = totalIngredients >= 8 and (dp[8] or 0) or 0
    local current, used = {}, {}
    local thread = coroutine.create(function()
        local function visit(depth, first)
            if depth == 9 then
                local recipe = {}
                for i = 1, 8 do recipe[i] = current[i] end
                coroutine.yield(recipe)
                return
            end
            for i = first, #ids do
                if (used[i] or 0) < limits[i] then
                    coroutine.yield(false) -- Bound traversal work, including non-leaf nodes.
                    used[i] = (used[i] or 0) + 1
                    current[depth] = ids[i]
                    visit(depth + 1, i)
                    used[i] = used[i] - 1
                end
            end
        end
        if total > 0 then visit(1, 1) end
    end)
    return { thread = thread, total = total }
end

return Recipes
