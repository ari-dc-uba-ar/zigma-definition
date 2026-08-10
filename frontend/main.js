const importObject = {
    env: {
        js_send_post: async (ptr, len) => {
            // Read the string out of WASM linear memory
            const memory = new Uint8Array(wasmInstance.exports.memory.buffer);
            const bytes = memory.subarray(ptr, ptr + len);
            const jsonString = new TextDecoder().decode(bytes);

            // Forward the query via browser fetch() to your Python backend
            const response = await fetch('http://localhost:8080/materias', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: jsonString
            });
            
            const result = await response.json();
            console.log("Server response:", result);
        }
    }
};

// Load your Zig WASM binary...
WebAssembly.instantiateStreaming(fetch('frontend.wasm'), importObject)
    .then(obj => {
        window.wasmInstance = obj.instance;
        // Trigger the creation from the spreadsheet/UI action
        obj.instance.exports.create_materia_request();
    });