-- Compiled with roblox-ts v2.1.0
-- NextCast
local ERR_NOT_INSTANCE = "Cannot statically invoke method '%s' - It is an instance method. Call it on an instance of this class created via %s"
local ERR_INVALID_TYPE = "Invalid type for parameter '%s' (Expected %s, got %s)"
local ERR_OBJECT_DISPOSED = "This ActiveCast has been terminated. It can no longer be used."
local ERR_CAN_PIERCE_PERFORMANCE = "ERROR: The latest call to CanPierceCallback took too long to complete! This cast is going to suffer desyncs which WILL cause unexpected behavior and errors. Please fix your performance problems, or remove statements that yield (e.g. wait() calls)"
local ERR_HIGH_FIDELITY_SEGMENT_PERFORMANCE = "Cascading cast lag encountered! The caster attempted to perform a high fidelity cast before the previous one completed, resulting in exponential cast lag. Consider increasing HighFidelitySegmentSize."
local WARN_INCREASE_SEGMENT_SIZE = "Extreme cast lag encountered! Consider increasing HighFidelitySegmentSize."
-- PartCache
local ERR_CACHE_PARENT_INVALID = "Cache parent is not a descendant of Workspace! Parts should be kept where they will remain in the visible world."
local ERR_POSSIBLE_WRONG_PART = [[Attempted to return part "%s" (%s) to the cache, but it's not in-use! Did you call this on the wrong part?]]
local WARN_NO_PARTS_AVAILABLE = "No parts available in the cache! Creating %s new part instance(s) - this amount can be edited by changing the ExpansionSize property of the PartCache instance... (This cache now contains a grand total of %s parts.)"
return {
	ERR_NOT_INSTANCE = ERR_NOT_INSTANCE,
	ERR_INVALID_TYPE = ERR_INVALID_TYPE,
	ERR_OBJECT_DISPOSED = ERR_OBJECT_DISPOSED,
	ERR_CAN_PIERCE_PERFORMANCE = ERR_CAN_PIERCE_PERFORMANCE,
	ERR_HIGH_FIDELITY_SEGMENT_PERFORMANCE = ERR_HIGH_FIDELITY_SEGMENT_PERFORMANCE,
	WARN_INCREASE_SEGMENT_SIZE = WARN_INCREASE_SEGMENT_SIZE,
	ERR_CACHE_PARENT_INVALID = ERR_CACHE_PARENT_INVALID,
	ERR_POSSIBLE_WRONG_PART = ERR_POSSIBLE_WRONG_PART,
	WARN_NO_PARTS_AVAILABLE = WARN_NO_PARTS_AVAILABLE,
}
