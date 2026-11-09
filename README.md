# Infinite Crafting Bag

Mod for The Binding of Isaac: Repentance+ with REPENTOGON. The Bag of Crafting stores collected ingredients in a virtual per-player inventory. The catalog previews possible results and can craft a selected item after confirmation.

## Controls

- **I** opens or closes the catalog. While editing the search, press Enter or Escape to finish editing first.
- **S** edits the name search; type letters, numbers or spaces and use Backspace to delete. Enter confirms the search and Escape cancels the edit.
- **Enter** on a catalog result opens the crafting confirmation. Enter confirms it; Escape cancels without consuming ingredients.
- **Up/Down** selects an item or scrolls the ingredient inventory; holding an arrow repeats after a short delay. **Page Up/Page Down** move through the item list.
- **R** cycles unlock filters (unlocked by default, all, locked). **Q** cycles quality filters (all, 0–4).
- **Tab** switches between the item list and ingredient inventory. **P** selects the next player.

The catalog considers only items discovered from the selected player's current stock. The unlock filter checks the item achievement against `PersistentGameData:Unlocked()`; items with no achievement are unlocked by default. Run restrictions are checked separately before crafting. The locked filter is not a complete list of all locked collectibles. Search uses the localized item name when available and supports ASCII case-insensitive typing.

## Recipe search

The mod counts ingredients by type and generates bounded combinations of eight in sorted order, so permutations are evaluated once. Each combination is passed to REPENTOGON's `EntityPlayer.CalculateBagOfCraftingOutput`; the returned collectible ID identifies the entry, and the first discovered recipe is kept. Browsing and searching do not consume ingredients or grant collectibles.

The search runs only while the catalog is open. It processes at most 128 traversal steps and 8 native recipe calculations per update, and stops after 50,000 combinations. The display distinguishes complete, in-progress, limited and error states, and reports evaluated combinations out of the total. A single current-stock/context cache is reused when reopening; it is discarded when the stock, seed, player, room, achievement or observed item-pool state changes. A bounded sprite cache holds up to 64 icons.

The native function calculates an output for one combination; it does not provide a reverse index of all recipes. The catalog is therefore incomplete while searching or after reaching the limit. Custom mods may change pools or availability in ways not covered by the observed callbacks; results are previews and require in-game verification. The native API documentation does not specify all side effects or detail every pool/unlock interaction, so those behaviors should be verified with the installed REPENTOGON version. No tables or assets from External Item Descriptions are required.

## Crafting and limitations

Confirmation checks that the selected player still exists, the stock has not changed, all eight ingredients are present, the collectible is available, and the native recipe calculator still returns that collectible. Active items require an empty primary active slot; the mod does not replace an equipped active item. The selected player must pass REPENTOGON's `CanAddCollectibleToInventory` check.

The eight ingredients are removed together and the resulting stock is saved before `EntityPlayer:AddCollectible` is called once. The `MC_POST_ADD_COLLECTIBLE` callback is used to observe delivery. `AddCollectible` is a direct grant, not the native Bag of Crafting animation or full use sequence; callbacks and interactions with other mods can therefore differ. In particular, another mod can cancel or change a grant. The API returns no delivery status: if the call fails, is cancelled or changed after invocation, the outcome may be ambiguous. The mod keeps the debit and logs `[ICB CRAFT]` rather than refunding automatically and risking duplication. A save failure before delivery rolls the in-memory debit back. SaveData and Isaac's game save are separate operations: interruption between them can leave item and ingredient state inconsistent.

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
4. Press Enter on an available item, then Escape; confirm neither the stock nor the item inventory changed. Reopen the confirmation and press Enter once. Verify the item is received exactly once and the stock decreases by eight, including repeated ingredient types.
5. Hold Enter and check it does not craft again. Verify the list rebuilds and the remaining stock is correct. Repeat with another item and test an active item with an empty primary slot.
6. Save, exit and Continue; verify the remaining ingredients. Close the catalog and verify normal controls resume. Repeat with two players and, separately, with other mods enabled.

Crafting, direct item delivery, the updated interface and persistence after crafting still need validation in Isaac.
