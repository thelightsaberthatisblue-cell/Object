--////////////////////////////////////////////////////////////
-- SIGNAL
-- lightweight pub/sub per instance
-- each signal is independent - firing one instance's signal
-- does not affect any other instance
-- can be required standalone if needed outside the framework
--
-- listeners stored in a dictionary keyed by ID
-- Connect  = O(1)
-- Disconnect = O(1)
-- Fire     = O(n) where n = number of active listeners
--////////////////////////////////////////////////////////////

local Signal = {}
Signal.__index = Signal

function Signal.new()
	return setmetatable({
		_listeners = {}, -- { [id] = callback }
		_nextId    = 0,
	}, Signal)
end

function Signal:Connect(callback: (...any) -> ())
	local id       = self._nextId + 1
	self._nextId   = id
	self._listeners[id] = callback

	return {
		Disconnect = function()
			self._listeners[id] = nil
		end
	}
end

function Signal:Fire(...)
	for _, callback in pairs(self._listeners) do
		local ok, err = pcall(callback, ...)
		if not ok then
			warn("Signal Fire error: " .. tostring(err))
		end
	end
end

function Signal:DisconnectAll()
	self._listeners = {}
	self._nextId    = 0
end

return Signal
