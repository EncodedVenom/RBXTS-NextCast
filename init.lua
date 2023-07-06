-- Entry-point for luau nextcast.

local TS = require(script.TS.RuntimeLib)
local Caster = TS.import(script, script, "Caster").Caster
local PartCache = TS.import(script, script, "PartCache").PartCache

local NextCast = {
    Caster = Caster,
    PartCache = PartCache
}

return NextCast