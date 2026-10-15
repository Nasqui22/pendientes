#!/usr/bin/env python3
"""Servidor de desarrollo: sirve la web contra la base LOCAL de Supabase (nunca contra producción).

  supabase start        # una vez, levanta la base local (Docker)
  python3 dev/seed.py   # carga usuarios y datos de prueba
  python3 dev/serve.py  # http://127.0.0.1:8001

Reescribe al vuelo /config.js (URL y clave locales) y la CSP de index.html, y muestra
una franja "DESARROLLO" para no confundirlo con producción. No modifica ningún archivo.
"""
import http.server, json, os, re, subprocess, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 8001

def local_cfg():
    out = subprocess.run(["supabase", "status", "-o", "json"], cwd=ROOT, capture_output=True, text=True)
    j = json.loads(out.stdout)
    return j["API_URL"], j["ANON_KEY"]

API, ANON = local_cfg()
WS = API.replace("http://", "ws://").replace("https://", "wss://")
BADGE = ('<div style="position:fixed;z-index:99;left:50%;top:0;transform:translateX(-50%);background:#b45309;color:#fff;'
         'font:600 11px system-ui;padding:2px 12px;border-radius:0 0 8px 8px;pointer-events:none">DESARROLLO · base local</div>')

class H(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *a, **k): super().__init__(*a, directory=ROOT, **k)
    def do_GET(self):
        path = self.path.split("?")[0]
        if path == "/config.js":
            body = ('window.PENDIENTES_CONFIG = %s;' % json.dumps({"url": API, "anonKey": ANON})).encode()
            return self._send(body, "application/javascript")
        if path in ("/", "/index.html"):
            html = open(os.path.join(ROOT, "index.html"), encoding="utf-8").read()
            html = re.sub(r"connect-src [^;]+;", "connect-src 'self' %s %s;" % (API, WS), html)
            html = html.replace("<body>", "<body>" + BADGE, 1)
            inj = os.environ.get("DEV_INJECT")  # solo para pruebas automáticas
            if inj: html = html.replace("</body>", "<script>" + open(inj, encoding="utf-8").read() + "</script></body>")
            return self._send(html.encode(), "text/html; charset=utf-8")
        return super().do_GET()
    def _send(self, body, ctype):
        self.send_response(200); self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body))); self.send_header("Cache-Control", "no-store")
        self.end_headers(); self.wfile.write(body)

if __name__ == "__main__":
    print("Desarrollo en http://127.0.0.1:%d  (API local: %s)" % (PORT, API))
    http.server.ThreadingHTTPServer(("127.0.0.1", PORT), H).serve_forever()
