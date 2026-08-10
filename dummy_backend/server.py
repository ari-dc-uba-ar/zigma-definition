from http.server import HTTPServer, BaseHTTPRequestHandler
import json

class RequestPrinterHandler(BaseHTTPRequestHandler):
    def do_OPTIONS(self):
        # Handle browser CORS preflight request
        self.send_response(200)
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "POST, GET, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Content-Type")
        self.end_headers()

    def do_POST(self):
        content_length = int(self.headers.get('Content-Length', 0))
        body = self.rfile.read(content_length)
        
        print("\n--- INCOMING HTTP POST REQUEST ---")
        print(f"Path: {self.path}")
        print("Headers:")
        print(self.headers)
        print("Body Payload:")
        try:
            print(json.dumps(json.loads(body.decode('utf-8')), indent=2))
        except Exception:
            print(body)
        print("----------------------------------\n")
        
        # Respond back with success and CORS headers
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Access-Control-Allow-Origin", "*")
        self.end_headers()
        self.wfile.write(json.dumps({"status": "received"}).encode('utf-8'))

    def do_GET(self):
        print(f"\n--- INCOMING HTTP GET REQUEST: {self.path} ---")
        self.send_response(200)
        self.send_header("Access-Control-Allow-Origin", "*")
        self.end_headers()
        self.wfile.write(b"OK")

def run(server_class=HTTPServer, handler_class=RequestPrinterHandler, port=8080):
    server_address = ('', port)
    httpd = server_class(server_address, handler_class)
    print(f"Python request printer running on port {port}...")
    httpd.serve_forever()

if __name__ == '__main__':
    run()