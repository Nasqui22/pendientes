# Product

<!-- impeccable:product-schema 1 -->

## Platform

web

## Users
Equipo chico que trabaja con tareas compartidas, usado por igual desde celular y computadora. Hay tres perfiles: la persona común (ve y mueve sus pendientes), el responsable (tiene gente a cargo, puede ser responsable de otros responsables) y el administrador (gestiona usuarios y quién responde por quién, sin ver las tareas de los demás).

## Product Purpose
Tablero de tareas en estados (Pendiente, En proceso, Completado, y Validado, que solo pasa el responsable) con prioridad, fecha límite, notas y subtareas, ahora con usuarios, responsables y proyectos. Nació como tablero personal. Éxito: abrir la app y resolver en segundos lo que toca hacer, revisar y validar lo del equipo, y repartir trabajo a los directos.

## Operating Context
Se abre varias veces al día, a menudo entre otras cosas y desde el teléfono. Tareas personales privadas por defecto: el responsable solo ve las de su personal si la persona marca una casilla o si él se las asignó. Los datos viven en Supabase con RLS por usuario y por relación de responsabilidad. Interfaz en español rioplatense. Web estática en GitHub Pages, un solo archivo `index.html` sin build.

## Capabilities and Constraints
- Login con email y contraseña; sin registro público. Solo el admin crea usuarios.
- Tareas con estados, prioridad, fecha, notas y subtareas; arrastrar entre columnas.
- Panel de administración: usuarios (alta, admin, activo, contraseña) y responsables (varios por persona, en cadena, sin ciclos).
- Pendiente de construir: proyectos, asignación de tareas a directos, estado Validado, vista "Mi equipo".
- Modo claro y oscuro, íconos SVG, mobile primero, mínimo 16px de margen lateral.
- La lógica JS y los ids del DOM existentes (`toRow`/`fromRow`, Supabase) deben seguir funcionando.

## Brand Commitments
Solo el nombre "Merlin't" y el español rioplatense. No hay logo, paleta ni marca previa que preservar; la identidad visual actual es reemplazable.

Preferencia estable confirmada por el usuario (2026-10-15): visual sobrio y limpio, al nivel de oficio de Linear, Todoist y Things 3, ejecutado como estándar de la categoría; sin tono corporativo frío ni decoración de más.

## Evidence on Hand
No hay testimonios, clientes ni métricas. No inventarlos.

## Product Principles
1. La acción diaria (ver, mover, completar) tiene que ser inmediata y de un solo gesto, también con el pulgar.
2. La responsabilidad es explícita: siempre se ve de quién es una tarea y quién la valida.
3. La privacidad por defecto se nota en la interfaz: lo compartido se distingue de lo personal.
4. La administración queda a un lado y no ensucia el tablero de quien no la usa.

## Accessibility & Inclusion
Sin requisito específico establecido. Piso razonable: contraste legible en claro y oscuro, foco visible, objetivos táctiles cómodos y respeto de `prefers-reduced-motion`.
