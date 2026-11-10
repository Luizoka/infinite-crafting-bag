# Infinite Crafting Bag

Mod for The Binding of Isaac: Repentance+ with REPENTOGON. The Bag of Crafting stores collected ingredients in a virtual per-player inventory. The catalog previews possible results and prepares a recipe for crafting by holding Q outside the catalog.

## Controls

- **I** opens or closes the catalog. While editing the search, press Enter or Escape to finish editing first.
- **S** edits the name search; type letters, numbers or spaces and use Backspace to delete. Enter confirms the search and Escape cancels the edit.
- **Enter** on a catalog result validates and prepares its recipe without consuming ingredients. Close the catalog and hold **Q** for 1.2 seconds to craft. Release early to cancel.
- A separate overlay above the Bag of Crafting HUD shows the prepared item icon and the eight ingredient names when REPENTOGON provides and runs its crafting-table render callback. The original bag remains untouched; its native slots are empty because ingredients are stored virtually. The overlay disappears when preparation is cleared or the required stock is insufficient.
- **Up/Down** selects an item or scrolls the ingredient inventory; holding an arrow repeats after a short delay. **Page Up/Page Down** move through the item list.
- **R** cycles unlock filters (unlocked by default, all, locked). **Q** cycles quality filters (all, 0–4).
- **Tab** switches between the item list and ingredient inventory. **P** selects the next player.

The catalog considers only items discovered from the selected player's current stock. The unlock filter checks the item achievement against `PersistentGameData:Unlocked()`; items with no achievement are unlocked by default. Run restrictions are checked separately before crafting. The locked filter is not a complete list of all locked collectibles. Search uses the localized item name when available and supports ASCII case-insensitive typing.

## Recipe search

The mod counts ingredients by type and generates bounded combinations of eight in sorted order, so permutations are evaluated once. Each combination is passed to REPENTOGON's `EntityPlayer.CalculateBagOfCraftingOutput`; the returned collectible ID identifies the entry, and the first discovered recipe is kept. Browsing and searching do not consume ingredients or grant collectibles.

The search runs only while the catalog is open. It processes at most 128 traversal steps and 8 native recipe calculations per update, and stops after 50,000 combinations. The display distinguishes complete, in-progress, limited and error states, and reports evaluated combinations out of the total. A single current-stock/context cache is reused when reopening; it is discarded when the stock, seed, player, room, achievement or observed item-pool state changes. A bounded sprite cache holds up to 64 icons.

The native function calculates an output for one combination; it does not provide a reverse index of all recipes. The catalog is therefore incomplete while searching or after reaching the limit. Custom mods may change pools or availability in ways not covered by the observed callbacks; results are previews and require in-game verification. The native API documentation does not specify all side effects or detail every pool/unlock interaction, so those behaviors should be verified with the installed REPENTOGON version. No tables or assets from External Item Descriptions are required.

## Crafting and limitations

The mod does not load the native Bag of Crafting. REPENTOGON documents callbacks for adding pickups to the bag, but no documented callback identified here proves that the native bag finished crafting a specific recipe. The mod instead suppresses the player's drop action while Q is held for a prepared recipe and controls the hold and delivery itself. It refuses to craft if the native bag contains ingredients. The prepared recipe is temporary and must be selected again after Continue; the inventory remains persistent.

Preparation checks the player, unlock, stock and native recipe output. Run availability and active-slot restrictions are checked at delivery, so they do not prevent selecting an otherwise valid recipe. Before delivery the mod checks all of these conditions again, consumes eight ingredients and saves the resulting stock. It then calls `EntityPlayer:AddCollectible` once and observes `MC_POST_ADD_COLLECTIBLE`. A failed save before delivery rolls back the in-memory consumption. `AddCollectible` and SaveData do not form a transaction with the game's save. Other mods can cancel or change item delivery, override input callbacks, or have side effects; after the delivery call an uncertain outcome is logged and ingredients are not automatically refunded to avoid duplication. Item acquisition callbacks run, but the native Bag of Crafting animation and special crafting interactions are not reproduced. To avoid replacing an equipped active item, active collectibles require an empty primary active slot. These interactions require testing in Isaac.

The installed `[RGON] (BETA) Tainted Cain Rework` implements its own crafting inventory and its own collectible delivery. The two crafting flows are independent; their joint behavior has not been validated and no integration is provided. Test this mod with the rework disabled first.

## Persistence

The inventory remains stored via the existing `Mod:SaveData` flow. `[ICB DEBUG]` logs include save/load diagnostics. Data that exists but is invalid is retained rather than overwritten.

## Tests

With Lua 5.3 or later, run from the project root:

```
lua tests/catalog_spec.lua
lua tests/catalog_ui_spec.lua
lua tests/storage_catalog_spec.lua
lua tests/crafting_spec.lua
```

The tests mock the Isaac API and native calculator; they do not verify game rendering or real recipe results.

## In-game validation

1. Start or continue a Tainted Cain run, collect at least eight ingredients, and press **I**.
2. Check the ingredient inventory with **Tab**, then return to the list. Verify the progress changes to complete or explicitly reports an incomplete search.
3. Navigate the results and compare an eight-ingredient recipe and its output with the game's native Bag of Crafting behavior. Search for a displayed item and exercise both filters.
4. Select an item with Enter. Check the stock does not change, close with I, hold Q briefly and release; verify nothing is consumed or granted.
5. Hold Q for 1.2 seconds and watch the progress bar. Verify exactly eight ingredients are removed and one item is granted. Keep holding and confirm no second item appears.
6. Select another recipe, craft it, save and Continue. Verify the remaining stock; prepare the recipe again after Continue. Check active items with an empty primary slot and test other mods separately.

Crafting, progress display, input suppression and persistence after crafting require validation in Isaac.
