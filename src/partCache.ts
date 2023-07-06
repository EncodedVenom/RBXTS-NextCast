/* eslint-disable roblox-ts/no-private-identifier */
import {
	ERR_CACHE_PARENT_INVALID,
	ERR_NOT_INSTANCE,
	ERR_POSSIBLE_WRONG_PART,
	WARN_NO_PARTS_AVAILABLE,
} from "./errorMessages";

const Workspace = game.GetService("Workspace");

const CF_REALLY_FAR_AWAY = new CFrame(0, 10e8, 0);

const assertwarn = (requirement: boolean, messageIfNotMet: string) => {
	if (!requirement) warn(messageIfNotMet);
};

const makeFromTemplate = (template: BasePart, currentCacheParent: Instance) => {
	const part = template.Clone();

	part.CFrame = CF_REALLY_FAR_AWAY;
	part.Anchored = true;
	part.Parent = currentCacheParent;
	return part;
};

export class PartCache {
	public Open = new Array<BasePart>();
	public InUse = new Array<BasePart>();
	public CurrentCacheParent: Instance;
	public Template;
	public ExpansionSize = 10;

	/**
	 * Used to verify types in ActiveCast.
	 * @hidden
	 */
	public _is_part_cache = true;

	static IsPartCache(object: Partial<PartCache>): object is PartCache {
		return object?._is_part_cache ?? false;
	}

	/**
	 * Creates a new Part Cache
	 * @param template The template projectile.
	 * @param numPrecreatedParts How many created parts should it start with [Default: 5]
	 * @param currentCacheParent The parent of these projectiles [Default: workspace]
	 */
	constructor(template: BasePart, numPrecreatedParts = 5, currentCacheParent: Instance = Workspace) {
		assert(numPrecreatedParts > 0, "PrecreatedParts can not be negative!");
		assertwarn(
			numPrecreatedParts !== 0,
			"PrecreatedParts is 0! This may have adverse effects when initially using the cache.",
		);
		assertwarn(
			template.Archivable,
			"The template's Archivable property has been set to false, which prevents it from being cloned. It will temporarily be set to true.",
		);

		const oldArchivable = template.Archivable;
		template.Archivable = true;
		const newTemplate = template.Clone();

		template.Archivable = oldArchivable;
		template = newTemplate;

		this.CurrentCacheParent = currentCacheParent;
		this.Template = template;

		for (const i of $range(1, numPrecreatedParts))
			this.Open.push(makeFromTemplate(template, this.CurrentCacheParent));
		this.Template.Parent = undefined;
	}

	/**
	 * Gets a part from the PartCache and allows it to be used for projectile simulation.
	 * @returns BasePart
	 */
	GetPart() {
		assert(PartCache.IsPartCache(this), ERR_NOT_INSTANCE.format("GetPart", "PartCache.new"));

		if (this.Open.size() === 0) {
			warn(
				WARN_NO_PARTS_AVAILABLE.format(
					this.ExpansionSize,
					tostring(this.Open.size() + this.InUse.size() + this.ExpansionSize),
				),
			);
			for (const i of $range(1, this.ExpansionSize))
				this.Open.push(makeFromTemplate(this.Template, this.CurrentCacheParent));
		}

		const part = this.Open.pop()!;
		this.InUse.push(part);
		return part;
	}

	/**
	 * Sends a part back into the cache to wait for further use.
	 * @param part The used part.
	 */
	ReturnPart(part: BasePart) {
		assert(PartCache.IsPartCache(this), ERR_NOT_INSTANCE.format("ReturnPart", "PartCache.new"));

		const index = this.InUse.indexOf(part);
		if (index === -1) error(ERR_POSSIBLE_WRONG_PART.format(part.Name, part.GetFullName()));

		this.InUse.remove(index);
		this.Open.push(part);
		part.CFrame = CF_REALLY_FAR_AWAY;
		part.Anchored = true;
	}

	/**
	 * Sets a new parent for caching.
	 * @param newParent The new parent
	 */
	SetCacheParent(newParent: Instance) {
		assert(PartCache.IsPartCache(this), ERR_NOT_INSTANCE.format("SetCacheParent", "PartCache.new"));
		assert(newParent.IsDescendantOf(Workspace), ERR_CACHE_PARENT_INVALID);

		this.CurrentCacheParent = newParent;
		this.Open.forEach((object) => (object.Parent = newParent));
		this.InUse.forEach((object) => (object.Parent = newParent));
	}

	/**
	 * Expands the cache by numParts.
	 * @param numParts The amount the cache will expand by [Default: this.ExpansionSize]
	 */
	Expand(numParts = this.ExpansionSize) {
		assert(PartCache.IsPartCache(this), ERR_NOT_INSTANCE.format("Expand", "PartCache.new"));
		for (const i of $range(1, numParts)) this.Open.push(makeFromTemplate(this.Template, this.CurrentCacheParent));
	}

	/**
	 * Once you're done with the PartCache, Dispose will remove the PartCache.
	 */
	Dispose() {
		assert(PartCache.IsPartCache(this), ERR_NOT_INSTANCE.format("Dispose", "PartCache.new"));
		this.Open.forEach((object) => object.Destroy());
		this.InUse.forEach((object) => object.Destroy());

		this.Template.Destroy();
		this.Open = {} as typeof this.Open;
		this.InUse = {} as typeof this.InUse;

		// More TS jank time!
		this.CurrentCacheParent = undefined as unknown as Instance;
		this.GetPart = undefined as unknown as typeof this.GetPart;
		this.ReturnPart = undefined as unknown as typeof this.ReturnPart;
		this.SetCacheParent = undefined as unknown as typeof this.SetCacheParent;
		this.Expand = undefined as unknown as typeof this.Expand;
		this.Dispose = undefined as unknown as typeof this.Dispose;
	}

	/**
	 * Alias for Dispose, meant for Janitor and other auto-cleanup solutions.
	 * @hidden
	 */
	Destroy() {
		this.Dispose();
	}
}
