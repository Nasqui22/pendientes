# Desarrollo local

Entorno aislado: base de Supabase local (Docker) y servidor propio. No toca producción.

```
supabase start -x storage-api,imgproxy,logflare,vector,supavisor,studio,mailpit,postgres-meta
python3 dev/seed.py        # usuarios y datos de prueba (clave de todos: DevPendientes1)
python3 dev/serve.py       # http://127.0.0.1:8001
```

Usuarios: `admin@dev.local`, `virginia@dev.local` (líder de los tres siguientes), `ana@dev.local`,
`beto@dev.local`, `carla@dev.local`. Las claves de prueba son solo locales.

- Reiniciar de cero: `supabase db reset` y volver a correr `python3 dev/seed.py`.
- Probar SQL: `supabase db query --local -f archivo.sql`.
- Apagar: `supabase stop`.
- La función de administración (`admin-usuarios`) no corre en este entorno: los usuarios de prueba se crean con el seed.
