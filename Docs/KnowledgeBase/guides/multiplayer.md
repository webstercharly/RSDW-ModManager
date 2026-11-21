# Guide: multiplayer, authority and who sees what

**Use this when** a mod must behave correctly in co-op or on a server.

## Identity and authority

| Question | Call |
|---|---|
| Is this controller mine? | `pc:IsLocalController()` (**not** `IsPlayerControlled()`, true for any human-driven pawn) |
| Am I the host (or solo)? | `pc:HasAuthority()` |
| Which character? | `pc.PlayerState:GetPlayerName():ToString()`; key files with `char_guid` too |
| All players | `UEHelpers.GetAllPlayerStates()` / `GetAllPlayers()`; Starfall's `World.players()` lists controllers with pawns |
| A remote player's id | pawn owner name or controller; Starfall's `World.playerId(owner)` |

RSDWTools learned this the hard way: a fallback using `IsPlayerControlled()` returned another player's controller and every cheat silently targeted them. Route every command to the local controller only.

## Host-only features

Most mods run on the host or solo only (NoAutoPickup, FishingSliders, Slayer, Starfall): check `HasAuthority()`, warn once if not the host, and do nothing. Some offer `AllowAsClient`. Dedicated server: FishingSliders 1.1.0's data sliders run on the server from the server's `config.txt`; per-player features do not yet.

Settings can carry a role: Mod Menu `runsOn` (`yours`, `host`, `server`, `both`) and host-only settings are refused without authority ([persistence-and-config](persistence-and-config.md)).

## Who sees what

| Thing | Visibility |
|---|---|
| Actors you spawn locally | only your machine (map icons on them too) |
| Local widgets and HUD edits | only you |
| `Client_DisplayTextNotification` through each controller | reaches the owning client **even if they lack the mod** |
| Writes to a replicated property on the host | replicate normally |
| Writes on a client | usually local only or rejected |
| Items via the normal inventory-use and server RPCs | work for remote servers without a server-side install (RSDWTools gear swap, replication verified) |

A mod that spawns shared things (Starfall's star) runs everything on the host; joined players get it through the game's own replicated actors and notifications.

## Component availability on clients

`pc.ProgressComponent` may be nil on a co-op client (CollectionLog treats nil as "try later"). The character save may not be on the PC (the Enemies tab says so). Joined players' `MapCustomizationComponent`s are constructed on the host, so a construction-time write there reaches them too (MapMarkers).

## Co-op pins and per-player state

PenguinFinder keeps a shadow of each remote player's pins (hooks `Server_NotifyPinPlaced/Cleared`), persists them, and **resends** the list a few ticks after a join so a new player gets it. It sorts candidates by distance to the player when the 99-pin cap leaves little room.

## Shared credit for multiplayer events

Starfall splits mining progress by recording which players were swinging (`PlayerMeleeAttackComponent:Multicast_SendDamageCacheData` records the attacker, the poll sees the health drop) and sharing the layer's drop between them.

## Network messaging between mods

RuneSchema's relay needs its networking pak on the server: out of reach for a standalone mod. Plain mods share nothing across machines.

## Pitfalls

- Using the first `PlayerController` found.
- Assuming a component exists on a client.
- Spawning a local actor and expecting others to see it.
- Reading another player's save.

## Seen in

[sources/RSDWTools.md](../sources/RSDWTools.md), [sources/NoAutoPickup.md](../sources/NoAutoPickup.md), [sources/Starfall.md](../sources/Starfall.md), [sources/ResourceAtlas-and-PenguinFinder.md](../sources/ResourceAtlas-and-PenguinFinder.md), [sources/FishingSliders.md](../sources/FishingSliders.md).
