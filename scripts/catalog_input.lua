-- Sample physical keys once per rendered frame; do not consume action triggers.
local InputState = {}
InputState.__index = InputState

function InputState.new(keys, repeatKeys)
    local ordered, seen = {}, {}
    for _, key in ipairs(keys) do
        if key and not seen[key] then ordered[#ordered + 1] = key; seen[key] = true end
    end
    return setmetatable({keys = ordered, repeatKeys = repeatKeys, held = {}, blocked = {}, repeatAt = {}}, InputState)
end

function InputState:SuppressHeld()
    for key, down in pairs(self.held) do
        if down then self.blocked[key] = true end
    end
    self.repeatAt = {}
end

function InputState:Poll(now, enabled)
    local events = {}
    for _, key in ipairs(self.keys) do
        local down = Input.IsButtonPressed(key, 0)
        local wasDown = self.held[key] or false
        if not down then
            self.blocked[key], self.repeatAt[key] = nil, nil
        elseif not enabled then
            self.blocked[key], self.repeatAt[key] = true, nil
        elseif not self.blocked[key] then
            if not wasDown then
                events[key] = true
                if self.repeatKeys[key] then self.repeatAt[key] = now + 350 end
            elseif self.repeatKeys[key] and self.repeatAt[key] and now >= self.repeatAt[key] then
                events[key] = true
                self.repeatAt[key] = now + 100 -- Do not catch up multiple steps after a stalled frame.
            end
        end
        self.held[key] = down
    end
    return events
end

return InputState
