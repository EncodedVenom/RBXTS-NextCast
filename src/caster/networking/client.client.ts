import { Caster } from "..";
import { CastBehaviorMap, OnClientCast, Remotes } from "./shared";

const replicationCaster = new Caster();

Remotes.Client.OnEvent("Replicate", (origin, direction, velocity, serializationCode) => {
	const behavior = CastBehaviorMap.get(serializationCode);
	if (!behavior) {
		warn("Client does not have CastBehavior defined!");
		return;
	}
	OnClientCast.Fire(replicationCaster.Fire(origin, direction, velocity, behavior));
});
