-- Entry-point for luau nextcast.

local TS = require(script.TS.RuntimeLib)
local Caster = TS.import(script, script, "caster").Caster
local PartCache = TS.import(script, script, "partCache").PartCache

export type PartCacheConstructor = {
    IsPartCache: (object: any) -> boolean;
    new: (template: BasePart, numPrecreatedParts: number?, currentCacheParent: Instance?) -> PartCache;
}

export type PartCache = {
    Open: {BasePart};
    InUse: {BasePart};
    CurrentCacheParent: Instance;
    Template: BasePart;
    ExpansionSize: number;
    GetPart: (self: PartCache) -> BasePart;
    ReturnPart: (self: PartCache, part: BasePart) -> ();
    SetCacheParent: (self: PartCache, newParent: Instance) -> ();
    Expand: (self: PartCache, numParts: number?) -> ();
    Dispose: (self: PartCache) -> ();
    Destroy: (self: PartCache) -> ();
}


export type Connection<T...> = {
    Connected: boolean;
    Disconnect: (self: Connection<T...>) -> ();
    Destroy: (self: Connection<T...>) -> ();
}
export type Signal<T...> = {
    Connect: (self: Signal<T...>, callback: (T...) -> ()) -> Connection<T...>,
    Once: (self: Signal<T...>, callback: (T...) -> ()) -> Connection<T...>;
    Fire: (self: Signal<T...>, T...) -> ();
    FireDeferred: (self: Signal<T...>, T...) -> ();
    Wait: (self: Signal<T...>) -> T...;
    DisconnectAll: (self: Signal<T...>) -> ();
    Destroy: (self: Signal<T...>) -> ();
}


type CastTrajectory = {
    StartTime: number;
    EndTime: number;
    Origin: Vector3;
    InitialVelocity: Vector3;
    Acceleration: Vector3;
}
type StateInfo = {
    UpdateConnection: RBXScriptConnection?;
    HighFidelitySegmentSize: number;
    HighFidelityBehavior: number;
    Paused: boolean;
    TotalRuntime: number;
    DistanceCovered: number;
    IsActivelySimulatingPierce: boolean;
    IsActivelyResimulating: boolean;
    CancelHighResCast: boolean;
    Trajectories: {CastTrajectory};
    SphereSize: number;
}

export type ActiveCastStatic<T> = {
    new: (Caster: Caster<T>, origin: Vector3, direction: Vector3, velocity: Vector3 | number, castDataPacket: CastBehavior<T>) -> ActiveCast<T>;
}

type ActiveCast<T> = {
    Caster: Caster<T>;
    UserData: T;
    StateInfo: StateInfo;
    RayInfo: RayInfo<T>;
    SetVelocity: (self: ActiveCast<T>, velocity: Vector3) -> (),
    SetAcceleration: (self: ActiveCast<T>, acceleration: Vector3) -> ();
    SetPosition: (self: ActiveCast<T>, position: Vector3) -> ();
    GetVelocity: (self: ActiveCast<T>) -> Vector3;
    GetAcceleration: (self: ActiveCast<T>) -> Vector3;
    GetPosition: (self: ActiveCast<T>) -> Vector3;
    AddVelocity: (self: ActiveCast<T>, velocity: Vector3) -> ();
    AddAcceleration: (self: ActiveCast<T>, acceleration: Vector3) -> ();
    AddPosition: (self: ActiveCast<T>, position: Vector3) -> ();
    Pause: (self: ActiveCast<T>) -> ();
    Resume: (self: ActiveCast<T>) -> ();
    Terminate: (self: ActiveCast<T>) -> ();
    Destroy: (self: ActiveCast<T>) -> ();
}

type RayInfo<T> = {
    Parameters: RaycastParams;
    WorldRoot: WorldRoot;
    MaxDistance: number;
    CosmeticBulletObject: BasePart?;
    CanPierceCallback: ((activeCast: ActiveCast<T>, result: RaycastResult, segmentVelocity: Vector3, cosmeticBulletObject: BasePart?) -> boolean)?;
}

type HighFidelityBehavior = {
    Default: number,
    Always: number
}

type CastBehavior<T> = {
    RaycastParams: RaycastParams?;
    Acceleration: Vector3;
    MaxDistance: number;
    CanPierceFunction: ((activeCast: ActiveCast<T>, result: RaycastResult, segmentVelocity: Vector3) -> boolean)?;
    HighFidelityBehavior: number;
    HighFidelitySegmentSize: number;
    CosmeticBulletTemplate: BasePart?;
    CosmeticBulletContainer: Instance?;
    CosmeticBulletProvider: PartCache?;
    AutoIgnoreContainer: boolean;
    SphereSize: number;
}

type CasterConstructor = {
    DebugLogging: boolean,
    VisualizeCasts: boolean,
    HighFidelityBehavior: HighFidelityBehavior,
    new: <T>() -> Caster<T>,
    createSimple: <T>(castBehavior: CastBehavior<T>, raycastParams: RaycastParams?) -> Caster<T>,
    newBehavior: <T>() -> CastBehavior<T>,
}
export type Caster<T> = {
    LengthChanged: Signal<ActiveCast<T>, Vector3, Vector3, number, Vector3, BasePart?>,
    RayHit: Signal<ActiveCast<T>, RaycastResult, Vector3, BasePart?>;
    RayPierced: Signal<ActiveCast<T>, RaycastResult, Vector3, BasePart?>;
    CastTerminating: Signal;
    WorldRoot: Workspace;
    Fire: (self: Caster<T>, origin: Vector3, direction: Vector3, velocity: Vector3 | number, castDataPacket: CastBehavior<T>?) -> ActiveCast<T>;
}

local NextCast = {
    Caster = Caster :: CasterConstructor,
    PartCache = PartCache :: PartCacheConstructor
}

return NextCast