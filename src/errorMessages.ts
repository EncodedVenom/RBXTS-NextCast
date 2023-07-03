// NextCast
export const ERR_NOT_INSTANCE =
	"Cannot statically invoke method '%s' - It is an instance method. Call it on an instance of this class created via %s";

export const ERR_INVALID_TYPE = "Invalid type for parameter '%s' (Expected %s, got %s)";

export const ERR_OBJECT_DISPOSED = "This ActiveCast has been terminated. It can no longer be used.";

export const ERR_CAN_PIERCE_PERFORMANCE =
	"ERROR: The latest call to CanPierceCallback took too long to complete! This cast is going to suffer desyncs which WILL cause unexpected behavior and errors. Please fix your performance problems, or remove statements that yield (e.g. wait() calls)";

export const ERR_HIGH_FIDELITY_SEGMENT_PERFORMANCE =
	"Cascading cast lag encountered! The caster attempted to perform a high fidelity cast before the previous one completed, resulting in exponential cast lag. Consider increasing HighFidelitySegmentSize.";

export const WARN_INCREASE_SEGMENT_SIZE = "Extreme cast lag encountered! Consider increasing HighFidelitySegmentSize.";

// PartCache
export const ERR_CACHE_PARENT_INVALID =
	"Cache parent is not a descendant of Workspace! Parts should be kept where they will remain in the visible world.";

export const ERR_POSSIBLE_WRONG_PART = `Attempted to return part "%s" (%s) to the cache, but it's not in-use! Did you call this on the wrong part?`;

export const WARN_NO_PARTS_AVAILABLE = `No parts available in the cache! Creating %s new part instance(s) - this amount can be edited by changing the ExpansionSize property of the PartCache instance... (This cache now contains a grand total of %s parts.)`;
