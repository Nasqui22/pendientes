#!/usr/bin/env python3
"""Carga dev/seed.sql en la base LOCAL (se niega a correr contra otra)."""
import os, subprocess, sys
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
r = subprocess.run(["supabase", "db", "query", "--local", "-f", os.path.join(ROOT, "dev", "seed.sql")], cwd=ROOT, capture_output=True, text=True)
print((r.stdout + r.stderr).strip()[-600:] or "seed aplicado")
sys.exit(r.returncode)
