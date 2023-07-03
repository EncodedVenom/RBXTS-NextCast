/* eslint-disable roblox-ts/no-private-identifier */
import { RunService, Workspace } from "@rbxts/services";
import type { CastBehavior, NextCast } from "."; // Do not import directly to avoid cyclic references.
import {
	ERR_CAN_PIERCE_PERFORMANCE,
	ERR_HIGH_FIDELITY_SEGMENT_PERFORMANCE,
	ERR_NOT_INSTANCE,
	ERR_OBJECT_DISPOSED,
	WARN_INCREASE_SEGMENT_SIZE,
} from "../errorMessages";
import { PartCache } from "../partCache";

interface CastTrajectory {
	StartTime: number;
	EndTime: number;
	Origin: Vector3;
	InitialVelocity: Vector3;
	Acceleration: Vector3;
}

interface StateInfo {
	UpdateConnection?: RBXScriptConnection;
	HighFidelitySegmentSize: number;
	HighFidelityBehavior: number;
	Paused: boolean;
	TotalRuntime: number;
	DistanceCovered: number;
	IsActivelySimulatingPierce: boolean;
	IsActivelyResimulating: boolean;
	CancelHighResCast: boolean;
	Trajectories: CastTrajectory[];

	SphereSize: number;
}

interface RayInfo<T extends {}> {
	Parameters: RaycastParams;
	WorldRoot: WorldRoot;
	MaxDistance: number;
	CosmeticBulletObject?: BasePart;
	CanPierceCallback?: (
		activeCast: ActiveCast<T>,
		result: RaycastResult,
		segmentVelocity: Vector3,
		cosmeticBulletObject?: BasePart,
	) => boolean;
}

const SIMULATION_EVENT = RunService.IsServer() ? RunService.Heartbeat : RunService.RenderStepped;

const MAX_PIERCE_TEST_COUNT = 100;
const ZERO_VECTOR = new Vector3();
const VIS_OBJ_NAME = "NextCastVisualizationObjects";

const GetVisualizationObjects = () => {
	let visualizationObjects = Workspace.Terrain.FindFirstChild(VIS_OBJ_NAME);
	if (visualizationObjects) return visualizationObjects;
	visualizationObjects = new Instance("Folder");
	visualizationObjects.Name = VIS_OBJ_NAME;
	visualizationObjects.Archivable = false;
	visualizationObjects.Parent = Workspace.Terrain;
	return visualizationObjects;
};

let NextCastRef: typeof NextCast;

const PrintDebug = (message: string) => {
	if (NextCastRef.DebugLogging) print(message);
};

const DbgVisualizeSegment = (castStartCFrame: CFrame, castLength: number) => {
	if (!NextCastRef.VisualizeCasts) return undefined;
	const adornment = new Instance("ConeHandleAdornment");
	adornment.Adornee = Workspace.Terrain;
	adornment.CFrame = castStartCFrame;
	adornment.Height = castLength;
	adornment.Color3 = new Color3();
	adornment.Radius = 0.25;
	adornment.Transparency = 0.5;
	adornment.Parent = GetVisualizationObjects();
	return adornment;
};

const DbgVisualizeHit = (atCF: CFrame, wasPierce: boolean) => {
	if (!NextCastRef.VisualizeCasts) return undefined;
	const adornment = new Instance("SphereHandleAdornment");
	adornment.Adornee = Workspace.Terrain;
	adornment.CFrame = atCF;
	adornment.Radius = 0.4;
	adornment.Transparency = 0.25;
	adornment.Color3 = !wasPierce ? new Color3(0.2, 1, 0.5) : new Color3(1, 0.2, 0.2);
	adornment.Parent = GetVisualizationObjects();
	return adornment;
};

const standardizeVelocity = (directionVector: Vector3, input: Vector3 | number) => {
	if (typeIs(input, "Vector3")) return input;
	return directionVector.Unit.mul(input);
};

const GetPositionAtTime = (time: number, origin: Vector3, InitialVelocity: Vector3, acceleration: Vector3): Vector3 => {
	const force = new Vector3(
		(acceleration.X * time ** 2) / 2,
		(acceleration.Y * time ** 2) / 2,
		(acceleration.Z * time ** 2) / 2,
	);
	return origin.add(InitialVelocity.mul(time)).add(force);
};

const GetVelocityAtTime = (time: number, initialVelocity: Vector3, acceleration: Vector3): Vector3 =>
	initialVelocity.add(acceleration).mul(time);

const GetTrajectoryInfo = <T extends {}>(cast: ActiveCast<T>, index: number) => {
	assert(cast.StateInfo.UpdateConnection !== undefined, ERR_OBJECT_DISPOSED);
	const trajectories = cast.StateInfo.Trajectories;
	const trajectory = trajectories[index];
	const duration = trajectory.EndTime - trajectory.StartTime;

	const origin = trajectory.Origin;
	const vel = trajectory.InitialVelocity;
	const accel = trajectory.Acceleration;

	return $tuple(GetPositionAtTime(duration, origin, vel, accel), GetVelocityAtTime(duration, vel, accel));
};

const GetLatestTrajectoryEndInfo = <T extends {}>(cast: ActiveCast<T>) => {
	assert(cast.StateInfo.UpdateConnection !== undefined, ERR_OBJECT_DISPOSED);
	return GetTrajectoryInfo(cast, cast.StateInfo.Trajectories.size() - 1);
};

const CloneCastParams = (params: RaycastParams) => {
	const clone = new RaycastParams();
	clone.CollisionGroup = params.CollisionGroup;
	clone.FilterType = params.FilterType;
	clone.FilterDescendantsInstances = params.FilterDescendantsInstances;
	clone.IgnoreWater = params.IgnoreWater;
	return clone;
};

const SendRayHit = <T extends {}>(
	cast: ActiveCast<T>,
	resultOfCast: RaycastResult,
	segmentVelocity: Vector3,
	cosmeticBulletObject?: BasePart,
) => cast.Caster.RayHit.Fire(cast, resultOfCast, segmentVelocity, cosmeticBulletObject);

const SendRayPierced = <T extends {}>(
	cast: ActiveCast<T>,
	resultOfCast: RaycastResult,
	segmentVelocity: Vector3,
	cosmeticBulletObject?: BasePart,
) => cast.Caster.RayPierced.Fire(cast, resultOfCast, segmentVelocity, cosmeticBulletObject);

const SendLengthChanged = <T extends {}>(
	cast: ActiveCast<T>,
	lastPoint: Vector3,
	rayDir: Vector3,
	rayDisplacement: number,
	segmentVelocity: Vector3,
	cosmeticBulletObject?: BasePart,
) => cast.Caster.LengthChanged.Fire(cast, lastPoint, rayDir, rayDisplacement, segmentVelocity, cosmeticBulletObject);

const SimulateCast = <T extends {}>(cast: ActiveCast<T>, delta: number, expectingShortCall: boolean) => {
	assert(cast.StateInfo.UpdateConnection !== undefined, ERR_OBJECT_DISPOSED);
	PrintDebug("Casting for frame.");
	const latestTrajectory = cast.StateInfo.Trajectories[cast.StateInfo.Trajectories.size() - 1];

	const origin = latestTrajectory.Origin;
	const initialVelocity = latestTrajectory.InitialVelocity;
	const acceleration = latestTrajectory.Acceleration;

	let totalDelta = cast.StateInfo.TotalRuntime - latestTrajectory.StartTime;

	const lastPoint = GetPositionAtTime(totalDelta, origin, initialVelocity, acceleration);
	const lastVelocity = GetVelocityAtTime(totalDelta, initialVelocity, acceleration);
	const lastDelta = cast.StateInfo.TotalRuntime - latestTrajectory.StartTime;

	cast.StateInfo.TotalRuntime += delta;

	// Recalculate this. (Artifact from FastCast. Keeping so that it doesn't break expected behavior.)
	totalDelta = cast.StateInfo.TotalRuntime - latestTrajectory.StartTime;

	const currentTarget = GetPositionAtTime(totalDelta, origin, initialVelocity, acceleration);
	const segmentVelocity = GetVelocityAtTime(totalDelta, initialVelocity, acceleration);
	const totalDisplacement = currentTarget.sub(lastPoint);

	const rayDir = totalDisplacement.Unit.mul(segmentVelocity.Magnitude).mul(delta);
	const targetWorldRoot = cast.RayInfo.WorldRoot;
	let resultOfCast =
		cast.StateInfo.SphereSize === 0
			? targetWorldRoot.Raycast(lastPoint, rayDir, cast.RayInfo.Parameters)
			: targetWorldRoot.Spherecast(lastPoint, cast.StateInfo.SphereSize, rayDir, cast.RayInfo.Parameters);

	const point = resultOfCast?.Position ?? currentTarget;
	const part = resultOfCast?.Instance;
	const material = resultOfCast?.Material;
	//const normal = resultOfCast?.Normal; // Not used...

	const rayDisplacement = point.sub(lastPoint).Magnitude;

	SendLengthChanged(
		cast,
		lastPoint,
		rayDir.Unit,
		rayDisplacement,
		segmentVelocity,
		cast.RayInfo.CosmeticBulletObject,
	);
	cast.StateInfo.DistanceCovered += rayDisplacement;

	let rayVisualization: ConeHandleAdornment | undefined;
	if (delta > 0)
		rayVisualization = DbgVisualizeSegment(new CFrame(lastPoint, lastPoint.add(rayDir)), rayDisplacement);

	if (resultOfCast && part && part !== cast.RayInfo.CosmeticBulletObject) {
		const start = os.clock();
		PrintDebug("Hit something, testing now.");

		if (cast.RayInfo.CanPierceCallback) {
			if (!expectingShortCall && cast.StateInfo.IsActivelySimulatingPierce) {
				cast.Terminate();
				error(ERR_CAN_PIERCE_PERFORMANCE);
			}
			cast.StateInfo.IsActivelySimulatingPierce = true;
		}

		if (
			!cast.RayInfo.CanPierceCallback ||
			!(
				cast.RayInfo.CanPierceCallback &&
				cast.RayInfo.CanPierceCallback(cast, resultOfCast, segmentVelocity, cast.RayInfo.CosmeticBulletObject)
			)
		) {
			PrintDebug("Piercing function is nil or it returned FALSE to not pierce this hit.");
			cast.StateInfo.IsActivelySimulatingPierce = false;

			if (
				cast.StateInfo.HighFidelityBehavior === 2 &&
				latestTrajectory.Acceleration !== ZERO_VECTOR &&
				cast.StateInfo.HighFidelitySegmentSize !== 0
			) {
				cast.StateInfo.CancelHighResCast = false;

				if (cast.StateInfo.IsActivelyResimulating) {
					cast.Terminate();
					error(ERR_HIGH_FIDELITY_SEGMENT_PERFORMANCE);
				}

				cast.StateInfo.IsActivelyResimulating = true;

				PrintDebug(
					"Hit was registered, but recalculation is on for physics based casts. Recalculating to verify a real hit...",
				);

				const numSegmentsDecimal = rayDisplacement / cast.StateInfo.HighFidelitySegmentSize;
				const numSegmentsReal = math.floor(numSegmentsDecimal);
				//const realSegmentLength = rayDisplacement / numSegmentsReal; // Also not used...

				const timeIncrement = delta / numSegmentsReal;
				for (const segmentIndex of $range(1, numSegmentsReal)) {
					if (cast.StateInfo.CancelHighResCast) {
						cast.StateInfo.CancelHighResCast = false;
						break;
					}

					const subPosition = GetPositionAtTime(
						lastDelta + timeIncrement * segmentIndex,
						origin,
						initialVelocity,
						acceleration,
					);
					const subVelocity = GetVelocityAtTime(
						lastDelta + timeIncrement * segmentIndex,
						initialVelocity,
						acceleration,
					);
					const subRayDir = subVelocity.mul(delta);
					const subResult =
						cast.StateInfo.SphereSize === 0
							? targetWorldRoot.Raycast(subPosition, subRayDir, cast.RayInfo.Parameters)
							: targetWorldRoot.Spherecast(
									subPosition,
									cast.StateInfo.SphereSize,
									subRayDir,
									cast.RayInfo.Parameters,
							  );

					let subDisplacement = subPosition.sub(subPosition.add(subVelocity)).Magnitude;
					if (subResult) {
						subDisplacement = subPosition.sub(subResult.Position).Magnitude;

						const dbgSeg = DbgVisualizeSegment(
							new CFrame(subPosition, subPosition.add(subVelocity)),
							subDisplacement,
						);
						if (dbgSeg) dbgSeg.Color3 = new Color3(0.286275, 0.329412, 0.247059);

						if (
							cast.RayInfo.CanPierceCallback === undefined ||
							!(
								cast.RayInfo.CanPierceCallback &&
								cast.RayInfo.CanPierceCallback(
									cast,
									subResult,
									subVelocity,
									cast.RayInfo.CosmeticBulletObject,
								)
							)
						) {
							// Still a hit at high res!
							cast.StateInfo.IsActivelyResimulating = false;

							SendRayHit(cast, subResult, subVelocity, cast.RayInfo.CosmeticBulletObject);
							cast.Terminate();
							const vis = DbgVisualizeHit(new CFrame(point), false);
							if (vis) vis.Color3 = new Color3(0.0588235, 0.87451, 1);
							return;
						} else {
							// Hit piercable object.
							SendRayPierced(cast, subResult, subVelocity, cast.RayInfo.CosmeticBulletObject);
							const vis = DbgVisualizeHit(new CFrame(point), true);
							if (vis) vis.Color3 = new Color3(1, 0.113725, 0.588235);
							if (dbgSeg) dbgSeg.Color3 = new Color3(0.305882, 0.243137, 0.329412);
						}
					} else {
						const dbgSeg = DbgVisualizeSegment(
							new CFrame(subPosition, subPosition.add(subVelocity)),
							subDisplacement,
						);
						if (dbgSeg) dbgSeg.Color3 = new Color3(0.286275, 0.329412, 0.247059);
					}
				}

				cast.StateInfo.IsActivelyResimulating = false;
			} else if (cast.StateInfo.HighFidelityBehavior !== 1 && cast.StateInfo.HighFidelityBehavior !== 3) {
				cast.Terminate();
				error(`Invalid value ${cast.StateInfo.HighFidelityBehavior} for HighFidelityBehavior`);
			} else {
				PrintDebug("Hit was successful. Terminating");
				SendRayHit(cast, resultOfCast, segmentVelocity, cast.RayInfo.CosmeticBulletObject);
				cast.Terminate();
				DbgVisualizeHit(new CFrame(point), false);
				return;
			}
		} else {
			PrintDebug("Piercing function returned TRUE to pierce this part.");
			if (rayVisualization) rayVisualization.Color3 = new Color3(0.4, 0.05, 0.05); // Turn it red to signify that the cast was scrapped.
			DbgVisualizeHit(new CFrame(point), true);

			const params = cast.RayInfo.Parameters;
			const alteredParts = new Array<Instance>();
			let currentPierceTestCount = 0;
			const originalFilter = params.FilterDescendantsInstances;

			let brokeFromSolidObject = false;

			// eslint-disable-next-line no-constant-condition
			while (true) {
				if (resultOfCast.Instance.IsA("Terrain")) {
					// Pierced water?
					if (material === Enum.Material.Water) {
						cast.Terminate();
						error(
							"Do not add Water as a piercable material. If you need to pierce water, set cast.RayInfo.Parameters.IgnoreWater = true instead",
						);
					}
					warn(
						"WARNING: The pierce callback for this cast returned TRUE on Terrain! This can cause severely adverse effects.",
					);
				}

				if (
					params.FilterType === Enum.RaycastFilterType.Exclude ||
					params.FilterType === Enum.RaycastFilterType.Blacklist // Backwards compat.
				) {
					const filter = params.FilterDescendantsInstances;
					filter.push(resultOfCast!.Instance);
					alteredParts.push(resultOfCast!.Instance);
					params.FilterDescendantsInstances = filter;
				} else {
					const filter = params.FilterDescendantsInstances;
					filter.remove(filter.indexOf(resultOfCast!.Instance));
					alteredParts.push(resultOfCast!.Instance);
					params.FilterDescendantsInstances = filter;
				}

				SendRayPierced(cast, resultOfCast!, segmentVelocity, cast.RayInfo.CosmeticBulletObject);

				// List updated, let's cast again!
				resultOfCast =
					cast.StateInfo.SphereSize === 0
						? targetWorldRoot.Raycast(lastPoint, rayDir, params)
						: targetWorldRoot.Spherecast(lastPoint, cast.StateInfo.SphereSize, rayDir, params);

				if (!resultOfCast) break; // No hit.

				if (currentPierceTestCount >= MAX_PIERCE_TEST_COUNT) {
					warn(
						`WARNING: Exceeded maximum pierce test budget for a single ray segment (attempted to test the same segment ${MAX_PIERCE_TEST_COUNT} times!)`,
					);
					break;
				}
				currentPierceTestCount++;

				if (
					cast.RayInfo.CanPierceCallback(
						cast,
						resultOfCast,
						segmentVelocity,
						cast.RayInfo.CosmeticBulletObject,
					) === false
				) {
					brokeFromSolidObject = true;
					break;
				}
			}

			cast.RayInfo.Parameters.FilterDescendantsInstances = originalFilter;
			cast.StateInfo.IsActivelySimulatingPierce = false;

			if (brokeFromSolidObject) {
				PrintDebug(
					`Broke because the ray hit something solid (${tostring(
						resultOfCast!.Instance,
					)}) while testing for a pierce. Terminating the cast.`,
				);
				SendRayHit(cast, resultOfCast!, segmentVelocity, cast.RayInfo.CosmeticBulletObject);
				cast.Terminate();
				DbgVisualizeHit(new CFrame(resultOfCast!.Position), false);
				return;
			}
		}
	}
	if (cast.StateInfo.DistanceCovered >= cast.RayInfo.MaxDistance && resultOfCast) {
		cast.Terminate();
		DbgVisualizeHit(new CFrame(resultOfCast.Position), false);
	}
};

const ModifyTransformation = <T extends {}>(
	cast: ActiveCast<T>,
	velocity?: Vector3,
	acceleration?: Vector3,
	position?: Vector3,
) => {
	const trajectories = cast.StateInfo.Trajectories;
	const lastTrajectory = trajectories[trajectories.size() - 1];

	if (lastTrajectory.StartTime === cast.StateInfo.TotalRuntime) {
		lastTrajectory.Origin = position ?? lastTrajectory.Origin;
		lastTrajectory.InitialVelocity = velocity ?? lastTrajectory.InitialVelocity;
		lastTrajectory.Acceleration = acceleration ?? lastTrajectory.Acceleration;
	} else {
		lastTrajectory.EndTime = cast.StateInfo.TotalRuntime;

		const [point, velAtPoint] = GetLatestTrajectoryEndInfo(cast);
		cast.StateInfo.Trajectories.push({
			StartTime: cast.StateInfo.TotalRuntime,
			EndTime: -1,
			Origin: position ?? point,
			InitialVelocity: velocity ?? velAtPoint,
			Acceleration: acceleration ?? lastTrajectory.Acceleration,
		});
		cast.StateInfo.CancelHighResCast = true;
	}
};

export class ActiveCast<T extends {}> {
	/**
	 * UserData for a given cast. Since it starts as a blank table, it is typed such that members can possibly not exist.
	 */
	public UserData: Partial<T> = {};

	/**
	 * The given state for the ActiveCast. Used internally.
	 * @hidden
	 */
	public StateInfo: StateInfo;
	/**
	 * The given info for the current ray. Used internally.
	 * @hidden
	 */
	public RayInfo: RayInfo<T>;

	static SetRef = (reference: typeof NextCast) => {
		NextCastRef = reference;
	};

	constructor(
		public Caster: NextCast<T>,
		origin: Vector3,
		direction: Vector3,
		velocity: Vector3 | number,
		castDataPacket: CastBehavior<T>,
	) {
		assert(
			castDataPacket.HighFidelitySegmentSize > 0,
			`Cannot set HighFidelitySegmentSize <= 0! (Got ${castDataPacket.HighFidelitySegmentSize})`,
		);
		velocity = standardizeVelocity(direction, velocity);
		this.StateInfo = {
			Paused: false,
			TotalRuntime: 0,
			DistanceCovered: 0,
			HighFidelitySegmentSize: castDataPacket.HighFidelitySegmentSize,
			HighFidelityBehavior: castDataPacket.HighFidelityBehavior,
			SphereSize: castDataPacket.SphereSize,
			IsActivelySimulatingPierce: false,
			IsActivelyResimulating: false,
			CancelHighResCast: false,
			Trajectories: identity<CastTrajectory[]>([
				{
					StartTime: 0,
					EndTime: -1,
					Origin: origin,
					InitialVelocity: velocity,
					Acceleration: castDataPacket.Acceleration,
				},
			]),
		};

		this.RayInfo = {
			Parameters: castDataPacket.RaycastParams ?? new RaycastParams(),
			WorldRoot: Workspace,
			MaxDistance: castDataPacket.MaxDistance,
			CosmeticBulletObject: castDataPacket.CosmeticBulletTemplate,
			CanPierceCallback: castDataPacket.CanPierceFunction,
		};

		if (this.StateInfo.HighFidelityBehavior === 2) {
			this.StateInfo.HighFidelityBehavior = 3; // FastCast compatibility.
		}

		let usingProvider = false;
		if (castDataPacket.CosmeticBulletProvider === undefined) {
			if (this.RayInfo.CosmeticBulletObject) {
				this.RayInfo.CosmeticBulletObject = this.RayInfo.CosmeticBulletObject.Clone();
				this.RayInfo.CosmeticBulletObject.CFrame = new CFrame(origin, origin.add(direction));
				this.RayInfo.CosmeticBulletObject.Parent = castDataPacket.CosmeticBulletContainer!;
			}
		} else {
			if (PartCache.IsPartCache(castDataPacket.CosmeticBulletProvider)) {
				if (this.RayInfo.CosmeticBulletObject !== undefined) {
					warn(
						"Do not define FastCastBehavior.CosmeticBulletTemplate and FastCastBehavior.CosmeticBulletProvider at the same time! The provider will be used, and CosmeticBulletTemplate will be set to nil.",
					);
					this.RayInfo.CosmeticBulletObject = undefined;
					castDataPacket.CosmeticBulletTemplate = undefined;
				}

				this.RayInfo.CosmeticBulletObject = castDataPacket.CosmeticBulletProvider.GetPart();
				this.RayInfo.CosmeticBulletObject.CFrame = new CFrame(origin, origin.add(direction));
				usingProvider = true;
			} else {
				warn(
					"FastCastBehavior.CosmeticBulletProvider was not an instance of the PartCache module (an external/separate model)! Are you inputting an instance created via PartCache.new? If so, are you on the latest version of PartCache? Setting FastCastBehavior.CosmeticBulletProvider to nil.",
				);
				castDataPacket.CosmeticBulletProvider = undefined as unknown as PartCache;
			}
		}

		const targetContainer = usingProvider
			? castDataPacket.CosmeticBulletProvider!.CurrentCacheParent
			: castDataPacket.CosmeticBulletContainer;

		if (castDataPacket.AutoIgnoreContainer && targetContainer !== undefined) {
			const ignoreList = this.RayInfo.Parameters.FilterDescendantsInstances;
			if (!ignoreList.includes(targetContainer)) {
				ignoreList.push(targetContainer);
				this.RayInfo.Parameters.FilterDescendantsInstances = ignoreList;
			}
		}

		this.StateInfo.UpdateConnection = SIMULATION_EVENT.Connect((delta) => {
			if (this.StateInfo.Paused) return;

			PrintDebug("Casting for frame.");
			const latestTrajectory = this.StateInfo.Trajectories[this.StateInfo.Trajectories.size() - 1];
			if (
				this.StateInfo.HighFidelityBehavior === NextCastRef.HighFidelityBehavior.Always &&
				latestTrajectory.Acceleration !== ZERO_VECTOR &&
				this.StateInfo.HighFidelitySegmentSize > 0
			) {
				const timeAtStart = os.clock();

				if (this.StateInfo.IsActivelyResimulating) {
					this.Terminate();
					error(ERR_HIGH_FIDELITY_SEGMENT_PERFORMANCE);
				}

				this.StateInfo.IsActivelyResimulating = true;

				const origin = latestTrajectory.Origin;
				const initialVelocity = latestTrajectory.InitialVelocity;
				const acceleration = latestTrajectory.Acceleration;
				let totalDelta = this.StateInfo.TotalRuntime - latestTrajectory.StartTime;

				const lastPoint = GetPositionAtTime(totalDelta, origin, initialVelocity, acceleration);
				const lastVelocity = GetVelocityAtTime(totalDelta, initialVelocity, acceleration);
				const lastDelta = this.StateInfo.TotalRuntime - latestTrajectory.StartTime;

				this.StateInfo.TotalRuntime += delta;

				totalDelta = this.StateInfo.TotalRuntime - latestTrajectory.StartTime;

				const currentPoint = GetPositionAtTime(totalDelta, origin, initialVelocity, acceleration);
				const currentVelocity = GetVelocityAtTime(totalDelta, initialVelocity, acceleration);
				const totalDisplacement = currentPoint.sub(lastPoint);

				const rayDir = totalDisplacement.Unit.mul(currentVelocity.Magnitude).mul(delta);
				const targetWorldRoot = this.RayInfo.WorldRoot;
				const resultOfCast =
					this.StateInfo.SphereSize === 0
						? targetWorldRoot.Raycast(lastPoint, rayDir, this.RayInfo.Parameters)
						: targetWorldRoot.Spherecast(
								lastPoint,
								this.StateInfo.SphereSize,
								rayDir,
								this.RayInfo.Parameters,
						  );

				const point = resultOfCast?.Position ?? currentPoint;

				const rayDisplacement = point.sub(lastPoint).Magnitude;

				this.StateInfo.TotalRuntime -= delta;

				const numSegmentsDecimal = rayDisplacement / this.StateInfo.HighFidelitySegmentSize;
				const numSegmentsReal = math.floor(numSegmentsDecimal);

				// Sets any numSegmentsReal value of 0 to 1 to avoid division by 0.
				const timeIncrement = delta / (numSegmentsReal === 0 ? 1 : numSegmentsReal);

				for (const segmentIndex of $range(1, numSegmentsReal)) {
					if (getmetatable(this) === undefined) return; // Could have been disposed of.
					if (this.StateInfo.CancelHighResCast) {
						this.StateInfo.CancelHighResCast = false;
						break;
					}
					PrintDebug(`[${segmentIndex}] Subcast of time increment ${timeIncrement}`);
					SimulateCast(this, timeIncrement, true);
				}

				if (getmetatable(this) === undefined) return; // Could have been disposed of.
				this.StateInfo.IsActivelyResimulating = false;

				if (os.clock() - timeAtStart > 0.016 * 5) warn(WARN_INCREASE_SEGMENT_SIZE);
			} else SimulateCast(this, delta, false);
		});
	}

	/**
	 * Sets the velocity of the simulation.
	 * @param velocity The velocity you want the simulation to be at.
	 */
	SetVelocity(velocity: Vector3) {
		assert(getmetatable(this) === ActiveCast, ERR_NOT_INSTANCE.format("SetVelocity", "ActiveCast.new(...)"));
		assert(this.StateInfo.UpdateConnection !== undefined, ERR_OBJECT_DISPOSED);
		ModifyTransformation(this, velocity, undefined, undefined);
	}

	/**
	 * Sets the acceleration of the simulation.
	 * @param acceleration The acceleration you want the simulation to be at.
	 */
	SetAcceleration(acceleration: Vector3) {
		assert(getmetatable(this) === ActiveCast, ERR_NOT_INSTANCE.format("SetAcceleration", "ActiveCast.new(...)"));
		assert(this.StateInfo.UpdateConnection !== undefined, ERR_OBJECT_DISPOSED);
		ModifyTransformation(this, undefined, acceleration, undefined);
	}

	/**
	 * Sets the position of the simulation.
	 * @param position The position you want the simulation to be at.
	 */
	SetPosition(position: Vector3) {
		assert(getmetatable(this) === ActiveCast, ERR_NOT_INSTANCE.format("SetPosition", "ActiveCast.new(...)"));
		assert(this.StateInfo.UpdateConnection !== undefined, ERR_OBJECT_DISPOSED);
		ModifyTransformation(this, undefined, undefined, position);
	}

	/**
	 * Gets the current velocity of the simulation.
	 * @returns The current velocity
	 */
	GetVelocity() {
		assert(getmetatable(this) === ActiveCast, ERR_NOT_INSTANCE.format("GetVelocity", "ActiveCast.new(...)"));
		assert(this.StateInfo.UpdateConnection !== undefined, ERR_OBJECT_DISPOSED);
		const currentTrajectory = this.StateInfo.Trajectories[this.StateInfo.Trajectories.size() - 1];
		return GetVelocityAtTime(
			this.StateInfo.TotalRuntime - currentTrajectory.StartTime,
			currentTrajectory.InitialVelocity,
			currentTrajectory.Acceleration,
		);
	}

	/**
	 * Gets the current acceleration of the simulation.
	 * @returns The current acceleration
	 */
	GetAcceleration() {
		assert(getmetatable(this) === ActiveCast, ERR_NOT_INSTANCE.format("GetAcceleration", "ActiveCast.new(...)"));
		assert(this.StateInfo.UpdateConnection !== undefined, ERR_OBJECT_DISPOSED);
		const currentTrajectory = this.StateInfo.Trajectories[this.StateInfo.Trajectories.size() - 1];
		return currentTrajectory.Acceleration;
	}

	/**
	 * Gets the current position of the simulation.
	 * @returns The current position
	 */
	GetPosition() {
		assert(getmetatable(this) === ActiveCast, ERR_NOT_INSTANCE.format("GetPosition", "ActiveCast.new(...)"));
		assert(this.StateInfo.UpdateConnection !== undefined, ERR_OBJECT_DISPOSED);
		const currentTrajectory = this.StateInfo.Trajectories[this.StateInfo.Trajectories.size() - 1];
		return GetPositionAtTime(
			this.StateInfo.TotalRuntime - currentTrajectory.StartTime,
			currentTrajectory.Origin,
			currentTrajectory.InitialVelocity,
			currentTrajectory.Acceleration,
		);
	}

	/**
	 * Modifies the velocity of the simulation.
	 * @param velocity How much you want to adjust the simulation.
	 */
	AddVelocity(velocity: Vector3) {
		assert(getmetatable(this) === ActiveCast, ERR_NOT_INSTANCE.format("AddVelocity", "ActiveCast.new(...)"));
		assert(this.StateInfo.UpdateConnection !== undefined, ERR_OBJECT_DISPOSED);
		this.SetVelocity(this.GetVelocity().add(velocity));
	}

	/**
	 * Modifies the acceleration of the simulation.
	 * @param acceleration How much you want to adjust the simulation.
	 */
	AddAcceleration(acceleration: Vector3) {
		assert(getmetatable(this) === ActiveCast, ERR_NOT_INSTANCE.format("AddAcceleration", "ActiveCast.new(...)"));
		assert(this.StateInfo.UpdateConnection !== undefined, ERR_OBJECT_DISPOSED);
		this.SetAcceleration(this.GetAcceleration().add(acceleration));
	}

	/**
	 * Modifies the position of the simulation.
	 * @param position How much you want to adjust the simulation.
	 */
	AddPosition(position: Vector3) {
		assert(getmetatable(this) === ActiveCast, ERR_NOT_INSTANCE.format("AddPosition", "ActiveCast.new(...)"));
		assert(this.StateInfo.UpdateConnection !== undefined, ERR_OBJECT_DISPOSED);
		this.SetPosition(this.GetPosition().add(position));
	}

	/**
	 * Stops simulation, but does not cancel it.
	 */
	Pause() {
		assert(getmetatable(this) === ActiveCast, ERR_NOT_INSTANCE.format("Pause", "ActiveCast.new(...)"));
		assert(this.StateInfo.UpdateConnection !== undefined, ERR_OBJECT_DISPOSED);
		this.StateInfo.Paused = true;
	}

	/**
	 * Resumes paused simulation.
	 */
	Resume() {
		assert(getmetatable(this) === ActiveCast, ERR_NOT_INSTANCE.format("Resume", "ActiveCast.new(...)"));
		assert(this.StateInfo.UpdateConnection !== undefined, ERR_OBJECT_DISPOSED);
		this.StateInfo.Paused = false;
	}

	/**
	 * Stops any casting and renders the Active Cast useless for further operations.
	 */
	Terminate() {
		assert(getmetatable(this) === ActiveCast, ERR_NOT_INSTANCE.format("Terminate", "ActiveCast.new(...)"));
		assert(this.StateInfo.UpdateConnection !== undefined, ERR_OBJECT_DISPOSED);

		const trajectories = this.StateInfo.Trajectories;
		const latestTrajectory = trajectories[trajectories.size() - 1];
		latestTrajectory.EndTime = this.StateInfo.TotalRuntime;

		this.StateInfo.UpdateConnection.Disconnect();
		this.Caster.CastTerminating.Fire();

		this.StateInfo.UpdateConnection = undefined;

		// Jank TS hacks. FastCast has this, so I'll keep it to simulate as closely as I can.
		this.Caster = undefined as unknown as typeof this.Caster;
		this.StateInfo = undefined as unknown as typeof this.StateInfo;
		this.RayInfo = undefined as unknown as typeof this.RayInfo;
		this.UserData = undefined as unknown as typeof this.UserData;
		setmetatable(this, undefined as unknown as LuaMetatable<this>);
	}

	/**
	 * Alias for Terminate, meant for Janitor and other auto-cleanup solutions.
	 * @hidden
	 */
	Destroy() {
		this.Terminate();
	}
}
