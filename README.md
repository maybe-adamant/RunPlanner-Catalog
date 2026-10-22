# Run Planner Catalog

Template plans for [Run Planner](https://github.com/maybe-adamant/RunPlanner). Each entry is a
planned Hades II run that players browse on the planner's **Catalog** screen and copy into their
own library with **Add to library**.

This repository holds the entries and the workflow that publishes them. The planner only reads:
it downloads the signed index from this repository's `catalog` release, checks it with the
catalog public key built into the app, and downloads an entry's plan only when a player adds it.

## Layout

```text
categories.json              # the fixed set of categories an entry can belong to
entries/
  <slug>/
    entry.json               # title, description, category, tags, author
    plan.runplanner.json     # the planned run, saved from the planner
  _template/                 # an example; folders starting with _ are never published
scripts/check-local.sh       # validates every entry against a local planner checkout
.github/workflows/
  validate.yml               # pull requests: validate every entry folder (no secrets)
  publish.yml                # build, sign and publish the index
```

See [entries/README.md](entries/README.md) to add an entry.

## Publishing

`publish.yml` runs on every push to `main` that touches `entries/` or `categories.json`, and by
hand (**Run workflow**, with **dry run** on by default). It:

1. checks out the planner's latest release and builds the index with its catalog builder
   (`npm run catalog:build`), which lists every entry with its metadata, route, biome count,
   plan schema version, URL and hash, and loads each plan to refuse one the planner cannot open;
2. checks the index with the planner's own decoder;
3. stops if the published index is identical and its signature verifies; otherwise signs
   `catalog.json` with the catalog key, verifies the signature with the planner's public key, and
   replaces each `<slug>.runplanner.json` and then `catalog.json` and `catalog.json.sig` on the
   `catalog` release.

The index carries plans as saved, not compiled: a planner that adds an entry checks its hash and
opens it like any saved plan, so a planner release needs no republish. An entry saved by a newer
planner than a player has shows "Needs a newer planner" and cannot be added.

Merging a pull request that changes `entries/` publishes at once. To preview first, run the
workflow by hand on the pull request's branch with **dry run** on.

If an upload stops part way, run the workflow again: a published index that differs or whose
signature does not verify is signed afresh and replaced.

## Owner setup

1. Generate the catalog key pair (once): `npx @tauri-apps/cli signer generate -w catalog.key`.
   Keep `catalog.key` and its password private and backed up. It is separate from the event key
   and the updater key.
2. Create the `catalog-publish` environment (Settings → Environments) with a deployment branch
   policy that allows only `main`, and add the **environment** secrets
   `CATALOG_SIGNING_PRIVATE_KEY` (the contents of `catalog.key`) and
   `CATALOG_SIGNING_PRIVATE_KEY_PASSWORD` there. Repository-level secrets would be reachable
   from a workflow run on any branch. Required reviewers are optional, for approval before each
   publish.
3. Put the public key (`catalog.key.pub`, one base64 line) in the planner repository's
   `apps/planner/src-tauri/catalog-feed.pub` and release the planner. Until a release ships the
   real key the publish workflow stops, and the app shows no catalog.
