import Net from "@rbxts/net";
import { CastBehavior } from "..";
import { Signal } from "../../signal";
import { ActiveCast } from "../activeCast";

export const Remotes = Net.Definitions.Create({
	Replicate:
		Net.Definitions.ServerToClientEvent<
			[origin: Vector3, direction: Vector3, velocity: Vector3 | number, serializationCode: string]
		>(),
});

export const CastBehaviorMap = new Map<string, CastBehavior<{}>>();

/** @client */
export const OnClientCast = new Signal<ActiveCast<{}>>();
