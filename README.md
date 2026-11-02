# Petal for WoW Forever

Summons your pets automatically, with different pets for different places.

Petal 2.0 is the Forever version of retail PETAL (a rewrite).

## Open it

`/petal`, or bind **Open Petal** under Key Bindings > Petal.

## Pages (side tabs)

- **Pets**: your collection. Tick the pets Petal can summon. Select a pet to see its model and description, choose the places it appears in, summon or dismiss it, favorite it, or unwrap a new pet.
- **Places**: your current place and a grid of ticked pets by place (Cities, Inns & towns, Outdoors, Dungeons, Raids, Battlegrounds). A place with no pets uses all ticked pets.
- **Options**: automatic summoning, keep pets you summon yourself, wait after you dismiss a pet, switch pets from time to time, an optional chat message, and the **Summon another pet** key.
- **Saved sets**: save, load, overwrite and delete sets, and share them as codes (`PETALF1`; retail `PETAL1` codes also import: open world becomes Outdoors, neighborhood is dropped).

## When Petal waits

Petal doesn't summon while you are in combat, mounted, on a flight path, eating or drinking, sitting at a campfire ("Welcoming Campfire" aura), stealthed, shapeshifted (travel/combat forms), or casting. After a mount, flight or loading screen, the same pet comes back.

## How Forever's collection is read

Pets in Forever are account-wide, with no battles or levels, and the Classic-style journal lists only collected pets. Petal remembers pets by **species**, so arrangements and codes work across characters and accounts. It finds them in this order:

1. `C_PetJournal.GetOwnedPetIDs()`
2. A walk through the journal index. Your journal filters are widened for the walk and then restored exactly.
3. `GetCompanionInfo("CRITTER")`

Pets of the other faction are hidden, as they are in Blizzard's journal.

`/petal probe` records what the client's pet API returns into `PETALDB.probe`. Use it if a pet is missing.

## Commands

`/petal`, `/petal next`, `/petal summon`, `/petal dismiss`, `/petal on`, `/petal off`, `/petal status`, `/petal probe`, `/petal debug`

## Tests

From this folder: `lua5.1 tests/Smoke.lua` and `lua5.1 tests/Discovery.lua`.
