local Recipes = include("scripts/recipes")
local Catalog = {}
Catalog.__index = Catalog

local function signature(counts, context)
    local ids, parts = {}, {tostring(context)}
    for id, count in pairs(counts) do if count > 0 then ids[#ids + 1] = id end end
    table.sort(ids)
    for _, id in ipairs(ids) do parts[#parts + 1] = tostring(id) .. ":" .. tostring(counts[id]) end
    return table.concat(parts, "|")
end

function Catalog.new(calculate, describe, maxRecipes)
    return setmetatable({calculate = calculate, describe = describe, maxRecipes = maxRecipes or 50000,
        state = "idle", items = {}, version = 0}, Catalog)
end

function Catalog:Refresh(counts, context)
    local key = signature(counts, context)
    if key == self.key then return false end
    self.key = key
    self.items, self.evaluated, self.errors = {}, 0, 0
    self.generator = Recipes.new(counts)
    self.total = self.generator.total
    self.state = self.total == 0 and "complete" or "working"
    self.version = self.version + 1
    return true
end

function Catalog:Step(nodeBudget, recipeBudget)
    if self.state ~= "working" then return 0, 0 end
    local steps, recipes = 0, 0
    while steps < nodeBudget and recipes < recipeBudget and self.state == "working" do
        if self.evaluated >= self.maxRecipes then
            self.state = self.evaluated >= self.total and (self.errors == 0 and "complete" or "error") or "limited"
            break
        end
        local ok, recipe = coroutine.resume(self.generator.thread)
        steps = steps + 1
        if not ok then self.state = "error"; self.error = tostring(recipe); break end
        if recipe then
            recipes = recipes + 1
            self.evaluated = self.evaluated + 1
            local good, id, pool = pcall(self.calculate, recipe)
            if not good then
                self.errors = self.errors + 1
                self.error = tostring(id)
            elseif type(id) == "number" and id > 0 and not self.items[id] then
                local described, info = pcall(self.describe, id)
                if described and info then
                    info.id, info.recipe, info.pool = id, recipe, pool
                    self.items[id] = info
                    self.version = self.version + 1
                else
                    self.errors = self.errors + 1
                    self.error = tostring(info or "collectible metadata unavailable")
                end
            end
        end
        if coroutine.status(self.generator.thread) == "dead" or self.evaluated == self.total then
            self.state = self.errors == 0 and "complete" or "error"
        end
    end
    return steps, recipes
end

function Catalog:Filter(query, availability, quality)
    local items, needle = {}, string.lower(query or "")
    for _, item in pairs(self.items) do
        if string.find(string.lower(item.name), needle, 1, true)
            and (quality == nil or item.quality == quality)
            and (availability == "all" or (availability == "available" and item.available)
                or (availability == "locked" and not item.available)) then
            items[#items + 1] = item
        end
    end
    table.sort(items, function(a, b)
        local an, bn = string.lower(a.name), string.lower(b.name)
        if an == bn then return a.id < b.id end
        return an < bn
    end)
    return items
end

return Catalog
