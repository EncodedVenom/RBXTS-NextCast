-- Compiled with roblox-ts v2.1.0
local TS = require(script.Parent.TS.RuntimeLib)
-- eslint-disable roblox-ts/no-private-identifier
local _errorMessages = TS.import(script, script.Parent, "errorMessages")
local ERR_CACHE_PARENT_INVALID = _errorMessages.ERR_CACHE_PARENT_INVALID
local ERR_NOT_INSTANCE = _errorMessages.ERR_NOT_INSTANCE
local ERR_POSSIBLE_WRONG_PART = _errorMessages.ERR_POSSIBLE_WRONG_PART
local WARN_NO_PARTS_AVAILABLE = _errorMessages.WARN_NO_PARTS_AVAILABLE
local Workspace = game:GetService("Workspace")
local CF_REALLY_FAR_AWAY = CFrame.new(0, 10e8, 0)
local assertwarn = function(requirement, messageIfNotMet)
	if not requirement then
		warn(messageIfNotMet)
	end
end
local makeFromTemplate = function(template, currentCacheParent)
	local part = template:Clone()
	part.CFrame = CF_REALLY_FAR_AWAY
	part.Anchored = true
	part.Parent = currentCacheParent
	return part
end
local PartCache
do
	PartCache = setmetatable({}, {
		__tostring = function()
			return "PartCache"
		end,
	})
	PartCache.__index = PartCache
	function PartCache.new(...)
		local self = setmetatable({}, PartCache)
		return self:constructor(...) or self
	end
	function PartCache:constructor(template, numPrecreatedParts, currentCacheParent)
		if numPrecreatedParts == nil then
			numPrecreatedParts = 5
		end
		if currentCacheParent == nil then
			currentCacheParent = Workspace
		end
		self.Open = {}
		self.InUse = {}
		self.ExpansionSize = 10
		self._is_part_cache = true
		local _arg0 = numPrecreatedParts > 0
		assert(_arg0, "PrecreatedParts can not be negative!")
		assertwarn(numPrecreatedParts ~= 0, "PrecreatedParts is 0! This may have adverse effects when initially using the cache.")
		assertwarn(template.Archivable, "The template's Archivable property has been set to false, which prevents it from being cloned. It will temporarily be set to true.")
		local oldArchivable = template.Archivable
		template.Archivable = true
		local newTemplate = template:Clone()
		template.Archivable = oldArchivable
		template = newTemplate
		self.CurrentCacheParent = currentCacheParent
		self.Template = template
		for i = 1, numPrecreatedParts do
			local _open = self.Open
			local _arg0_1 = makeFromTemplate(template, self.CurrentCacheParent)
			table.insert(_open, _arg0_1)
		end
		self.Template.Parent = nil
	end
	function PartCache:IsPartCache(object)
		local _result = object
		if _result ~= nil then
			_result = _result._is_part_cache
		end
		local _condition = _result
		if _condition == nil then
			_condition = false
		end
		return _condition
	end
	function PartCache:GetPart()
		local _arg0 = PartCache:IsPartCache(self)
		local _arg1 = string.format(ERR_NOT_INSTANCE, "GetPart", "PartCache.new")
		assert(_arg0, _arg1)
		if #self.Open == 0 then
			local _expansionSize = self.ExpansionSize
			local _arg1_1 = tostring(#self.Open + #self.InUse + self.ExpansionSize)
			warn(string.format(WARN_NO_PARTS_AVAILABLE, _expansionSize, _arg1_1))
			for i = 1, self.ExpansionSize do
				local _open = self.Open
				local _arg0_1 = makeFromTemplate(self.Template, self.CurrentCacheParent)
				table.insert(_open, _arg0_1)
			end
		end
		local _exp = self.Open
		-- ▼ Array.pop ▼
		local _length = #_exp
		local _result = _exp[_length]
		_exp[_length] = nil
		-- ▲ Array.pop ▲
		local part = _result
		table.insert(self.InUse, part)
		return part
	end
	function PartCache:ReturnPart(part)
		local _arg0 = PartCache:IsPartCache(self)
		local _arg1 = string.format(ERR_NOT_INSTANCE, "ReturnPart", "PartCache.new")
		assert(_arg0, _arg1)
		local _inUse = self.InUse
		local _part = part
		local index = (table.find(_inUse, _part) or 0) - 1
		if index == -1 then
			local _name = part.Name
			local _arg1_1 = part:GetFullName()
			error(string.format(ERR_POSSIBLE_WRONG_PART, _name, _arg1_1))
		end
		table.remove(self.InUse, index + 1)
		local _open = self.Open
		local _part_1 = part
		table.insert(_open, _part_1)
		part.CFrame = CF_REALLY_FAR_AWAY
		part.Anchored = true
	end
	function PartCache:SetCacheParent(newParent)
		local _arg0 = PartCache:IsPartCache(self)
		local _arg1 = string.format(ERR_NOT_INSTANCE, "SetCacheParent", "PartCache.new")
		assert(_arg0, _arg1)
		local _arg0_1 = newParent:IsDescendantOf(Workspace)
		assert(_arg0_1, ERR_CACHE_PARENT_INVALID)
		self.CurrentCacheParent = newParent
		local _open = self.Open
		local _arg0_2 = function(object)
			object.Parent = newParent
			return object.Parent
		end
		for _k, _v in _open do
			_arg0_2(_v, _k - 1, _open)
		end
		local _inUse = self.InUse
		local _arg0_3 = function(object)
			object.Parent = newParent
			return object.Parent
		end
		for _k, _v in _inUse do
			_arg0_3(_v, _k - 1, _inUse)
		end
	end
	function PartCache:Expand(numParts)
		if numParts == nil then
			numParts = self.ExpansionSize
		end
		local _arg0 = PartCache:IsPartCache(self)
		local _arg1 = string.format(ERR_NOT_INSTANCE, "Expand", "PartCache.new")
		assert(_arg0, _arg1)
		for i = 1, numParts do
			local _open = self.Open
			local _arg0_1 = makeFromTemplate(self.Template, self.CurrentCacheParent)
			table.insert(_open, _arg0_1)
		end
	end
	function PartCache:Dispose()
		local _arg0 = PartCache:IsPartCache(self)
		local _arg1 = string.format(ERR_NOT_INSTANCE, "Dispose", "PartCache.new")
		assert(_arg0, _arg1)
		local _open = self.Open
		local _arg0_1 = function(object)
			return object:Destroy()
		end
		for _k, _v in _open do
			_arg0_1(_v, _k - 1, _open)
		end
		local _inUse = self.InUse
		local _arg0_2 = function(object)
			return object:Destroy()
		end
		for _k, _v in _inUse do
			_arg0_2(_v, _k - 1, _inUse)
		end
		self.Template:Destroy()
		self.Open = {}
		self.InUse = {}
		-- More TS jank time!
		self.CurrentCacheParent = nil
		self.GetPart = nil
		self.ReturnPart = nil
		self.SetCacheParent = nil
		self.Expand = nil
		self.Dispose = nil
	end
	function PartCache:Destroy()
		self:Dispose()
	end
end
return {
	PartCache = PartCache,
}
