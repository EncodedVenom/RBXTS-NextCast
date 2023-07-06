/* eslint-disable roblox-ts/no-private-identifier */
import { ActiveCast } from "./activeCast";
import { PartCache } from "../_PartCache";
import { Signal } from "../signal";

const Workspace = game.GetService("Workspace");

export enum HighFidelityBehavior {
	/** NextCast will behave as it normally does, and use a segment length based on delta time. */
	Default = 1,
	/** NextCast will always enforce that the segment length is as close to HighFidelitySegmentSize no matter what. */
	Always = 3,
}

export type CastBehavior<T extends {}> = {
	/** RaycastParams passed into the raycasting functions. */
	RaycastParams?: RaycastParams;
	/** How gravity, wind, and other forces should affect the trajectory. */
	Acceleration: Vector3;
	/** How far a bullet can go before auto-terminating. Defaults to 1000 */
	MaxDistance: number;
	/** A function that determines if a bullet is able to go through a part or not. Leave this undefined if you do not wish to use it. */
	CanPierceFunction?: (activeCast: ActiveCast<T>, result: RaycastResult, segmentVelocity: Vector3) => boolean;
	/** How NextCast should enforce cast segment lengths. In most cases, HighFidelityBehavior.Default will work, but if you want to have specific segment sizes, HighFidelityBehavior.Always will enforce this. */
	HighFidelityBehavior: HighFidelityBehavior;
	/** Used in conjunction with HighFidelityBehavior.Always. Defines how big your segment sizes are. Can cause extreme lag if you are not careful. Defaults to 0.5 */
	HighFidelitySegmentSize: number;
	/** A template part for casting. Use CosmeticBulletContainer in conjunction with this. */
	CosmeticBulletTemplate?: BasePart;
	/** Used in conjunction with CosmeticBulletTemplate. Defines the parent of the bullet. */
	CosmeticBulletContainer?: Instance;

	/** Uses PartCache in lieu of CosmeticBulletTemplate and CosmeticBulletContainer. */
	CosmeticBulletProvider?: PartCache;

	/** Auto ignores the container for bullets. */
	AutoIgnoreContainer: boolean;
	// Additions
	/** When set above 0, uses WorldRoot.Spherecast instead of WorldRoot.Raycast */
	SphereSize: number;
};

const DEFAULT_BEHAVIOR = identity<CastBehavior<{}>>({
	RaycastParams: undefined,
	Acceleration: new Vector3(),
	MaxDistance: 1000,
	HighFidelityBehavior: HighFidelityBehavior.Default,
	HighFidelitySegmentSize: 0.5,
	AutoIgnoreContainer: true,

	CosmeticBulletTemplate: undefined,
	CosmeticBulletProvider: undefined,
	CosmeticBulletContainer: undefined,
	CanPierceFunction: undefined,

	SphereSize: 0,
});

export class Caster<T extends {}> {
	/** Makes NextCast print verbose logs if enabled. */
	static DebugLogging = false;
	/** Makes NextCast show a representation of the casts if enabled */
	static VisualizeCasts = false;
	/**
	 * Kept for compatibility. Use the exported enum when possible.
	 * @hidden */
	static HighFidelityBehavior = HighFidelityBehavior;
	/**
	 * Better method to set a static reference.
	 * @hidden
	 */
	private static _sentStaticReference = false;

	constructor() {
		if (!Caster._sentStaticReference) {
			ActiveCast.SetRef(Caster);
			Caster._sentStaticReference = true;
		}
	}

	/**
	 * Creates a new NextCast with most of the boilerplate handled.
	 * @param castBehavior NextCast cast behavior.
	 * @param raycastParams Roblox raycast params.
	 * @returns
	 */
	public static createSimple<T extends {} = {}>(castBehavior: CastBehavior<T>, raycastParams?: RaycastParams) {
		castBehavior.RaycastParams = raycastParams;
		const caster = new Caster<T>();
		caster.defaultBehavior = castBehavior;
		return caster;
	}

	/**
	 * Clones the default behavior and returns it.
	 * @returns CastBehavior<T>
	 */
	public static newBehavior<U extends {}>() {
		return table.clone(DEFAULT_BEHAVIOR) as CastBehavior<U>;
	}

	/**
	 * Used internally with createSimple to allow CastBehavior to be stored in memory.
	 * @hidden */
	private defaultBehavior = DEFAULT_BEHAVIOR as CastBehavior<T>;

	/** Fires when the bullet updates. */
	public LengthChanged = new Signal<
		[
			cast: ActiveCast<T>,
			lastPoint: Vector3,
			rayDir: Vector3,
			rayDisplacement: number,
			segmentVelocity: Vector3,
			cosmeticBulletObject?: BasePart,
		]
	>();
	/** Fires when the bullet hits something. */
	public RayHit = new Signal<
		[cast: ActiveCast<T>, resultOfCast: RaycastResult, segmentVelocity: Vector3, cosmeticBulletObject?: BasePart]
	>();
	/** Fires when the bullet pierces something. Useful if you want to add reflection or other fun behavior. */
	public RayPierced = new Signal<
		[cast: ActiveCast<T>, resultOfCast: RaycastResult, segmentVelocity: Vector3, cosmeticBulletObject?: BasePart]
	>();
	/** Fires when the bullet is done casting. */
	public CastTerminating = new Signal<[]>();
	public WorldRoot = Workspace;

	/**
	 * Fires a ray from this Caster.
	 * This actively simulated ray (or "bullet") is represented as an object referred to as an ActiveCast.
	 * The velocity parameter can either be a number or a Vector3.
	 * If it is a number, it will be in the same direction as direction and effectively represents a speed for your cast in studs/sec.
	 * @param origin Where the bullet originates
	 * @param direction Where the bullet is going
	 * @param velocity How fast the bullet is going
	 * @param castDataPacket How NextCast behavior should affect the bullet
	 * @returns
	 */
	Fire(
		origin: Vector3,
		direction: Vector3,
		velocity: Vector3 | number,
		castDataPacket = this.defaultBehavior,
	): ActiveCast<T> {
		const cast = new ActiveCast<T>(this, origin, direction, velocity, castDataPacket);
		return cast;
	}
}
