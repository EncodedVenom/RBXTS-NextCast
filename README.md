# NextCast

A raycasting module for Roblox developers with power users in mind.

## Inspiration

[FastCast](https://etithespir.it/FastCastAPIDocs/) has been one of the best and most powerful raycasting modules in roblox development. Unfortunately, the project has gone stale with no maintainers working on it as of July 2023. This module is intended to modernize FastCast as well as rewrite it entirely in [roblox-ts](https://roblox-ts.com) so that it may remain maintainable for years to come.

## Guarantees

This module will remain 1:1 backwards compatible with any FastCast API calls that are necessary. If there is a good reason to remove such functionality, such as roblox releasing breaking changes to the engine, this module will change its release version in accordance to semver as well as note any changes to default behavior in this section.

## Additions

-   SphereCasts are implemented
-   Simpler constructors for use
-   UserData types

## Examples

Below is an example of a typical gun used in the orignal module's example in typescript.

```ts
import { NextCast, PartCache, HighFidelityBehavior, ActiveCast } from "@rbxts/nextcast";

// UserData is now typed. cast.UserData will be typed as Partial<UserData> since the table is still empty on creation.
interface UserData {
	Hits: number;
}

const Tool = script.Parent as Tool; // As an example, we're assuming the script is a descendant of the actual tool.
const MouseEvent = Tool.MouseEvent as RemoteEvent; // Another example.

const BULLET_MAXDIST = 1000;
const BULLET_GRAVITY = new Vector3(0, -game.GetService("Workspace").Gravity, 0);
const DEBUG = false;
const RNG = new Random();

const CosmeticBullet = new Instance("Part");
CosmeticBullet.Material = Enum.Material.Neon;
CosmeticBullet.Color = Color3.fromRGB(0, 196, 255);
CosmeticBullet.CanCollide = false;
CosmeticBullet.Anchored = true;
CosmeticBullet.Size = new Vector3(0.2, 0.2, 2.4);

const PartProvider = new PartCache(CosmeticBullet, 100, game.GetService("Workspace")); // In real games this would be a Projectiles folder in workspace or similar, but this is fine for an example.

const Caster = new NextCast<UserData>();

const CastParams = new RaycastParams();
CastParams.IgnoreWater = true;
CastParams.FilterType = Enum.RaycastFilterType.Exclude; // Blacklist is still supported, but the use of Exclude is recommended.
CastParams.FilterDescendantsInstances = [];

const CastBehavior = NextCast.newBehavior();
CastBehavior.RaycastParams = CastParams;
CastBehavior.MaxDistance = BULLET_MAXDIST;
// Can be prefixed with NextCast, but this is the recommended way.
// CastBehavior.HighFidelityBehavior = NextCast.HighFidelityBehavior.Default is still valid.
CastBehavior.HighFidelityBehavior = HighFidelityBehavior.Default;

// CastBehavior.CosmeticBulletTemplate = CosmeticBullet // Uncomment if you just want a simple template part and aren't using PartCache
CastBehavior.CosmeticBulletProvider = CosmeticPartProvider;

CastBehavior.CosmeticBulletContainer = game.GetService("Workspace");
CastBehavior.Acceleration = BULLET_GRAVITY;
CastBehavior.AutoIgnoreContainer = false;
// NEW
CastBehavior.SphereSize = 0; // Anything above 0 will change the raycast to a spherecast. Set to 0 to preserve original behavior.

const CanRayPierce = (cast: ActiveCast<UserData>, rayResult: RaycastResult, segmentVelocity: Vector3) => {
	if (cast.UserData.Hits === undefined) cast.UserData.Hits = 1;
	cast.UserData.Hits++;
	if (cast.UserData.Hits > 3) return false;

	const hitPart = rayResult.Instance;
	if (hitPart !== undefined && hitPart.Parent !== undefined)
		hitPart.Parent.FindFirstChildOfClass("Humanoid")?.TakeDamage(10);

	// Any other logic you want to do before terminating a cast.
	return true; // Continue the simulation.
};

const Fire = (direction: Vector3) => {
	if (Tool.Parent.IsA("BackPack")) return;

	const directionalCF = new CFrame(new Vector3(), direction);

	const direction = directionalCF
		.mul(CFrame.fromOrientation(0, 0, RNG.NextNumber(0, TAU)))
		.mul(
			CFrame.fromOrientation(math.rad(RNG.NextNumber(MIN_BULLET_SPREAD_ANGLE, MAX_BULLET_SPREAD_ANGLE)), 0, 0),
		).LookVector;
	const humanoidRootPart = Tool.Parent.WaitForChild("HumanoidRootPart", 1);
	const movementSpeed = humanoidRootPart.Velocity;
	const modifiedBulletSpeed = direction.mul(BULLET_SPEED);

	CastBehavior.CanPierceFunction = CanRayPierce;

	const simBullet = Caster.Fire(
		Tool.Handle.FirePointObject.WorldPosition,
		direction,
		modifiedBulletSpeed,
		CastBehavior,
	);
};

Tool.Equipped.Connect(() => (CastParams.FilterDescendantsInstances = [Tool.Parent]));
MouseEvent.OnServerEvent.Connect((client, mousePoint) => {
	const mouseDirection = mousePoint.sub(Tool.Handle.FirePointObject.WorldPosition).Unit;
	Fire(mouseDirection);
});
```

A more recent example using some of the changes includes:

```ts
import { NextCast, HighFidelityBehavior } from "@rbxts/nextcast";

interface UserData {
	UUID: number;
}

const caster = NextCast.createSimple<UserData>({
	RaycastParams: new RaycastParams(),
	Acceleration: new Vector3(),
	MaxDistance: 10000,
	HighFidelityBehavior: HighFidelityBehavior.Default,
	HighFidelitySegmentSize: 0,
	CosmeticBulletTemplate: undefined, // This configuration does not simulate a bullet. Useful for server-side casting.
	CosmeticBulletProvider: undefined,
	CosmeticBulletContainer: undefined,
	AutoIgnoreContainer: true,
	SphereSize: 1,
});

const projectile = caster.Fire(new Vector3(), new Vector3(0, 100, 0), 100); // Notice that CastBehavior is no longer passed in, only origin, direction, and velocity are.

projectile.UserData.UUID = 12345679; // Whatever UUID system you want.
```

## Contributing

This project is open for PRs. If you want to add something to the module, you are more than welcome to, but make sure that you don't make changes to behavior expected from normal FastCast.

## Special Thanks

This project would not be possible without Eti's [FastCast module](https://etithespir.it/FastCastAPIDocs/), [roblox-ts](https://roblox-ts.com), and the entire roblox open-source community. Thank you all for supporting myself and many other developers out there.
