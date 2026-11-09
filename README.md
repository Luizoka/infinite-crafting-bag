# Infinite Crafting Bag

Mod for The Binding of Isaac: Repentance+ with REPENTOGON. The Bag of Crafting stores collected ingredients in a virtual per-player inventory. The catalog previews possible results. Crafting from the virtual inventory is currently unavailable.

## Controls

- **I** opens or closes the catalog. While editing the search, press Enter or Escape to finish editing first.
- **S** edits the name search; type letters, numbers or spaces and use Backspace to delete. Enter confirms the search and Escape cancels the edit.
- **Enter** on a catalog result revalidates its recipe and reports that native crafting is unavailable. It does not consume ingredients or grant an item.
- **Up/Down** selects an item or scrolls the ingredient inventory; holding an arrow repeats after a short delay. **Page Up/Page Down** move through the item list.
- **R** cycles unlock filters (unlocked by default, all, locked). **Q** cycles quality filters (all, 0–4).
- **Tab** switches between the item list and ingredient inventory. **P** selects the next player.

The catalog considers only items discovered from the selected player's current stock. The unlock filter checks the item achievement against `PersistentGameData:Unlocked()`; items with no achievement are unlocked by default. Run restrictions are checked separately before crafting. The locked filter is not a complete list of all locked collectibles. Search uses the localized item name when available and supports ASCII case-insensitive typing.

## Recipe search

The mod counts ingredients by type and generates bounded combinations of eight in sorted order, so permutations are evaluated once. Each combination is passed to REPENTOGON's `EntityPlayer.CalculateBagOfCraftingOutput`; the returned collectible ID identifies the entry, and the first discovered recipe is kept. Browsing and searching do not consume ingredients or grant collectibles.

The search runs only while the catalog is open. It processes at most 128 traversal steps and 8 native recipe calculations per update, and stops after 50,000 combinations. The display distinguishes complete, in-progress, limited and error states, and reports evaluated combinations out of the total. A single current-stock/context cache is reused when reopening; it is discarded when the stock, seed, player, room, achievement or observed item-pool state changes. A bounded sprite cache holds up to 64 icons.

The native function calculates an output for one combination; it does not provide a reverse index of all recipes. The catalog is therefore incomplete while searching or after reaching the limit. Custom mods may change pools or availability in ways not covered by the observed callbacks; results are previews and require in-game verification. The native API documentation does not specify all side effects or detail every pool/unlock interaction, so those behaviors should be verified with the installed REPENTOGON version. No tables or assets from External Item Descriptions are required.

## Crafting and limitations

The mod does not place selected ingredients into the native bag or grant items from the catalog. The capture callback clears the native bag after a confirmed ingredient pickup. REPENTOGON documents callbacks for adding pickups to the bag, but no documented callback identified here proves that the native Bag of Crafting finished crafting a specific recipe. A cleared bag or a generic collectible callback alone is not proof. Loading eight virtual ingredients into the native bag without reliable confirmation would allow a free craft or incorrect debits, so the integration is disabled pending investigation and in-game verification.

Pressing Enter checks the player, stock and native recipe result but leaves the bag and inventory untouched. Holding Q after selecting a catalog result will not craft that item. The previous direct `AddCollectible` path has been removed. SaveData and the game state are separate operations and cannot guarantee atomic recovery across interruptions.

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
4. Press Enter repeatedly on a result. Check that the message says native crafting is unavailable, the stock remains unchanged and no item is granted. Close the catalog with I.
5. Save, exit and Continue; verify the remaining ingredients. Close the catalog and verify normal controls resume. Check the scroll indicator at the beginning and end of a filtered list and at smaller screen resolutions.

Native Q crafting from the virtual inventory is not available to test yet. The updated interface and these regressions still require validation in Isaac.
