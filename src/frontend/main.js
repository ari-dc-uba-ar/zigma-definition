const apiBase = "http://localhost:8080";

let catalog = [];
let currentEntity = null;
let wasmExports = null;

const importObject = {
    env: {
        js_send_post: async (ptr, len) => {
            const jsonString = readMemoryString(ptr, len);
            await sendJson(`${apiBase}/${currentEntity.name}`, "POST", jsonString);
        }
    }
};

function readMemoryString(ptr, len) {
    const memory = new Uint8Array(wasmExports.memory.buffer);
    return new TextDecoder().decode(memory.subarray(ptr, ptr + len));
}

function readWasmString(ptrFn, lenFn) {
    return readMemoryString(ptrFn(), lenFn());
}

function dateToInput(value) {
    if (value == null || value === "") return "";
    if (typeof value === "string") return value;
    if (typeof value === "object") {
        const parts = Object.values(value);
        if (parts.length >= 3) {
            const y = String(parts[0]).padStart(4, "0");
            const m = String(parts[1]).padStart(2, "0");
            const d = String(parts[2]).padStart(2, "0");
            return `${y}-${m}-${d}`;
        }
    }
    return "";
}

function displayValue(field, value) {
    if (field.storage === "date") return dateToInput(value);
    if (field.storage === "boolean") return value;
    if (value == null) return "";
    return value;
}

function isPkField(field) {
    return currentEntity.pk.includes(field.name);
}

function fieldByName(name) {
    return currentEntity.fields.find((field) => field.name === name);
}

function pkString(name, value) {
    const field = fieldByName(name);
    if (field && field.storage === "date") return dateToInput(value);
    if (field && field.storage === "boolean") return value === true || value === "true" ? "true" : "false";
    if (value == null) return "";
    return String(value);
}

function resourceUrl(entity, row) {
    const query = new URLSearchParams();
    for (const name of entity.pk) {
        query.set(name, pkString(name, row[name]));
    }
    return `${apiBase}/${entity.name}?${query}`;
}

function makeInput(field, value, locked) {
    const input = document.createElement("input");
    input.dataset.field = field.name;
    input.autocomplete = "off";
    if (field.storage === "integer") {
        input.type = "number";
        input.value = value ?? "";
    } else if (field.storage === "boolean") {
        input.type = "checkbox";
        input.checked = value === true || value === "true";
    } else if (field.storage === "date") {
        input.type = "date";
        input.value = dateToInput(value);
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

function readInput(input, field) {
    if (field.storage === "boolean") return input.checked ? "true" : "false";
    return input.value ?? "";
}

function entityIndex() {
    return catalog.findIndex((entity) => entity.name === currentEntity.name);
}

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
        td.appendChild(makeInput(field, field.storage === "boolean" ? false : ""));
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
        const values = fields.map((field) => {
            const input = document.querySelector(`#new-row input[data-field="${field.name}"]`);
            return readInput(input, field);
        });
        try {
            writeInputStrings(values);
            wasmExports.create_row(entityIndex());
        } catch (err) {
            document.getElementById("status").textContent = String(err);
        }
    });
}

function fillTable(rows) {
    const tbody = document.querySelector("#sheet-table tbody");
    const fields = currentEntity.fields;
    tbody.replaceChildren();
    for (const row of rows) {
        const tr = document.createElement("tr");
        for (const field of fields) {
            const td = document.createElement("td");
            td.appendChild(makeInput(field, displayValue(field, row[field.name]), isPkField(field)));
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
    return currentEntity.fields.map((field) => {
        const input = tr.querySelector(`input[data-field="${field.name}"]`);
        return readInput(input, field);
    });
}

async function saveRow(tr, row) {
    const status = document.getElementById("status");
    try {
        writeInputStrings(rowValuesFrom(tr));
        const len = wasmExports.build_row(entityIndex());
        if (!len) throw new Error("could not build row JSON");
        const jsonString = readMemoryString(wasmExports.json_ptr(), len);
        await sendJson(resourceUrl(currentEntity, row), "PUT", jsonString);
    } catch (err) {
        status.textContent = String(err);
    }
}

async function deleteRow(row) {
    const status = document.getElementById("status");
    try {
        await sendJson(resourceUrl(currentEntity, row), "DELETE", null);
    } catch (err) {
        status.textContent = String(err);
    }
}

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
