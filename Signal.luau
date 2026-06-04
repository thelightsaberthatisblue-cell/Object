--////////////////////////////////////////////////////////////
-- SIGNAL
-- lightweight pub/sub per instance
-- each signal is independent - firing one instance's signal
-- does not affect any other instance
-- can be required standalone if needed outside the framework
--
-- listeners stored in a dictionary keyed by ID
-- Connect     = O(1)
-- Disconnect  = O(1)
-- Fire        = O(n) snapshot iteration — safe against mid-fire disconnects
-- Once        = auto-disconnects after first fire
-- Wait        = yields until signal fires, tracked so DisconnectAll can cancel
--////////////////////////////////////////////////////////////

local Signal = {}
Signal.__index = Signal

function Signal.new()
	return setmetatable({
		_listeners    = {}, -- { [id] = callback }
		_waitingThreads = {}, -- { [id] = thread } tracked for cancellation
		_nextId       = 0,
	}, Signal)
end

--////////////////////////////////////////////////////////////
-- Connect
-- standard persistent listener
--////////////////////////////////////////////////////////////
function Signal:Connect(callback: (...any) -> ())
	local id            = self._nextId + 1
	self._nextId        = id
	self._listeners[id] = callback

	return {
		Disconnect = function()
			self._listeners[id] = nil
		end
	}
end

--////////////////////////////////////////////////////////////
-- Once
-- fires once then auto-disconnects
--////////////////////////////////////////////////////////////
function Signal:Once(callback: (...any) -> ())
	local id     = self._nextId + 1
	self._nextId = id

	self._listeners[id] = function(...)
		self._listeners[id] = nil
		callback(...)
	end

	return {
		Disconnect = function()
			self._listeners[id] = nil
		end
	}
end

--////////////////////////////////////////////////////////////
-- Wait
-- yields the current thread until the signal fires
-- returns whatever args were passed to Fire()
-- thread is tracked so DisconnectAll can cancel it safely
-- usage: local dmg = signal:Wait()
--////////////////////////////////////////////////////////////
function Signal:Wait(): ...any
	local thread = coroutine.running()
	local id     = self._nextId + 1
	self._nextId = id

	-- track the waiting thread so DisconnectAll can cancel it
	self._waitingThreads[id] = thread

	self._listeners[id] = function(...)
		self._listeners[id]      = nil
		self._waitingThreads[id] = nil
		coroutine.resume(thread, ...)
	end

	return coroutine.yield()
end

--////////////////////////////////////////////////////////////
-- Fire
-- snapshots listeners before iterating
-- safe against callbacks that disconnect themselves mid-fire
--////////////////////////////////////////////////////////////
function Signal:Fire(...)
	-- snapshot so mid-fire disconnects don't affect iteration
	local snapshot = table.clone(self._listeners)
	for _, callback in pairs(snapshot) do
		local ok, err = pcall(callback, ...)
		if not ok then
			warn("Signal Fire error: " .. tostring(err))
		end
	end
end

--////////////////////////////////////////////////////////////
-- DisconnectAll
-- clears all listeners and cancels any waiting coroutines
-- waiting threads are resumed with no args so they don't hang forever
--////////////////////////////////////////////////////////////
function Signal:DisconnectAll()
	-- cancel waiting coroutines first
	for id, thread in pairs(self._waitingThreads) do
		self._listeners[id] = nil
		coroutine.resume(thread) -- resume with no args, Wait() returns nil
	end
	self._waitingThreads = {}
	self._listeners      = {}
	self._nextId         = 0
end

return Signal
