-- Compiled with roblox-ts v2.1.0
local TS = require(script.TS.RuntimeLib)
local exports = {}
for _k, _v in TS.import(script, script, "Caster") or {} do
	exports[_k] = _v
end
for _k, _v in TS.import(script, script, "PartCache") or {} do
	exports[_k] = _v
end
for _k, _v in TS.import(script, script, "Caster", "activeCast") or {} do
	exports[_k] = _v
end
return exports
