---
version: 1
slug: "index-html"
primary_target: "index.html"
related_targets: []
---

# Surface brief: Pendientes (index.html)

Mode: Operate. Audience: equipo chico, celular y compu por igual; tres perfiles (persona, responsable, admin). Job: ver y mover pendientes, revisar y validar lo del equipo, asignar y armar proyectos, administrar usuarios. Constraints: un solo archivo, claro y oscuro, SVG, mobile primero con 16px de margen, español rioplatense, ids y lógica JS intactos.

## Direction contract

THESIS: El estándar de la categoría ejecutado con oficio, al nivel de Linear, Todoist y Things 3: una app de tareas sobria y limpia que se siente cálida porque está bien hecha, no porque tenga disfraz. Rechaza el disfraz temático y el kanban genérico de tarjetas idénticas con sombra pesada.
OWN-WORLD: Neutros fríos apenas tintados (ground #F6F7F9, superficie blanca, tinta #12151C), un solo acento índigo #3858E9 para selección, foco y acciones; estados con color propio y funcional (pendiente pizarra, en proceso ámbar, completado verde, validado en el acento). Hanken Grotesk para todo, pesos 400/500/600, numerales tabulares. Radio 10px, hilos de 1px, una sola elevación suave. Oscuro: #0E1116 con superficies #151A22 y acento #8CA2FF.
STORY: Quien abre la app entiende en un segundo qué le toca, qué está en curso y qué espera validación; mueve una tarea con un gesto; el responsable ve de quién es cada cosa. La administración queda en un panel aparte.
FIRST VIEWPORT: Barra superior de 56px (logo Pendientes a la izquierda; a la derecha nombre, Usuarios si es admin y Salir). Debajo, título "Mi tablero" con el conteo y una barra de avance fina. Tres columnas parejas (Pendiente, En proceso, Completado) con encabezado de ícono, nombre y contador; tarjetas limpias con prioridad como punto y texto, fecha, subtareas y notas; fila de agregar discreta al pie. En celular, selector segmentado de estado y una sola columna visible.
FORM: Canon del catálogo de la tirada, elegido por el usuario por la vía de registro más seguro; SEED REFERENCE: seed: 8deeae2e (register safer, reroll 1).
FINISH: unreviewed and undocumented is unfinished; this build ends with the finish review, the verdict, DESIGN.md, and every shipping raster carrying its provenance
