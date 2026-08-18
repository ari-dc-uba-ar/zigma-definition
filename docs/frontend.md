# How the example frontend is produced

The page is **not** HTML/JS emitted from Zig at compile time. `src/frontend/` is a
generic client: it knows `zigma`, `zigma_json`, and a `system` module
(`type_defs` + `entity_defs`). The aida example is a consumer package:
`examples/aida/build.zig` calls `addAppFromDep` with `src/system.zig` as
`system`. The table is built **at runtime** from entity Infos that live in the
WASM module.

How to run it: [run-example.md](run-example.md). Build steps: [build.md](build.md).

```
examples/aida/src/aida.zig     entity Defs (comptime)
examples/aida/src/system.zig   re-exports Defs + optional seeds
        │                      addAppFromDep imports this as `system`
        ▼
src/frontend/main.zig          WASM: catalog JSON + typed row builder
src/json.zig                   stringifyEntityCatalog / stringifyRecord
        │
        ▼  cd examples/aida && zig build frontend
examples/aida/zig-out/frontend/
  frontend.wasm                compiled from main.zig
  index.html                   copied as-is (empty shell)
  main.js                      copied as-is
        │
        ▼  browser loads the page
main.js reads schema_ptr/schema_len
        │
        ▼
nav + one table from entity.fields
GET/POST/PUT http://localhost:8080/{entity}
```

## What the build copies vs compiles

`addAppFromDep` (from the example’s `build.zig`) writes `zig-out/frontend/`
under `examples/aida/`. Two different things happen:

1. **Compile** `src/frontend/main.zig` for `wasm32-freestanding` (`optimize = .small`,
   `entry = .disabled`, `rdynamic`, exported memory). The module imports `zigma`,
   `zigma_json`, and `system`. For the example, `system` is `src/system.zig`. The
   artifact is `frontend.wasm`. Native HTTP uses a **separate** copy of those
   modules (host target, not wasm).
2. **Copy** `src/frontend/index.html` and `src/frontend/main.js` unchanged. There is no
   template step and no HTML generator.

`index.html` is a shell: an empty nav, a title, an empty table (`thead` / `tbody`
/ `tfoot`), a status line, and `<script src="main.js">`. Column headers, inputs,
and rows are created later in the browser.

`cd examples/aida && zig build` and `zig build frontend` both perform this
install. The library `zig build` at the repo root does not. Generators
under `src/` (`json.zig`, `http/`, `frontend/`) **are** in the published package so a consumer
can call `addAppFromDep`. Tests and `docs/` are not.

## What WASM exposes

On first read of `schema_ptr` / `schema_len`, WASM fills a buffer with
`stringifyEntityCatalog(type_defs, entity_defs)`. For every entity that walks
`completeEntity` and writes one JSON object:

- `name`
- `pk`, `uks`, `fks`
- `fields`: `{ name, label, type, storage }` per field. `type` is the domain
  type name; `storage` is the Zig shape (`text`, `integer`, `boolean`, `date`,
  `object`). A struct of three integers is `date` (year, month, day in field
  order).

That catalog is the only schema the page uses. JS never imports a concrete
system.

The other exports are a packed-string row builder, not UI:

| Export | Role |
| --- | --- |
| `schema_ptr` / `schema_len` | catalog JSON |
| `input_ptr` / `input_len` | packed field strings from the page |
| `lengths_ptr` | per-field lengths into `input_buf` |
| `build_row(entity_index)` | parse into `RecordInstanceType` of that entity's `.fields`, write JSON |
| `json_ptr` / `json_len` | last built row (for PUT) |
| `create_row(entity_index)` | `build_row` then `env.js_send_post` |

`entity_index` is the order of fields on `entity_defs` (the same order as the
catalog array). Date structs are parsed from `YYYY-MM-DD` into the three
integer fields in declaration order.

## What JS builds in the browser

After `WebAssembly.instantiateStreaming(fetch("frontend.wasm"), …)`, `main.js`:

1. Parses the catalog JSON.
2. Builds a nav of entity names (hash `#` + entity name).
3. Builds **one** table from the selected entity’s `fields`: thead labels, tfoot
   empty alta row, tbody filled from `GET /{entity}`. With no hash, the first
   catalog entity is selected.
4. Chooses `<input>` widgets from `field.storage` (`integer` → number,
   `boolean` → checkbox, `date` → date, else text).

**Post** (tfoot) packs the empty-row values into WASM memory and calls
`create_row`. Zig builds a typed record instance, `stringifyRecord`s it, and
calls `js_send_post`, which `fetch`es `POST /{entity}`.

**Save** (tbody) calls `build_row` and `PUT /{entity}`. The HTTP backend
replaces the row whose pk matches.

On success the page GETs the list again. The table is rebuilt from the catalog
plus that JSON; nothing is written to disk.

## Source files

| File | Role |
| --- | --- |
| `src/frontend/main.zig` | WASM entry: catalog, `build_row` / `create_row` (generic `system`) |
| `src/json.zig` | JSON for rows and entity Infos |
| `src/frontend/main.js` | nav + table from the catalog; `GET` / `POST` / `PUT` |
| `src/frontend/index.html` | empty shell |
| `examples/aida/src/aida.zig` | domain Defs (vocabulary fixture) |
| `examples/aida/src/system.zig` | wired as `system` by the example `build.zig` |
| `examples/aida/build.zig` | consumer: `addAppFromDep` |
| `src/http/main.zig` | in-memory lists per entity name from `system` |
