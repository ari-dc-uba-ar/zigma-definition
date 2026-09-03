const apiBase = "http://localhost:8080";

let catalog = [];
let currentEntity = null;
let wasmExports = null;
/** Domain type name → `{ make, read }` from optional `./widgets.js`. */
let widgets = {};

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

function widgetFor(field) {
    return field.type ? widgets[field.type] : undefined;
}

/** Widget for `field.type` if the consumer registered one, else `field.storage`. `locked` makes pk cells read-only. Returns the element. */
function makeInput(field, value, locked) {
    const widget = widgetFor(field);
    if (widget?.make) return widget.make(field, value, locked);
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
        input.type = "text";
        input.inputMode = "numeric";
        input.className = "input-integer";
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

/** Value of `field` under `root`: nested object, checkbox bool, or raw string. Used inside object cells. */
function readLeaf(root, field) {
    const widget = widgetFor(field);
    if (widget?.read) return widget.read(root, field);
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
    return input.value ?? "";
}

/** Cell string for WASM packing: object → JSON, boolean → `"true"`/`"false"`, else the input value. */
function readFieldValue(td, field) {
    const widget = widgetFor(field);
    if (widget?.read) {
        const value = widget.read(td, field);
        if (typeof value === "object") return JSON.stringify(value ?? {});
        return String(value ?? "");
    }
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

function clearStatus() {
    const status = document.getElementById("status");
    status.textContent = "";
    status.classList.remove("network");
}

function showNetworkError(message) {
    const status = document.getElementById("status");
    status.textContent = message;
    status.classList.add("network");
}

function clearCellErrors() {
    document.querySelectorAll("#sheet-table td.cell-error").forEach((td) => {
        td.classList.remove("cell-error");
        td.removeAttribute("title");
    });
}

function fieldErrorName(message) {
    const match = /^error: (.+): not /.exec(message);
    return match ? match[1] : null;
}

function markCellError(td, message) {
    td.classList.add("cell-error");
    td.title = message;
}

function showRowBuildError(tr, message) {
    clearCellErrors();
    clearStatus();
    const name = fieldErrorName(message);
    const index = name ? currentEntity.fields.findIndex((field) => field.name === name) : -1;
    if (index >= 0 && tr.children[index]) {
        markCellError(tr.children[index], message);
        return;
    }
    for (let i = 0; i < currentEntity.fields.length; i++) {
        markCellError(tr.children[i], message);
    }
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
    button.textContent = "New";
    action.appendChild(button);
    newRow.appendChild(action);
    table.tFoot.replaceChildren(newRow);
    fitSheetColumns();

    button.addEventListener("click", () => {
        const values = fields.map((field, i) => readFieldValue(newRow.children[i], field));
        try {
            writeInputStrings(values);
            const len = wasmExports.create_row(entityIndex());
            if (!len) throw new Error(rowBuildError());
        } catch (err) {
            showRowBuildError(newRow, err instanceof Error ? err.message : String(err));
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
        save.className = "save-row";
        save.textContent = "Save";
        save.disabled = true;
        save.addEventListener("click", () => saveRow(tr, row));
        const del = document.createElement("button");
        del.type = "button";
        del.textContent = "Delete";
        del.addEventListener("click", () => deleteRow(row));
        action.appendChild(save);
        action.appendChild(del);
        tr.appendChild(action);
        tbody.appendChild(tr);
        setRowBaseline(tr);
    }
    fitSheetColumns();
}

let measureEl = null;
let fitFrame = 0;

function textWidth(text, styleSource) {
    if (!measureEl) {
        measureEl = document.createElement("span");
        measureEl.style.cssText = "position:absolute;left:-9999px;top:0;white-space:pre;visibility:hidden";
        document.body.appendChild(measureEl);
    }
    measureEl.style.font = getComputedStyle(styleSource).font;
    measureEl.textContent = text.length ? text : " ";
    return measureEl.offsetWidth;
}

function inputContentWidth(input) {
    if (input.type === "checkbox") return 28;
    const cs = getComputedStyle(input);
    const content = textWidth(input.value, input) + parseFloat(cs.paddingLeft) + parseFloat(cs.paddingRight) + 2;
    if (input.type === "date") return Math.max(160, content);
    return content;
}

function cellContentWidth(cell) {
    if (cell.classList.contains("action") || cell.querySelector(":scope > button")) {
        const cs = getComputedStyle(cell);
        const pad = parseFloat(cs.paddingLeft) + parseFloat(cs.paddingRight);
        const border = parseFloat(cs.borderLeftWidth) + parseFloat(cs.borderRightWidth);
        let content = 0;
        cell.querySelectorAll(":scope > button").forEach((button, i) => {
            content += button.offsetWidth;
            if (i > 0) content += parseFloat(getComputedStyle(button).marginLeft) || 0;
        });
        return content + pad + border;
    }
    if (cell.tagName === "TH") {
        return textWidth(cell.textContent, cell) + 16;
    }
    const wrap = cell.querySelector(".object-fields");
    if (wrap) {
        let width = 0;
        wrap.querySelectorAll("input").forEach((input) => {
            width += Math.max(inputContentWidth(input), input.offsetWidth);
        });
        return width;
    }
    const input = cell.querySelector("input");
    return input ? inputContentWidth(input) : 0;
}

/** Sizes each column to the widest header or cell. Table width is the sum; it does not stretch to the viewport. */
function fitSheetColumns() {
    const table = document.getElementById("sheet-table");
    const header = table.tHead?.rows[0];
    if (!header) return;
    const n = header.cells.length;
    const widths = Array(n).fill(24);
    for (const row of table.rows) {
        for (let i = 0; i < n; i++) {
            const cell = row.cells[i];
            if (cell) widths[i] = Math.max(widths[i], cellContentWidth(cell));
        }
    }
    let colgroup = table.querySelector("colgroup");
    if (!colgroup) {
        colgroup = document.createElement("colgroup");
        table.prepend(colgroup);
    }
    colgroup.replaceChildren();
    let total = 0;
    for (const width of widths) {
        const col = document.createElement("col");
        const px = Math.ceil(width);
        col.style.width = `${px}px`;
        total += px;
        colgroup.appendChild(col);
    }
    table.style.tableLayout = "fixed";
    table.style.width = `${total}px`;
}

function scheduleFitSheetColumns() {
    if (fitFrame) return;
    fitFrame = requestAnimationFrame(() => {
        fitFrame = 0;
        fitSheetColumns();
    });
}

function rowValuesFrom(tr) {
    return currentEntity.fields.map((field, i) => readFieldValue(tr.children[i], field));
}

function setRowBaseline(tr) {
    tr.dataset.baseline = JSON.stringify(rowValuesFrom(tr));
}

function isRowDirty(tr) {
    if (!tr.dataset.baseline) return false;
    return tr.dataset.baseline !== JSON.stringify(rowValuesFrom(tr));
}

/** Enables Save only when live cell values differ from the baseline captured at load. */
function updateSaveButton(tr) {
    const save = tr.querySelector("button.save-row");
    if (!save) return;
    save.disabled = !isRowDirty(tr);
}

/** PUT: pack live cells from `tr`, `build_row`, body from `json_buf`. Query pk from loaded `row`. */
async function saveRow(tr, row) {
    try {
        writeInputStrings(rowValuesFrom(tr));
        const len = wasmExports.build_row(entityIndex());
        if (!len) throw new Error(rowBuildError());
        const jsonString = readMemoryString(wasmExports.json_ptr(), len);
        await sendJson(resourceUrl(currentEntity, row), "PUT", jsonString);
    } catch (err) {
        showRowBuildError(tr, err instanceof Error ? err.message : String(err));
    }
}

/** DELETE `/{entity}?pk…` from loaded `row`. No body. Network errors go to the top bar. */
async function deleteRow(row) {
    try {
        await sendJson(resourceUrl(currentEntity, row), "DELETE", null);
    } catch (err) {
        showNetworkError(String(err));
        console.error(err);
    }
}

/** GET `/{currentEntity.name}` then `fillTable`. Network errors go to the top bar. */
function loadRows() {
    fetch(`${apiBase}/${currentEntity.name}`)
        .then((response) => {
            if (!response.ok) throw new Error(`Could not load ${currentEntity.name} (${response.status})`);
            return response.json();
        })
        .then((rows) => {
            clearStatus();
            fillTable(rows);
        })
        .catch((err) => {
            showNetworkError(String(err));
            console.error(err);
        });
}

/** `fetch` `method` at `url`; JSON body if `jsonString` is not null. On OK: refresh the table, no success text. */
async function sendJson(url, method, jsonString) {
    try {
        const init = { method };
        if (jsonString != null) {
            init.headers = { "Content-Type": "application/json" };
            init.body = jsonString;
        }
        const response = await fetch(url, init);
        const result = await response.json().catch(() => null);
        if (!response.ok) {
            showNetworkError(`Could not ${method} ${currentEntity.name} (${response.status})`);
            console.error("Server response:", result);
            return;
        }
        console.log("Server response:", result);
        clearCellErrors();
        clearStatus();
        if (method === "POST") {
            document.querySelectorAll("#new-row input").forEach((input) => {
                if (input.type === "checkbox") input.checked = false;
                else input.value = "";
            });
        }
        loadRows();
    } catch (err) {
        showNetworkError(String(err));
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

document.getElementById("sheet-table").addEventListener("input", (event) => {
    const td = event.target.closest("td");
    if (td) {
        td.classList.remove("cell-error");
        td.removeAttribute("title");
    }
    const tr = event.target.closest("tbody tr");
    if (tr) updateSaveButton(tr);
    scheduleFitSheetColumns();
});
document.getElementById("sheet-table").addEventListener("change", (event) => {
    const tr = event.target.closest("tbody tr");
    if (tr) updateSaveButton(tr);
    scheduleFitSheetColumns();
});

function loadWidgets() {
    return import("./widgets.js")
        .then((mod) => {
            widgets = mod.widgets ?? {};
        })
        .catch(() => {
            widgets = {};
        });
}

loadWidgets()
    .then(() => WebAssembly.instantiateStreaming(fetch("frontend.wasm"), importObject))
    .then((obj) => {
        wasmExports = obj.instance.exports;
        window.wasmInstance = obj.instance;
        catalog = JSON.parse(readWasmString(wasmExports.schema_ptr, wasmExports.schema_len));
        const fromHash = location.hash.replace(/^#/, "");
        selectEntity(fromHash || catalog[0].name);
        clearStatus();
        window.addEventListener("hashchange", () => {
            const name = location.hash.replace(/^#/, "");
            if (name && currentEntity && name !== currentEntity.name) selectEntity(name);
        });
    })
    .catch((err) => {
        showNetworkError(String(err));
        console.error(err);
    });
