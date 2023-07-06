-- Compiled with roblox-ts v2.1.0
local TS = require(script.Parent.Parent.TS.RuntimeLib)
-- eslint-disable roblox-ts/no-private-identifier
local _errorMessages = TS.import(script, script.Parent.Parent, "errorMessages")
local ERR_CAN_PIERCE_PERFORMANCE = _errorMessages.ERR_CAN_PIERCE_PERFORMANCE
local ERR_HIGH_FIDELITY_SEGMENT_PERFORMANCE = _errorMessages.ERR_HIGH_FIDELITY_SEGMENT_PERFORMANCE
local ERR_NOT_INSTANCE = _errorMessages.ERR_NOT_INSTANCE
local ERR_OBJECT_DISPOSED = _errorMessages.ERR_OBJECT_DISPOSED
local WARN_INCREASE_SEGMENT_SIZE = _errorMessages.WARN_INCREASE_SEGMENT_SIZE
local PartCache = TS.import(script, script.Parent.Parent, "PartCache").PartCache
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local SIMULATION_EVENT = if RunService:IsServer() then RunService.Heartbeat else RunService.RenderStepped
local MAX_PIERCE_TEST_COUNT = 100
local ZERO_VECTOR = Vector3.new()
local VIS_OBJ_NAME = "NextCastVisualizationObjects"
local GetVisualizationObjects = function()
	local visualizationObjects = Workspace.Terrain:FindFirstChild(VIS_OBJ_NAME)
	if visualizationObjects then
		return visualizationObjects
	end
	visualizationObjects = Instance.new("Folder")
	visualizationObjects.Name = VIS_OBJ_NAME
	visualizationObjects.Archivable = false
	visualizationObjects.Parent = Workspace.Terrain
	return visualizationObjects
end
local NextCastRef
local PrintDebug = function(message)
	if NextCastRef.DebugLogging then
		print(message)
	end
end
local DbgVisualizeSegment = function(castStartCFrame, castLength)
	if not NextCastRef.VisualizeCasts then
		return nil
	end
	local adornment = Instance.new("ConeHandleAdornment")
	adornment.Adornee = Workspace.Terrain
	adornment.CFrame = castStartCFrame
	adornment.Height = castLength
	adornment.Color3 = Color3.new()
	adornment.Radius = 0.25
	adornment.Transparency = 0.5
	adornment.Parent = GetVisualizationObjects()
	return adornment
end
local DbgVisualizeHit = function(atCF, wasPierce)
	if not NextCastRef.VisualizeCasts then
		return nil
	end
	local adornment = Instance.new("SphereHandleAdornment")
	adornment.Adornee = Workspace.Terrain
	adornment.CFrame = atCF
	adornment.Radius = 0.4
	adornment.Transparency = 0.25
	adornment.Color3 = if not wasPierce then Color3.new(0.2, 1, 0.5) else Color3.new(1, 0.2, 0.2)
	adornment.Parent = GetVisualizationObjects()
	return adornment
end
local standardizeVelocity = function(directionVector, input)
	local _input = input
	if typeof(_input) == "Vector3" then
		return input
	end
	local _unit = directionVector.Unit
	local _input_1 = input
	return _unit * _input_1
end
local GetPositionAtTime = function(time, origin, InitialVelocity, acceleration)
	local force = Vector3.new((acceleration.X * time ^ 2) / 2, (acceleration.Y * time ^ 2) / 2, (acceleration.Z * time ^ 2) / 2)
	local _origin = origin
	local _initialVelocity = InitialVelocity
	local _time = time
	return _origin + (_initialVelocity * _time) + force
end
local GetVelocityAtTime = function(time, initialVelocity, acceleration)
	local _initialVelocity = initialVelocity
	local _acceleration = acceleration
	local _time = time
	return (_initialVelocity + _acceleration) * _time
end
local GetTrajectoryInfo = function(cast, index)
	local _arg0 = cast.StateInfo.UpdateConnection ~= nil
	assert(_arg0, ERR_OBJECT_DISPOSED)
	local trajectories = cast.StateInfo.Trajectories
	local trajectory = trajectories[index + 1]
	local duration = trajectory.EndTime - trajectory.StartTime
	local origin = trajectory.Origin
	local vel = trajectory.InitialVelocity
	local accel = trajectory.Acceleration
	return GetPositionAtTime(duration, origin, vel, accel), GetVelocityAtTime(duration, vel, accel)
end
local GetLatestTrajectoryEndInfo = function(cast)
	local _arg0 = cast.StateInfo.UpdateConnection ~= nil
	assert(_arg0, ERR_OBJECT_DISPOSED)
	return GetTrajectoryInfo(cast, #cast.StateInfo.Trajectories - 1)
end
local CloneCastParams = function(params)
	local clone = RaycastParams.new()
	clone.CollisionGroup = params.CollisionGroup
	clone.FilterType = params.FilterType
	clone.FilterDescendantsInstances = params.FilterDescendantsInstances
	clone.IgnoreWater = params.IgnoreWater
	return clone
end
local SendRayHit = function(cast, resultOfCast, segmentVelocity, cosmeticBulletObject)
	return cast.Caster.RayHit:Fire(cast, resultOfCast, segmentVelocity, cosmeticBulletObject)
end
local SendRayPierced = function(cast, resultOfCast, segmentVelocity, cosmeticBulletObject)
	return cast.Caster.RayPierced:Fire(cast, resultOfCast, segmentVelocity, cosmeticBulletObject)
end
local SendLengthChanged = function(cast, lastPoint, rayDir, rayDisplacement, segmentVelocity, cosmeticBulletObject)
	return cast.Caster.LengthChanged:Fire(cast, lastPoint, rayDir, rayDisplacement, segmentVelocity, cosmeticBulletObject)
end
local SimulateCast = function(cast, delta, expectingShortCall)
	local _arg0 = cast.StateInfo.UpdateConnection ~= nil
	assert(_arg0, ERR_OBJECT_DISPOSED)
	PrintDebug("Casting for frame.")
	local latestTrajectory = cast.StateInfo.Trajectories[#cast.StateInfo.Trajectories - 1 + 1]
	local origin = latestTrajectory.Origin
	local initialVelocity = latestTrajectory.InitialVelocity
	local acceleration = latestTrajectory.Acceleration
	local totalDelta = cast.StateInfo.TotalRuntime - latestTrajectory.StartTime
	local lastPoint = GetPositionAtTime(totalDelta, origin, initialVelocity, acceleration)
	local lastVelocity = GetVelocityAtTime(totalDelta, initialVelocity, acceleration)
	local lastDelta = cast.StateInfo.TotalRuntime - latestTrajectory.StartTime
	cast.StateInfo.TotalRuntime += delta
	-- Recalculate this. (Artifact from FastCast. Keeping so that it doesn't break expected behavior.)
	totalDelta = cast.StateInfo.TotalRuntime - latestTrajectory.StartTime
	local currentTarget = GetPositionAtTime(totalDelta, origin, initialVelocity, acceleration)
	local segmentVelocity = GetVelocityAtTime(totalDelta, initialVelocity, acceleration)
	local totalDisplacement = currentTarget - lastPoint
	local _unit = totalDisplacement.Unit
	local _magnitude = segmentVelocity.Magnitude
	local _delta = delta
	local rayDir = _unit * _magnitude * _delta
	local targetWorldRoot = cast.RayInfo.WorldRoot
	local resultOfCast = if cast.StateInfo.SphereSize == 0 then targetWorldRoot:Raycast(lastPoint, rayDir, cast.RayInfo.Parameters) else targetWorldRoot:Spherecast(lastPoint, cast.StateInfo.SphereSize, rayDir, cast.RayInfo.Parameters)
	local _result = resultOfCast
	if _result ~= nil then
		_result = _result.Position
	end
	local _condition = _result
	if _condition == nil then
		_condition = currentTarget
	end
	local point = _condition
	local _part = resultOfCast
	if _part ~= nil then
		_part = _part.Instance
	end
	local part = _part
	local _material = resultOfCast
	if _material ~= nil then
		_material = _material.Material
	end
	local material = _material
	-- const normal = resultOfCast?.Normal; // Not used...
	local rayDisplacement = (point - lastPoint).Magnitude
	SendLengthChanged(cast, lastPoint, rayDir.Unit, rayDisplacement, segmentVelocity, cast.RayInfo.CosmeticBulletObject)
	cast.StateInfo.DistanceCovered += rayDisplacement
	local rayVisualization
	if delta > 0 then
		rayVisualization = DbgVisualizeSegment(CFrame.new(lastPoint, lastPoint + rayDir), rayDisplacement)
	end
	if resultOfCast and (part and part ~= cast.RayInfo.CosmeticBulletObject) then
		local start = os.clock()
		PrintDebug("Hit something, testing now.")
		if cast.RayInfo.CanPierceCallback then
			if not expectingShortCall and cast.StateInfo.IsActivelySimulatingPierce then
				cast:Terminate()
				error(ERR_CAN_PIERCE_PERFORMANCE)
			end
			cast.StateInfo.IsActivelySimulatingPierce = true
		end
		if not cast.RayInfo.CanPierceCallback or not (cast.RayInfo.CanPierceCallback and cast.RayInfo.CanPierceCallback(cast, resultOfCast, segmentVelocity, cast.RayInfo.CosmeticBulletObject)) then
			PrintDebug("Piercing function is nil or it returned FALSE to not pierce this hit.")
			cast.StateInfo.IsActivelySimulatingPierce = false
			if cast.StateInfo.HighFidelityBehavior == 2 and (latestTrajectory.Acceleration ~= ZERO_VECTOR and cast.StateInfo.HighFidelitySegmentSize ~= 0) then
				cast.StateInfo.CancelHighResCast = false
				if cast.StateInfo.IsActivelyResimulating then
					cast:Terminate()
					error(ERR_HIGH_FIDELITY_SEGMENT_PERFORMANCE)
				end
				cast.StateInfo.IsActivelyResimulating = true
				PrintDebug("Hit was registered, but recalculation is on for physics based casts. Recalculating to verify a real hit...")
				local numSegmentsDecimal = rayDisplacement / cast.StateInfo.HighFidelitySegmentSize
				local numSegmentsReal = math.floor(numSegmentsDecimal)
				-- const realSegmentLength = rayDisplacement / numSegmentsReal; // Also not used...
				local timeIncrement = delta / numSegmentsReal
				for segmentIndex = 1, numSegmentsReal do
					if cast.StateInfo.CancelHighResCast then
						cast.StateInfo.CancelHighResCast = false
						break
					end
					local subPosition = GetPositionAtTime(lastDelta + timeIncrement * segmentIndex, origin, initialVelocity, acceleration)
					local subVelocity = GetVelocityAtTime(lastDelta + timeIncrement * segmentIndex, initialVelocity, acceleration)
					local _delta_1 = delta
					local subRayDir = subVelocity * _delta_1
					local subResult = if cast.StateInfo.SphereSize == 0 then targetWorldRoot:Raycast(subPosition, subRayDir, cast.RayInfo.Parameters) else targetWorldRoot:Spherecast(subPosition, cast.StateInfo.SphereSize, subRayDir, cast.RayInfo.Parameters)
					local _arg0_1 = subPosition + subVelocity
					local subDisplacement = (subPosition - _arg0_1).Magnitude
					if subResult then
						local _position = subResult.Position
						subDisplacement = (subPosition - _position).Magnitude
						local dbgSeg = DbgVisualizeSegment(CFrame.new(subPosition, subPosition + subVelocity), subDisplacement)
						if dbgSeg then
							dbgSeg.Color3 = Color3.new(0.286275, 0.329412, 0.247059)
						end
						if cast.RayInfo.CanPierceCallback == nil or not (cast.RayInfo.CanPierceCallback and cast.RayInfo.CanPierceCallback(cast, subResult, subVelocity, cast.RayInfo.CosmeticBulletObject)) then
							-- Still a hit at high res!
							cast.StateInfo.IsActivelyResimulating = false
							SendRayHit(cast, subResult, subVelocity, cast.RayInfo.CosmeticBulletObject)
							cast:Terminate()
							local vis = DbgVisualizeHit(CFrame.new(point), false)
							if vis then
								vis.Color3 = Color3.new(0.0588235, 0.87451, 1)
							end
							return nil
						else
							-- Hit piercable object.
							SendRayPierced(cast, subResult, subVelocity, cast.RayInfo.CosmeticBulletObject)
							local vis = DbgVisualizeHit(CFrame.new(point), true)
							if vis then
								vis.Color3 = Color3.new(1, 0.113725, 0.588235)
							end
							if dbgSeg then
								dbgSeg.Color3 = Color3.new(0.305882, 0.243137, 0.329412)
							end
						end
					else
						local dbgSeg = DbgVisualizeSegment(CFrame.new(subPosition, subPosition + subVelocity), subDisplacement)
						if dbgSeg then
							dbgSeg.Color3 = Color3.new(0.286275, 0.329412, 0.247059)
						end
					end
				end
				cast.StateInfo.IsActivelyResimulating = false
			elseif cast.StateInfo.HighFidelityBehavior ~= 1 and cast.StateInfo.HighFidelityBehavior ~= 3 then
				cast:Terminate()
				error("Invalid value " .. (tostring(cast.StateInfo.HighFidelityBehavior) .. " for HighFidelityBehavior"))
			else
				PrintDebug("Hit was successful. Terminating")
				SendRayHit(cast, resultOfCast, segmentVelocity, cast.RayInfo.CosmeticBulletObject)
				cast:Terminate()
				DbgVisualizeHit(CFrame.new(point), false)
				return nil
			end
		else
			PrintDebug("Piercing function returned TRUE to pierce this part.")
			if rayVisualization then
				rayVisualization.Color3 = Color3.new(0.4, 0.05, 0.05)
			end
			DbgVisualizeHit(CFrame.new(point), true)
			local params = cast.RayInfo.Parameters
			local alteredParts = {}
			local currentPierceTestCount = 0
			local originalFilter = params.FilterDescendantsInstances
			local brokeFromSolidObject = false
			-- eslint-disable-next-line no-constant-condition
			while true do
				if resultOfCast.Instance:IsA("Terrain") then
					-- Pierced water?
					if material == Enum.Material.Water then
						cast:Terminate()
						error("Do not add Water as a piercable material. If you need to pierce water, set cast.RayInfo.Parameters.IgnoreWater = true instead")
					end
					warn("WARNING: The pierce callback for this cast returned TRUE on Terrain! This can cause severely adverse effects.")
				end
				if params.FilterType == Enum.RaycastFilterType.Exclude or params.FilterType == Enum.RaycastFilterType.Blacklist then
					local filter = params.FilterDescendantsInstances
					local _instance = resultOfCast.Instance
					table.insert(filter, _instance)
					local _instance_1 = resultOfCast.Instance
					table.insert(alteredParts, _instance_1)
					params.FilterDescendantsInstances = filter
				else
					local filter = params.FilterDescendantsInstances
					local _instance = resultOfCast.Instance
					local _arg0_1 = (table.find(filter, _instance) or 0) - 1
					table.remove(filter, _arg0_1 + 1)
					local _instance_1 = resultOfCast.Instance
					table.insert(alteredParts, _instance_1)
					params.FilterDescendantsInstances = filter
				end
				SendRayPierced(cast, resultOfCast, segmentVelocity, cast.RayInfo.CosmeticBulletObject)
				-- List updated, let's cast again!
				resultOfCast = if cast.StateInfo.SphereSize == 0 then targetWorldRoot:Raycast(lastPoint, rayDir, params) else targetWorldRoot:Spherecast(lastPoint, cast.StateInfo.SphereSize, rayDir, params)
				if not resultOfCast then
					break
				end
				if currentPierceTestCount >= MAX_PIERCE_TEST_COUNT then
					warn("WARNING: Exceeded maximum pierce test budget for a single ray segment (attempted to test the same segment " .. (tostring(MAX_PIERCE_TEST_COUNT) .. " times!)"))
					break
				end
				currentPierceTestCount += 1
				if cast.RayInfo.CanPierceCallback(cast, resultOfCast, segmentVelocity, cast.RayInfo.CosmeticBulletObject) == false then
					brokeFromSolidObject = true
					break
				end
			end
			cast.RayInfo.Parameters.FilterDescendantsInstances = originalFilter
			cast.StateInfo.IsActivelySimulatingPierce = false
			if brokeFromSolidObject then
				PrintDebug("Broke because the ray hit something solid (" .. (tostring(resultOfCast.Instance) .. ") while testing for a pierce. Terminating the cast."))
				SendRayHit(cast, resultOfCast, segmentVelocity, cast.RayInfo.CosmeticBulletObject)
				cast:Terminate()
				DbgVisualizeHit(CFrame.new(resultOfCast.Position), false)
				return nil
			end
		end
	end
	if cast.StateInfo.DistanceCovered >= cast.RayInfo.MaxDistance and resultOfCast then
		cast:Terminate()
		DbgVisualizeHit(CFrame.new(resultOfCast.Position), false)
	end
end
local ModifyTransformation = function(cast, velocity, acceleration, position)
	local trajectories = cast.StateInfo.Trajectories
	local lastTrajectory = trajectories[#trajectories - 1 + 1]
	if lastTrajectory.StartTime == cast.StateInfo.TotalRuntime then
		lastTrajectory.Origin = position or lastTrajectory.Origin
		lastTrajectory.InitialVelocity = velocity or lastTrajectory.InitialVelocity
		lastTrajectory.Acceleration = acceleration or lastTrajectory.Acceleration
	else
		lastTrajectory.EndTime = cast.StateInfo.TotalRuntime
		local point, velAtPoint = GetLatestTrajectoryEndInfo(cast)
		local _trajectories = cast.StateInfo.Trajectories
		local _arg0 = {
			StartTime = cast.StateInfo.TotalRuntime,
			EndTime = -1,
			Origin = position or point,
			InitialVelocity = velocity or velAtPoint,
			Acceleration = acceleration or lastTrajectory.Acceleration,
		}
		table.insert(_trajectories, _arg0)
		cast.StateInfo.CancelHighResCast = true
	end
end
local ActiveCast
do
	ActiveCast = setmetatable({}, {
		__tostring = function()
			return "ActiveCast"
		end,
	})
	ActiveCast.__index = ActiveCast
	function ActiveCast.new(...)
		local self = setmetatable({}, ActiveCast)
		return self:constructor(...) or self
	end
	function ActiveCast:constructor(Caster, origin, direction, velocity, castDataPacket)
		self.Caster = Caster
		self.UserData = {}
		local _arg0 = castDataPacket.HighFidelitySegmentSize > 0
		local _arg1 = "Cannot set HighFidelitySegmentSize <= 0! (Got " .. (tostring(castDataPacket.HighFidelitySegmentSize) .. ")")
		assert(_arg0, _arg1)
		velocity = standardizeVelocity(direction, velocity)
		local _object = {
			Paused = false,
			TotalRuntime = 0,
			DistanceCovered = 0,
			HighFidelitySegmentSize = castDataPacket.HighFidelitySegmentSize,
			HighFidelityBehavior = castDataPacket.HighFidelityBehavior,
			SphereSize = castDataPacket.SphereSize,
			IsActivelySimulatingPierce = false,
			IsActivelyResimulating = false,
			CancelHighResCast = false,
		}
		local _left = "Trajectories"
		local _arg0_1 = { {
			StartTime = 0,
			EndTime = -1,
			Origin = origin,
			InitialVelocity = velocity,
			Acceleration = castDataPacket.Acceleration,
		} }
		_object[_left] = _arg0_1
		self.StateInfo = _object
		self.RayInfo = {
			Parameters = castDataPacket.RaycastParams or RaycastParams.new(),
			WorldRoot = Workspace,
			MaxDistance = castDataPacket.MaxDistance,
			CosmeticBulletObject = castDataPacket.CosmeticBulletTemplate,
			CanPierceCallback = castDataPacket.CanPierceFunction,
		}
		if self.StateInfo.HighFidelityBehavior == 2 then
			self.StateInfo.HighFidelityBehavior = 3
		end
		local usingProvider = false
		if castDataPacket.CosmeticBulletProvider == nil then
			if self.RayInfo.CosmeticBulletObject then
				self.RayInfo.CosmeticBulletObject = self.RayInfo.CosmeticBulletObject:Clone()
				local _exp = origin
				local _origin = origin
				local _direction = direction
				self.RayInfo.CosmeticBulletObject.CFrame = CFrame.new(_exp, _origin + _direction)
				self.RayInfo.CosmeticBulletObject.Parent = castDataPacket.CosmeticBulletContainer
			end
		else
			if PartCache:IsPartCache(castDataPacket.CosmeticBulletProvider) then
				if self.RayInfo.CosmeticBulletObject ~= nil then
					warn("Do not define FastCastBehavior.CosmeticBulletTemplate and FastCastBehavior.CosmeticBulletProvider at the same time! The provider will be used, and CosmeticBulletTemplate will be set to nil.")
					self.RayInfo.CosmeticBulletObject = nil
					castDataPacket.CosmeticBulletTemplate = nil
				end
				self.RayInfo.CosmeticBulletObject = castDataPacket.CosmeticBulletProvider:GetPart()
				local _exp = origin
				local _origin = origin
				local _direction = direction
				self.RayInfo.CosmeticBulletObject.CFrame = CFrame.new(_exp, _origin + _direction)
				usingProvider = true
			else
				warn("FastCastBehavior.CosmeticBulletProvider was not an instance of the PartCache module (an external/separate model)! Are you inputting an instance created via PartCache.new? If so, are you on the latest version of PartCache? Setting FastCastBehavior.CosmeticBulletProvider to nil.")
				castDataPacket.CosmeticBulletProvider = nil
			end
		end
		local targetContainer = if usingProvider then castDataPacket.CosmeticBulletProvider.CurrentCacheParent else castDataPacket.CosmeticBulletContainer
		if castDataPacket.AutoIgnoreContainer and targetContainer ~= nil then
			local ignoreList = self.RayInfo.Parameters.FilterDescendantsInstances
			if not (table.find(ignoreList, targetContainer) ~= nil) then
				table.insert(ignoreList, targetContainer)
				self.RayInfo.Parameters.FilterDescendantsInstances = ignoreList
			end
		end
		self.StateInfo.UpdateConnection = SIMULATION_EVENT:Connect(function(delta)
			if self.StateInfo.Paused then
				return nil
			end
			PrintDebug("Casting for frame.")
			local latestTrajectory = self.StateInfo.Trajectories[#self.StateInfo.Trajectories - 1 + 1]
			if self.StateInfo.HighFidelityBehavior == NextCastRef.HighFidelityBehavior.Always and (latestTrajectory.Acceleration ~= ZERO_VECTOR and self.StateInfo.HighFidelitySegmentSize > 0) then
				local timeAtStart = os.clock()
				if self.StateInfo.IsActivelyResimulating then
					self:Terminate()
					error(ERR_HIGH_FIDELITY_SEGMENT_PERFORMANCE)
				end
				self.StateInfo.IsActivelyResimulating = true
				local origin = latestTrajectory.Origin
				local initialVelocity = latestTrajectory.InitialVelocity
				local acceleration = latestTrajectory.Acceleration
				local totalDelta = self.StateInfo.TotalRuntime - latestTrajectory.StartTime
				local lastPoint = GetPositionAtTime(totalDelta, origin, initialVelocity, acceleration)
				local lastVelocity = GetVelocityAtTime(totalDelta, initialVelocity, acceleration)
				local lastDelta = self.StateInfo.TotalRuntime - latestTrajectory.StartTime
				self.StateInfo.TotalRuntime += delta
				totalDelta = self.StateInfo.TotalRuntime - latestTrajectory.StartTime
				local currentPoint = GetPositionAtTime(totalDelta, origin, initialVelocity, acceleration)
				local currentVelocity = GetVelocityAtTime(totalDelta, initialVelocity, acceleration)
				local totalDisplacement = currentPoint - lastPoint
				local _unit = totalDisplacement.Unit
				local _magnitude = currentVelocity.Magnitude
				local _delta = delta
				local rayDir = _unit * _magnitude * _delta
				local targetWorldRoot = self.RayInfo.WorldRoot
				local resultOfCast = if self.StateInfo.SphereSize == 0 then targetWorldRoot:Raycast(lastPoint, rayDir, self.RayInfo.Parameters) else targetWorldRoot:Spherecast(lastPoint, self.StateInfo.SphereSize, rayDir, self.RayInfo.Parameters)
				local _result = resultOfCast
				if _result ~= nil then
					_result = _result.Position
				end
				local _condition = _result
				if _condition == nil then
					_condition = currentPoint
				end
				local point = _condition
				local rayDisplacement = (point - lastPoint).Magnitude
				self.StateInfo.TotalRuntime -= delta
				local numSegmentsDecimal = rayDisplacement / self.StateInfo.HighFidelitySegmentSize
				local numSegmentsReal = math.floor(numSegmentsDecimal)
				-- Sets any numSegmentsReal value of 0 to 1 to avoid division by 0.
				local timeIncrement = delta / (if numSegmentsReal == 0 then 1 else numSegmentsReal)
				for segmentIndex = 1, numSegmentsReal do
					if getmetatable(self) == nil then
						return nil
					end
					if self.StateInfo.CancelHighResCast then
						self.StateInfo.CancelHighResCast = false
						break
					end
					PrintDebug("[" .. (tostring(segmentIndex) .. ("] Subcast of time increment " .. tostring(timeIncrement))))
					SimulateCast(self, timeIncrement, true)
				end
				if getmetatable(self) == nil then
					return nil
				end
				self.StateInfo.IsActivelyResimulating = false
				if os.clock() - timeAtStart > 0.016 * 5 then
					warn(WARN_INCREASE_SEGMENT_SIZE)
				end
			else
				SimulateCast(self, delta, false)
			end
		end)
	end
	function ActiveCast:SetVelocity(velocity)
		local _arg0 = getmetatable(self) == ActiveCast
		local _arg1 = string.format(ERR_NOT_INSTANCE, "SetVelocity", "ActiveCast.new(...)")
		assert(_arg0, _arg1)
		local _arg0_1 = self.StateInfo.UpdateConnection ~= nil
		assert(_arg0_1, ERR_OBJECT_DISPOSED)
		ModifyTransformation(self, velocity, nil, nil)
	end
	function ActiveCast:SetAcceleration(acceleration)
		local _arg0 = getmetatable(self) == ActiveCast
		local _arg1 = string.format(ERR_NOT_INSTANCE, "SetAcceleration", "ActiveCast.new(...)")
		assert(_arg0, _arg1)
		local _arg0_1 = self.StateInfo.UpdateConnection ~= nil
		assert(_arg0_1, ERR_OBJECT_DISPOSED)
		ModifyTransformation(self, nil, acceleration, nil)
	end
	function ActiveCast:SetPosition(position)
		local _arg0 = getmetatable(self) == ActiveCast
		local _arg1 = string.format(ERR_NOT_INSTANCE, "SetPosition", "ActiveCast.new(...)")
		assert(_arg0, _arg1)
		local _arg0_1 = self.StateInfo.UpdateConnection ~= nil
		assert(_arg0_1, ERR_OBJECT_DISPOSED)
		ModifyTransformation(self, nil, nil, position)
	end
	function ActiveCast:GetVelocity()
		local _arg0 = getmetatable(self) == ActiveCast
		local _arg1 = string.format(ERR_NOT_INSTANCE, "GetVelocity", "ActiveCast.new(...)")
		assert(_arg0, _arg1)
		local _arg0_1 = self.StateInfo.UpdateConnection ~= nil
		assert(_arg0_1, ERR_OBJECT_DISPOSED)
		local currentTrajectory = self.StateInfo.Trajectories[#self.StateInfo.Trajectories - 1 + 1]
		return GetVelocityAtTime(self.StateInfo.TotalRuntime - currentTrajectory.StartTime, currentTrajectory.InitialVelocity, currentTrajectory.Acceleration)
	end
	function ActiveCast:GetAcceleration()
		local _arg0 = getmetatable(self) == ActiveCast
		local _arg1 = string.format(ERR_NOT_INSTANCE, "GetAcceleration", "ActiveCast.new(...)")
		assert(_arg0, _arg1)
		local _arg0_1 = self.StateInfo.UpdateConnection ~= nil
		assert(_arg0_1, ERR_OBJECT_DISPOSED)
		local currentTrajectory = self.StateInfo.Trajectories[#self.StateInfo.Trajectories - 1 + 1]
		return currentTrajectory.Acceleration
	end
	function ActiveCast:GetPosition()
		local _arg0 = getmetatable(self) == ActiveCast
		local _arg1 = string.format(ERR_NOT_INSTANCE, "GetPosition", "ActiveCast.new(...)")
		assert(_arg0, _arg1)
		local _arg0_1 = self.StateInfo.UpdateConnection ~= nil
		assert(_arg0_1, ERR_OBJECT_DISPOSED)
		local currentTrajectory = self.StateInfo.Trajectories[#self.StateInfo.Trajectories - 1 + 1]
		return GetPositionAtTime(self.StateInfo.TotalRuntime - currentTrajectory.StartTime, currentTrajectory.Origin, currentTrajectory.InitialVelocity, currentTrajectory.Acceleration)
	end
	function ActiveCast:AddVelocity(velocity)
		local _arg0 = getmetatable(self) == ActiveCast
		local _arg1 = string.format(ERR_NOT_INSTANCE, "AddVelocity", "ActiveCast.new(...)")
		assert(_arg0, _arg1)
		local _arg0_1 = self.StateInfo.UpdateConnection ~= nil
		assert(_arg0_1, ERR_OBJECT_DISPOSED)
		local _fn = self
		local _exp = self:GetVelocity()
		local _velocity = velocity
		_fn:SetVelocity(_exp + _velocity)
	end
	function ActiveCast:AddAcceleration(acceleration)
		local _arg0 = getmetatable(self) == ActiveCast
		local _arg1 = string.format(ERR_NOT_INSTANCE, "AddAcceleration", "ActiveCast.new(...)")
		assert(_arg0, _arg1)
		local _arg0_1 = self.StateInfo.UpdateConnection ~= nil
		assert(_arg0_1, ERR_OBJECT_DISPOSED)
		local _fn = self
		local _exp = self:GetAcceleration()
		local _acceleration = acceleration
		_fn:SetAcceleration(_exp + _acceleration)
	end
	function ActiveCast:AddPosition(position)
		local _arg0 = getmetatable(self) == ActiveCast
		local _arg1 = string.format(ERR_NOT_INSTANCE, "AddPosition", "ActiveCast.new(...)")
		assert(_arg0, _arg1)
		local _arg0_1 = self.StateInfo.UpdateConnection ~= nil
		assert(_arg0_1, ERR_OBJECT_DISPOSED)
		local _fn = self
		local _exp = self:GetPosition()
		local _position = position
		_fn:SetPosition(_exp + _position)
	end
	function ActiveCast:Pause()
		local _arg0 = getmetatable(self) == ActiveCast
		local _arg1 = string.format(ERR_NOT_INSTANCE, "Pause", "ActiveCast.new(...)")
		assert(_arg0, _arg1)
		local _arg0_1 = self.StateInfo.UpdateConnection ~= nil
		assert(_arg0_1, ERR_OBJECT_DISPOSED)
		self.StateInfo.Paused = true
	end
	function ActiveCast:Resume()
		local _arg0 = getmetatable(self) == ActiveCast
		local _arg1 = string.format(ERR_NOT_INSTANCE, "Resume", "ActiveCast.new(...)")
		assert(_arg0, _arg1)
		local _arg0_1 = self.StateInfo.UpdateConnection ~= nil
		assert(_arg0_1, ERR_OBJECT_DISPOSED)
		self.StateInfo.Paused = false
	end
	function ActiveCast:Terminate()
		local _arg0 = getmetatable(self) == ActiveCast
		local _arg1 = string.format(ERR_NOT_INSTANCE, "Terminate", "ActiveCast.new(...)")
		assert(_arg0, _arg1)
		local _arg0_1 = self.StateInfo.UpdateConnection ~= nil
		assert(_arg0_1, ERR_OBJECT_DISPOSED)
		local trajectories = self.StateInfo.Trajectories
		local latestTrajectory = trajectories[#trajectories - 1 + 1]
		latestTrajectory.EndTime = self.StateInfo.TotalRuntime
		self.StateInfo.UpdateConnection:Disconnect()
		self.Caster.CastTerminating:Fire()
		self.StateInfo.UpdateConnection = nil
		-- Jank TS hacks. FastCast has this, so I'll keep it to simulate as closely as I can.
		self.Caster = nil
		self.StateInfo = nil
		self.RayInfo = nil
		self.UserData = nil
		setmetatable(self, nil)
	end
	function ActiveCast:Destroy()
		self:Terminate()
	end
	ActiveCast.SetRef = function(reference)
		NextCastRef = reference
	end
end
return {
	ActiveCast = ActiveCast,
}
