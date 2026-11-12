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

local accents = {
    ["á"]="a", ["à"]="a", ["â"]="a", ["ã"]="a", ["ä"]="a", ["Á"]="a", ["À"]="a", ["Â"]="a", ["Ã"]="a", ["Ä"]="a",
    ["é"]="e", ["è"]="e", ["ê"]="e", ["ë"]="e", ["É"]="e", ["È"]="e", ["Ê"]="e", ["Ë"]="e",
    ["í"]="i", ["ì"]="i", ["î"]="i", ["ï"]="i", ["Í"]="i", ["Ì"]="i", ["Î"]="i", ["Ï"]="i",
    ["ó"]="o", ["ò"]="o", ["ô"]="o", ["õ"]="o", ["ö"]="o", ["Ó"]="o", ["Ò"]="o", ["Ô"]="o", ["Õ"]="o", ["Ö"]="o",
    ["ú"]="u", ["ù"]="u", ["û"]="u", ["ü"]="u", ["Ú"]="u", ["Ù"]="u", ["Û"]="u", ["Ü"]="u", ["ç"]="c", ["Ç"]="c",
}
local function normalize(value)
    local result = tostring(value or ""):gsub("[\194-\244][\128-\191]+", accents)
    return result:lower():gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
end

function Catalog.new(calculate, describe, maxRecipes, maxCache)
    return setmetatable({calculate = calculate, describe = describe, maxRecipes = maxRecipes or 50000,
        maxCache = maxCache or 10000, cache = {}, cacheOrder = {}, cacheNext = 1,
        state = "idle", items = {}, version = 0}, Catalog)
end

function Catalog:Refresh(counts, context, cacheContext)
    cacheContext = cacheContext or context
    if self.cacheContext ~= cacheContext then
        self.cache, self.cacheOrder, self.cacheNext, self.cacheContext = {}, {}, 1, cacheContext
    end
    local key = signature(counts, context) .. "|" .. tostring(cacheContext)
    if key == self.key then return false end
    self.key = key
    self.items, self.evaluated, self.errors = {}, 0, 0
    self.generator = Recipes.new(counts)
    self.total = self.generator.total
    self.state = self.total == 0 and "complete" or "working"
    self.version = self.version + 1
    return true
end

function Catalog:Step(nodeBudget, recipeBudget, cachedBudget)
    if self.state ~= "working" then return 0, 0 end
    local steps, recipes, calculations = 0, 0, 0
    cachedBudget = cachedBudget or recipeBudget
    while steps < nodeBudget and recipes < cachedBudget and calculations < recipeBudget and self.state == "working" do
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
            local recipeKey = table.concat(recipe, ",")
            local cached = self.cache[recipeKey]
            local good, id, pool
            if cached then
                good, id, pool = true, cached.id, cached.pool
            else
                calculations = calculations + 1
                good, id, pool = pcall(self.calculate, recipe)
                if good and type(id) == "number" and self.maxCache > 0 then
                    local old = self.cacheOrder[self.cacheNext]
                    if old then self.cache[old] = nil end
                    self.cache[recipeKey] = {id = id, pool = pool}
                    self.cacheOrder[self.cacheNext] = recipeKey
                    self.cacheNext = self.cacheNext % self.maxCache + 1
                end
            end
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
    local items, needle = {}, normalize(query)
    for _, item in pairs(self.items) do
        if string.find(normalize(item.name), needle, 1, true)
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
