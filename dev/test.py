#!/usr/bin/env python3
"""Corre las pruebas de seguridad y reglas (supabase/tests/*.sql) contra la base LOCAL.
Cada prueba arma sus datos, comprueba y termina con un error a propósito para revertir todo.
Antes revisa que el JavaScript de index.html compile (necesita node).
Uso: python3 dev/test.py        (requiere `supabase start`)
     python3 dev/test.py --js   (solo el chequeo de sintaxis, no necesita base ni Docker)"""
import glob, os, re, subprocess, sys, tempfile
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
bad = 0

def chequear_js():
    """Compila los <script> inline de index.html con node: un error de sintaxis deja la web en «cargando…» para todos.
    Devuelve la cantidad de fallas (0 si compila o si falta node, que se avisa)."""
    html = open(os.path.join(ROOT, "index.html"), encoding="utf8").read()
    scripts = re.findall(r"<script(?![^>]*src)[^>]*>(.*?)</script>", html, re.S)
    if subprocess.run(["which", "node"], capture_output=True).returncode:
        print("AVISO node no está instalado: no se chequeó la sintaxis de index.html"); return 0
    fallas = 0
    with tempfile.TemporaryDirectory() as tmp:
        for i, s in enumerate(scripts):
            f = os.path.join(tmp, "script%d.js" % i)
            open(f, "w", encoding="utf8").write(s)
            r = subprocess.run(["node", "--check", f], capture_output=True, text=True)
            if r.returncode:
                fallas += 1
                lineas = [l for l in r.stderr.splitlines() if l.strip()]
                err = next((l for l in lineas if "Error" in l), lineas[-1])
                donde = next((l for l in lineas if re.search(r"\.js:\d+", l)), "")
                print("FALLA index.html (script %d)  ->  %s  (%s)" % (i, err, re.sub(r"^.*script\d+\.js", "línea", donde)))
    if not fallas: print("OK    index.html (sintaxis de %d scripts)" % len(scripts))
    return fallas

bad += chequear_js()
if "--js" in sys.argv:
    sys.exit(1 if bad else 0)
for f in sorted(glob.glob(os.path.join(ROOT, "supabase", "tests", "*.sql"))):
    r = subprocess.run(["supabase", "db", "query", "--local", "-f", f], cwd=ROOT, capture_output=True, text=True)
    m = re.search(r'error: ([^"]*)', r.stdout + r.stderr)
    msg = m.group(1).strip() if m else (r.stdout + r.stderr).strip()[-200:]
    ok = msg.startswith("TODO OK") or re.search(r"[0-9]+ comprobaciones OK, 0 fallas", msg)
    bad += 0 if ok else 1
    print(("OK    " if ok else "FALLA ") + os.path.basename(f) + ("" if ok else "  ->  " + msg))
print("\n%s" % ("Todas las pruebas pasaron." if not bad else "%d prueba(s) con fallas." % bad))
sys.exit(1 if bad else 0)
