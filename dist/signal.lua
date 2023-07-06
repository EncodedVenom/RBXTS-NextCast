-- Compiled with roblox-ts v2.1.0
-- eslint-disable roblox-ts/no-private-identifier
--[[
	*
	* Represents a connection to a signal.
]]
local Connection
do
	Connection = setmetatable({}, {
		__tostring = function()
			return "Connection"
		end,
	})
	Connection.__index = Connection
	function Connection.new(...)
		local self = setmetatable({}, Connection)
		return self:constructor(...) or self
	end
	function Connection:constructor(signal, fn)
		self.signal = signal
		self.Connected = true
		self._fn = fn
	end
	function Connection:Disconnect()
		if not self.Connected then
			return nil
		end
		self.Connected = false
		if self.signal._handlerListHead == self then
			self.signal._handlerListHead = self._next
		else
			local prev = self.signal._handlerListHead
			while prev and prev._next ~= self do
				prev = prev._next
			end
			if prev then
				prev._next = self._next
			end
		end
	end
	function Connection:Destroy()
		self:Disconnect()
	end
end
--[[
	*
	* Signals allow events to be dispatched to any number of listeners.
]]
local Signal
do
	Signal = setmetatable({}, {
		__tostring = function()
			return "Signal"
		end,
	})
	Signal.__index = Signal
	function Signal.new(...)
		local self = setmetatable({}, Signal)
		return self:constructor(...) or self
	end
	function Signal:constructor()
		self.waitingThreads = {}
		self._handlerListHead = nil
	end
	function Signal:Connect(callback)
		local connection = Connection.new(self, callback)
		if self._handlerListHead ~= nil then
			connection._next = self._handlerListHead
		end
		self._handlerListHead = connection
		return connection
	end
	function Signal:Once(callback)
		local done = false
		local c
		c = self:Connect(function(...)
			local args = { ... }
			if done then
				return nil
			end
			done = true
			c:Disconnect()
			callback(unpack(args))
		end)
		return c
	end
	function Signal:Fire(...)
		local args = { ... }
		local item = self._handlerListHead
		while item do
			if item.Connected then
				task.spawn(item._fn, unpack(args))
			end
			item = item._next
		end
	end
	function Signal:FireDeferred(...)
		local args = { ... }
		local item = self._handlerListHead
		while item do
			if item.Connected then
				task.defer(item._fn, unpack(args))
			end
			item = item._next
		end
	end
	function Signal:Wait()
		local running = coroutine.running()
		self.waitingThreads[running] = true
		self:Once(function(...)
			local args = { ... }
			self.waitingThreads[running] = nil
			task.spawn(running, unpack(args))
		end)
		return coroutine.yield()
	end
	function Signal:DisconnectAll()
		local item = self._handlerListHead
		while item do
			item.Connected = false
			item = item._next
		end
		self._handlerListHead = nil
		local _waitingThreads = self.waitingThreads
		local _arg0 = function(thread)
			return task.cancel(thread)
		end
		for _v in _waitingThreads do
			_arg0(_v, _v, _waitingThreads)
		end
		table.clear(self.waitingThreads)
	end
	function Signal:Destroy()
		self:DisconnectAll()
	end
end
return {
	Connection = Connection,
	Signal = Signal,
}
