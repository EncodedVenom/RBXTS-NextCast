-- Entry-point for luau nextcast.

local TS = require(script.TS.RuntimeLib)
local Caster = TS.import(script, script, "caster").Caster
local PartCache = TS.import(script, script, "partCache").PartCache

local NextCast = {
    Caster = Caster,
    PartCache = PartCache
}

return NextCast