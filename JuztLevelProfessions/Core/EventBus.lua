local _, JLP = ...
local EventBus = { listeners = {} }

function EventBus:On(eventName, callback)
    if type(eventName) ~= "string" or type(callback) ~= "function" then return false end
    self.listeners[eventName] = self.listeners[eventName] or {}
    self.listeners[eventName][#self.listeners[eventName] + 1] = callback
    return true
end

function EventBus:Emit(eventName, ...)
    local list = self.listeners[eventName]
    if not list then return end
    for _, callback in ipairs(list) do
        local ok, err = pcall(callback, ...)
        if not ok then
            if JLP.RecordRuntimeError then
                JLP:RecordRuntimeError(eventName,err)
            end
        end
    end
end

JLP.EventBus = EventBus
