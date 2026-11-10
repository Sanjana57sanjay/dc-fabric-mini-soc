#!/usr/bin/env python3
# Lab webhook receiver: prints one line per Grafana alert notification.
import json, http.server, datetime

class H(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        body = self.rfile.read(int(self.headers.get("Content-Length", 0)))
        try:
            for a in json.loads(body).get("alerts", []):
                lb = a.get("labels", {})
                name = lb.get("alertname", "?")
                if lb.get("rulename") and lb["rulename"] != name:
                    name = f"{name} (rule: {lb['rulename']})"
                print(f"{datetime.datetime.utcnow():%H:%M:%S} UTC  "
                      f"{a.get('status', '?').upper():9} {lb.get('severity', '-'):9} {name}", flush=True)
        except Exception as e:
            print("bad payload:", e, flush=True)
        self.send_response(200); self.end_headers()
    def log_message(self, *args): pass

print("alert-sink listening on :8080", flush=True)
http.server.HTTPServer(("0.0.0.0", 8080), H).serve_forever()
