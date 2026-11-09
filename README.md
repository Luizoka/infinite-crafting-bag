# Infinite Crafting Bag

Mod for The Binding of Isaac: Repentance+ with REPENTOGON. The Bag of Crafting stores collected ingredients in a virtual per-player inventory. The catalog previews possible results; it does not craft items or consume ingredients.

## Controls

- **I** opens or closes the catalog. While editing the search, press Enter or Escape to finish editing first.
- **Enter** edits the name search; type letters, numbers or spaces and use Backspace to delete. Enter confirms the search and Escape cancels the edit.
- **Up/Down** selects an item or scrolls the ingredient inventory; holding an arrow repeats after a short delay. **Page Up/Page Down** move through the item list.
- **R** cycles item availability filters (all, unlocked, locked). **Q** cycles quality filters (all, 0–4).
- **Tab** switches between the item list and ingredient inventory. **P** selects the next player.

The catalog considers only items discovered from the selected player's current stock. Availability refers to `ItemConfig:IsAvailable()`; the locked filter is not a complete list of all locked collectibles. Search uses the localized item name when available and supports ASCII case-insensitive typing.

## Recipe search

The mod counts ingredients by type and generates bounded combinations of eight in sorted order, so permutations are evaluated once. Each combination is passed to REPENTOGON's `EntityPlayer.CalculateBagOfCraftingOutput`; the returned collectible ID identifies the entry, and the first discovered recipe is kept. No collectible is granted and the stock is not modified.

The search runs only while the catalog is open. It processes at most 128 traversal steps and 8 native recipe calculations per update, and stops after 50,000 combinations. The display distinguishes complete, in-progress, limited and error states, and reports evaluated combinations out of the total. A single current-stock/context cache is reused when reopening; it is discarded when the stock, seed, player, room, achievement or observed item-pool state changes. A bounded sprite cache holds up to 64 icons.

The native function calculates an output for one combination; it does not provide a reverse index of all recipes. The catalog is therefore incomplete while searching or after reaching the limit. Custom mods may change pools or availability in ways not covered by the observed callbacks; results are previews and require in-game verification. The native API documentation does not specify all side effects or detail every pool/unlock interaction, so those behaviors should be verified with the installed REPENTOGON version. No tables or assets from External Item Descriptions are required.

## Persistence

The inventory remains stored via the existing `Mod:SaveData` flow. `[ICB DEBUG]` logs include save/load diagnostics. Data that exists but is invalid is retained rather than overwritten.

## Tests

With Lua 5.3 or later, run from the project root:

```
lua tests/catalog_spec.lua
lua tests/catalog_ui_spec.lua
lua tests/storage_catalog_spec.lua
```

The tests mock the Isaac API and native calculator; they do not verify game rendering or real recipe results.

## In-game validation

1. Start or continue a Tainted Cain run, collect at least eight ingredients, and press **I**.
2. Check the ingredient inventory with **Tab**, then return to the list. Verify the progress changes to complete or explicitly reports an incomplete search.
3. Navigate the results and compare an eight-ingredient recipe and its output with the game's native Bag of Crafting behavior. Search for a displayed item and exercise both filters.
4. Close the catalog and verify movement, shooting and item controls resume. Confirm that opening and selecting entries did not consume ingredients or give an item.
5. Collect another ingredient and check that the search restarts. Save, exit and continue to verify the stock and catalog rebuild.

The visual interface, native results, input handling and persistence regression still need validation in Isaac.
