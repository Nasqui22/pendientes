#!/usr/bin/env python3
"""Corre las pruebas de seguridad y reglas (supabase/tests/*.sql) contra la base LOCAL.
Cada prueba arma sus datos, comprueba y termina con un error a propósito para revertir todo.
Uso: python3 dev/test.py   (requiere `supabase start`)"""
import glob, os, re, subprocess, sys
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
bad = 0
for f in sorted(glob.glob(os.path.join(ROOT, "supabase", "tests", "*.sql"))):
    r = subprocess.run(["supabase", "db", "query", "--local", "-f", f], cwd=ROOT, capture_output=True, text=True)
    m = re.search(r'error: ([^"]*)', r.stdout + r.stderr)
    msg = m.group(1).strip() if m else (r.stdout + r.stderr).strip()[-200:]
    ok = msg.startswith("TODO OK") or re.search(r"[0-9]+ comprobaciones OK, 0 fallas", msg)
    bad += 0 if ok else 1
    print(("OK    " if ok else "FALLA ") + os.path.basename(f) + ("" if ok else "  ->  " + msg))
print("\n%s" % ("Todas las pruebas pasaron." if not bad else "%d prueba(s) con fallas." % bad))
sys.exit(1 if bad else 0)
