const apiBase = "http://localhost:8080";

let catalog = [];
let currentEntity = null;
let wasmExports = null;

const importObject = {
    env: {
        /** WASM import: `ptr`/`len` into `json_buf`. POSTs that JSON to `/{currentEntity}`. No return. */
        js_send_post: async (ptr, len) => {
            const jsonString = readMemoryString(ptr, len);
            await sendJson(`${apiBase}/${currentEntity.name}`, "POST", jsonString);
        }
    }
};

/** UTF-8 slice of WASM memory at `ptr` of `len` bytes. */
function readMemoryString(ptr, len) {
    const memory = new Uint8Array(wasmExports.memory.buffer);
    return new TextDecoder().decode(memory.subarray(ptr, ptr + len));
}

function readWasmString(ptrFn, lenFn) {
    return readMemoryString(ptrFn(), lenFn());
}

function isPkField(field) {
    return currentEntity.pk.includes(field.name);
}

function fieldByName(name) {
    return currentEntity.fields.find((field) => field.name === name);
}

/** Query-string form of a pk cell: object → JSON, boolean → `"true"`/`"false"`, else `String(value)` (empty if nullish). */
function pkString(name, value) {
    const field = fieldByName(name);
    if (field && field.storage === "object") return JSON.stringify(value ?? {});
    if (field && field.storage === "boolean") return value === true || value === "true" ? "true" : "false";
    if (value == null) return "";
    return String(value);
}

/** `GET`-style identity URL: `/{entity.name}?` every pk field from `row` (loaded identity, not live inputs). */
function resourceUrl(entity, row) {
    const query = new URLSearchParams();
    for (const name of entity.pk) {
        query.set(name, pkString(name, row[name]));
    }
    return `${apiBase}/${entity.name}?${query}`;
}

/** Widget for `field.storage`: nested `.object-fields` or `<input>`. `locked` makes pk cells read-only. Returns the element. */
function makeInput(field, value, locked) {
    if (field.storage === "object" && field.fields) {
        const wrap = document.createElement("div");
        wrap.className = "object-fields";
        wrap.dataset.field = field.name;
        const obj = value && typeof value === "object" ? value : {};
        for (const sub of field.fields) {
            wrap.appendChild(makeInput(sub, obj[sub.name], locked));
        }
        return wrap;
    }
    const input = document.createElement("input");
    input.dataset.field = field.name;
    input.autocomplete = "off";
    if (field.storage === "integer") {
        input.type = "number";
        input.value = value ?? "";
    } else if (field.storage === "boolean") {
        input.type = "checkbox";
        input.checked = value === true || value === "true";
    } else {
        input.type = "text";
        input.value = value ?? "";
    }
    if (locked) {
        if (field.storage === "boolean") input.disabled = true;
        else input.readOnly = true;
        input.tabIndex = -1;
    }
    return input;
}

/** Value of `field` under `root`: nested object, checkbox bool, number or raw string. Used inside object cells. */
function readLeaf(root, field) {
    if (field.storage === "object" && field.fields) {
        const wrap = root.matches?.(`[data-field="${field.name}"].object-fields`)
            ? root
            : root.querySelector(`[data-field="${field.name}"].object-fields`);
        const obj = {};
        for (const sub of field.fields) {
            obj[sub.name] = readLeaf(wrap ?? root, sub);
        }
        return obj;
    }
    const input = root.querySelector(`input[data-field="${field.name}"]`);
    if (field.storage === "boolean") return input.checked;
    if (field.storage === "integer") {
        if (!input.value) return "";
        const n = Number(input.value);
        return Number.isFinite(n) ? n : input.value;
    }
    return input.value ?? "";
}

/** Cell string for WASM packing: object → JSON, boolean → `"true"`/`"false"`, else the input value. */
function readFieldValue(td, field) {
    if (field.storage === "object" && field.fields) {
        return JSON.stringify(readLeaf(td, field));
    }
    const input = td.querySelector(`input[data-field="${field.name}"]`);
    if (field.storage === "boolean") return input.checked ? "true" : "false";
    return input.value ?? "";
}

/** Last WASM `error_buf` text, or a fallback if `error_len` is 0. */
function rowBuildError() {
    const len = wasmExports.error_len();
    if (!len) return "error: could not build row JSON";
    return readMemoryString(wasmExports.error_ptr(), len);
}

function entityIndex() {
    return catalog.findIndex((entity) => entity.name === currentEntity.name);
}

/** Rebuilds `#entity-nav` from `catalog` (`href="#name"`). No args/return. */
function buildNav() {
    const nav = document.getElementById("entity-nav");
    nav.replaceChildren();
    for (const entity of catalog) {
        const link = document.createElement("a");
        link.href = `#${entity.name}`;
        link.textContent = entity.name;
        if (currentEntity && entity.name === currentEntity.name) link.className = "selected";
        nav.appendChild(link);
    }
}

/** Thead labels + tfoot alta row for `entity.fields`; Post packs cells and calls `create_row`. Does not fill tbody. */
function buildTable(entity) {
    const table = document.getElementById("sheet-table");
    const fields = entity.fields;

    const headerRow = document.createElement("tr");
    for (const field of fields) {
        const th = document.createElement("th");
        th.textContent = field.label;
        headerRow.appendChild(th);
    }
    headerRow.appendChild(document.createElement("th"));
    table.tHead.replaceChildren(headerRow);

    const newRow = document.createElement("tr");
    newRow.id = "new-row";
    for (const field of fields) {
        const td = document.createElement("td");
        td.appendChild(makeInput(field, field.storage === "boolean" ? false : field.storage === "object" ? {} : ""));
        newRow.appendChild(td);
    }
    const action = document.createElement("td");
    action.className = "action";
    const button = document.createElement("button");
    button.type = "button";
    button.id = "post-row";
    button.textContent = "Post";
    action.appendChild(button);
    newRow.appendChild(action);
    table.tFoot.replaceChildren(newRow);

    button.addEventListener("click", () => {
        const values = fields.map((field, i) => readFieldValue(newRow.children[i], field));
        try {
            writeInputStrings(values);
            const len = wasmExports.create_row(entityIndex());
            if (!len) throw new Error(rowBuildError());
        } catch (err) {
            document.getElementById("status").textContent = err instanceof Error ? err.message : String(err);
        }
    });
}

/** Tbody from GET `rows`: one tr per row, pk inputs locked, Save/Delete. Uses `currentEntity`. */
function fillTable(rows) {
    const tbody = document.querySelector("#sheet-table tbody");
    const fields = currentEntity.fields;
    tbody.replaceChildren();
    for (const row of rows) {
        const tr = document.createElement("tr");
        for (const field of fields) {
            const td = document.createElement("td");
            td.appendChild(makeInput(field, row[field.name], isPkField(field)));
            tr.appendChild(td);
        }
        const action = document.createElement("td");
        action.className = "action";
        const save = document.createElement("button");
        save.type = "button";
        save.textContent = "Save";
        save.addEventListener("click", () => saveRow(tr, row));
        const del = document.createElement("button");
        del.type = "button";
        del.textContent = "Delete";
        del.addEventListener("click", () => deleteRow(row));
        action.appendChild(save);
        action.appendChild(del);
        tr.appendChild(action);
        tbody.appendChild(tr);
    }
}

function rowValuesFrom(tr) {
    return currentEntity.fields.map((field, i) => readFieldValue(tr.children[i], field));
}

/** PUT: pack live cells from `tr`, `build_row`, body from `json_buf`. Query pk from loaded `row`. Status on failure. */
async function saveRow(tr, row) {
    const status = document.getElementById("status");
    try {
        writeInputStrings(rowValuesFrom(tr));
        const len = wasmExports.build_row(entityIndex());
        if (!len) throw new Error(rowBuildError());
        const jsonString = readMemoryString(wasmExports.json_ptr(), len);
        await sendJson(resourceUrl(currentEntity, row), "PUT", jsonString);
    } catch (err) {
        status.textContent = err instanceof Error ? err.message : String(err);
    }
}

/** DELETE `/{entity}?pk…` from loaded `row`. No body. Status on failure. */
async function deleteRow(row) {
    const status = document.getElementById("status");
    try {
        await sendJson(resourceUrl(currentEntity, row), "DELETE", null);
    } catch (err) {
        status.textContent = String(err);
    }
}

/** GET `/{currentEntity.name}` then `fillTable`. Writes `#status` on error. */
function loadRows() {
    const status = document.getElementById("status");
    fetch(`${apiBase}/${currentEntity.name}`)
        .then((response) => {
            if (!response.ok) throw new Error(`GET /${currentEntity.name} ${response.status}`);
            return response.json();
        })
        .then(fillTable)
        .catch((err) => {
            status.textContent = String(err);
            console.error(err);
        });
}

/** `fetch` `method` at `url`; JSON body if `jsonString` is not null. On OK: clear Post row if POST, then `loadRows`. */
async function sendJson(url, method, jsonString) {
    const status = document.getElementById("status");
    try {
        const init = { method };
        if (jsonString != null) {
            init.headers = { "Content-Type": "application/json" };
            init.body = jsonString;
        }
        const response = await fetch(url, init);
        const result = await response.json();
        status.textContent = JSON.stringify(result);
        console.log("Server response:", result);
        if (response.ok) {
            if (method === "POST") {
                document.querySelectorAll("#new-row input").forEach((input) => {
                    if (input.type === "checkbox") input.checked = false;
                    else input.value = "";
                });
            }
            loadRows();
        }
    } catch (err) {
        status.textContent = String(err);
        console.error(err);
    }
}

/** Packs `values` (entity field order) into `input_buf` and `lengths_buf`. Throws if over `input_len`. */
function writeInputStrings(values) {
    const ptr = wasmExports.input_ptr();
    const cap = wasmExports.input_len();
    const encoded = new TextEncoder();
    const parts = values.map((value) => encoded.encode(String(value)));
    let total = 0;
    for (const part of parts) total += part.length;
    if (total > cap) throw new Error("input too long for WASM buffer");

    const memory = new Uint8Array(wasmExports.memory.buffer);
    const lengths = new Uint32Array(wasmExports.memory.buffer, wasmExports.lengths_ptr(), parts.length);
    let offset = 0;
    parts.forEach((part, i) => {
        memory.set(part, ptr + offset);
        lengths[i] = part.length;
        offset += part.length;
    });
}

/** Select catalog entity by `name` (else first). Sets hash, title, nav, table, GET. No return. */
function selectEntity(name) {
    const entity = catalog.find((item) => item.name === name) ?? catalog[0];
    currentEntity = entity;
    location.hash = entity.name;
    document.getElementById("sheet-title").textContent = entity.name;
    buildNav();
    buildTable(entity);
    loadRows();
}

WebAssembly.instantiateStreaming(fetch("frontend.wasm"), importObject)
    .then((obj) => {
        wasmExports = obj.instance.exports;
        window.wasmInstance = obj.instance;
        const status = document.getElementById("status");
        catalog = JSON.parse(readWasmString(wasmExports.schema_ptr, wasmExports.schema_len));
        const fromHash = location.hash.replace(/^#/, "");
        selectEntity(fromHash || catalog[0].name);
        if (status.textContent === "Loading WASM…") status.textContent = "Ready.";
        window.addEventListener("hashchange", () => {
            const name = location.hash.replace(/^#/, "");
            if (name && currentEntity && name !== currentEntity.name) selectEntity(name);
        });
    })
    .catch((err) => {
        document.getElementById("status").textContent = String(err);
        console.error(err);
    });
