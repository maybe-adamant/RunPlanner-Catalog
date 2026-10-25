# Adding an entry

1. **Plan the run in Run Planner** with a released planner, not a development build: an entry
   saved by a newer planner than a player has cannot be added by that player. Save it, then copy
   the saved file into a new folder here as `entries/<slug>/plan.runplanner.json`.
2. **Write `entries/<slug>/entry.json`:**

   ```json
   {
     "title": "Sub 2m Underworld",
     "description": "Argent Skull, Aspect of Persephone from Erebus to Tartarus, built on Apollo and Hera.",
     "category": "speedrun",
     "tags": ["skull", "persephone", "apollo", "hera"],
     "author": "maybe-adamant"
   }
   ```

   - The folder name is the entry's slug: lower-case letters, digits and single hyphens, at most
     64 characters. Keep it once published; players' copies are matched to it.
   - `title` is one line of at most 80 characters.
   - `description` is one line of at most 200 characters: what the plan does, such as weapon,
     route and the gods it builds around. Factual, no hype.
   - `category` is one `id` from [`categories.json`](../categories.json).
   - `tags` lists at most 8 distinct tags, each lower-case letters, digits and single hyphens of
     at most 24 characters, such as a weapon, aspect or god. A tag never repeats the category, and
     the route is shown from the plan itself, so it needs no tag.
   - `author` is one line of at most 64 characters: who made the plan.
   - No invisible formatting characters and no other fields: the route, biome count, schema
     version, URL and hash are added when the index is built.

3. **Check it locally** (optional): `scripts/check-local.sh <path-to-RunPlanner-checkout>`.
4. **Open a pull request.** The validation check loads every entry with the planner's latest
   release. The owner reviews the plan and its metadata; once merged, the publish workflow
   builds, signs and publishes the index.

## Import a folder of plans

On Windows, `scripts/catalog-import.cmd` turns a folder of saved plans into entry folders:

1. Download the `scripts` folder (or the whole repository).
2. Drag your plans folder onto `catalog-import.cmd`, or double-click it and answer the
   questions: the plans folder, a category and your name.
3. Check each new `entry.json`; the title comes from the file name and the tags and description
   from the plan, so edit them as you like. Copies of the same plan are added once.
4. On GitHub, open `entries`, choose **Add file → Upload files**, drag the new folders in and
   propose the change; or commit them in your checkout and open a pull request.

Run inside a checkout, it writes into `entries`; otherwise into a `catalog-entries` folder next
to your plans folder.

## Categories

`categories.json` is the only list of categories. Adding or renaming one is an owner change, made
in its own pull request, usually together with its first entry; the planner shows the categories in the order listed and hides any without entries.

## What players receive

The index lists each entry's metadata with its plan's URL, SHA-256 hash, route, biome count and
schema version; the plan itself is downloaded only on **Add to library**, checked against its
hash, and copied into the player's library under a new id.

`_template/` holds an example `entry.json`; folders whose name starts with `_` are never
published.
