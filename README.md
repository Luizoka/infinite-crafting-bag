# Infinite Crafting Bag

Mod for Repentance+ with REPENTOGON. This first delivery implements ingredient storage and a small diagnostic inventory overlay. Recipe discovery and crafting are not implemented yet.

## Phase 1 strategy

`MC_TRY_ADD_TO_BAG_OF_CRAFTING` supplies the effective ingredient ID list for the pickup, which may contain multiple IDs or be empty. The mod allows the game's normal collection behavior to proceed. `MC_POST_ADD_TO_BAG_OF_CRAFTING` confirms a successful addition; only then does the mod append those IDs to that player's external inventory, clear the native Bag of Crafting through `SetBagOfCraftingContent({})`, and save.

The native bag therefore acts as a short-lived transfer buffer. It is cleared after each confirmed pickup, before it can accumulate to eight ingredients and trigger the native full-bag behavior. The mod does not use the physical pickup variant as a substitute for the effective ingredient IDs. It never extends the native bag array.

This callback sequence is documented by REPENTOGON, but it has not yet been exercised in Isaac. In particular, verify in-game that clearing the bag inside `MC_POST_ADD_TO_BAG_OF_CRAFTING` happens after all native pickup effects and does not interfere with collection animation or other mods.

## Controls and storage

- The total ingredient count is shown in the HUD.
- Press **I** to open or close the per-player breakdown (up to ten ingredient types are displayed at once).
- Ingredient IDs are stored separately per REPENTOGON player index.
- The inventory is written with `Mod:SaveData` after each confirmed pickup, on room changes, and on an exit where `ShouldSave` is true. It is restored in `MC_POST_GAME_STARTED` when `IsContinued` is true. Writes before the run starts and empty writes during initialization are skipped.
- `[ICB DEBUG]` logs report callback order, player indexes/controllers, `HasData`, JSON decode status, inventory totals, save payload size, and a `diagnostic` marker (`persistencia` / `12345`) stored alongside the inventory. Missing save data allows subsequent pickups to be saved. Invalid data, including legacy data without a run seed, is preserved and blocks writes until it can be investigated.

## In-game acceptance check

1. Start a run as Tainted Cain and pick up a normal ingredient. Confirm the count increases by the number of effective ingredients shown in the breakdown.
2. Collect at least ten ingredients. Confirm each pickup is collected, the total exceeds eight, and the native bag does not craft automatically or repel pickups because it is full.
3. Save and exit, continue the same run, and confirm the count and ingredient types remain.
4. Start a fresh run and confirm its count starts at zero.
5. In co-op, if available, collect different ingredients with each player and confirm their displayed counts remain separate.

If pickup collection fails after the eighth ingredient, disable this build and report the game/REPENTOGON versions and log. The first fallback to investigate is moving the transfer from the post-add callback to a confirmed pickup-state transition, since returning `false` from the pre-add callback explicitly repels the pickup according to the REPENTOGON docs.

## Current limits

- The Isaac runtime is not available in this workspace, so Lua callback execution, HUD placement, pickup handling, and save/continue behavior still require manual validation in-game.
- Recipe catalog, recipe selection, and crafting are not part of this delivery.
- Ingredient count is practically bounded by save-file size and runtime memory.
