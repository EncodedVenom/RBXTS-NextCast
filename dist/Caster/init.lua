-- Compiled with roblox-ts v2.1.0
local TS = require(script.Parent.TS.RuntimeLib)
-- eslint-disable roblox-ts/no-private-identifier
local ActiveCast = TS.import(script, script, "activeCast").ActiveCast
local Signal = TS.import(script, script.Parent, "signal").Signal
local Workspace = game:GetService("Workspace")
local HighFidelityBehavior
do
	local _inverse = {}
	HighFidelityBehavior = setmetatable({}, {
		__index = _inverse,
	})
	HighFidelityBehavior.Default = 1
	_inverse[1] = "Default"
	HighFidelityBehavior.Always = 3
	_inverse[3] = "Always"
end
local _arg0 = {
	RaycastParams = nil,
	Acceleration = Vector3.new(),
	MaxDistance = 1000,
	HighFidelityBehavior = HighFidelityBehavior.Default,
	HighFidelitySegmentSize = 0.5,
	AutoIgnoreContainer = true,
	CosmeticBulletTemplate = nil,
	CosmeticBulletProvider = nil,
	CosmeticBulletContainer = nil,
	CanPierceFunction = nil,
	SphereSize = 0,
}
local DEFAULT_BEHAVIOR = _arg0
local Caster
do
	Caster = setmetatable({}, {
		__tostring = function()
			return "Caster"
		end,
	})
	Caster.__index = Caster
	function Caster.new(...)
		local self = setmetatable({}, Caster)
		return self:constructor(...) or self
	end
	function Caster:constructor()
		self.defaultBehavior = DEFAULT_BEHAVIOR
		self.LengthChanged = Signal.new()
		self.RayHit = Signal.new()
		self.RayPierced = Signal.new()
		self.CastTerminating = Signal.new()
		self.WorldRoot = Workspace
		if not Caster._sentStaticReference then
			ActiveCast.SetRef(Caster)
			Caster._sentStaticReference = true
		end
	end
	function Caster:createSimple(castBehavior, raycastParams)
		castBehavior.RaycastParams = raycastParams
		local caster = Caster.new()
		caster.defaultBehavior = castBehavior
		return caster
	end
	function Caster:newBehavior()
		return table.clone(DEFAULT_BEHAVIOR)
	end
	function Caster:Fire(origin, direction, velocity, castDataPacket)
		if castDataPacket == nil then
			castDataPacket = self.defaultBehavior
		end
		local cast = ActiveCast.new(self, origin, direction, velocity, castDataPacket)
		return cast
	end
	Caster.DebugLogging = false
	Caster.VisualizeCasts = false
	Caster.HighFidelityBehavior = HighFidelityBehavior
	Caster._sentStaticReference = false
end
return {
	HighFidelityBehavior = HighFidelityBehavior,
	Caster = Caster,
}
