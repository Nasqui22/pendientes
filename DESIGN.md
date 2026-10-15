---
name: Pendientes
description: Tablero personal de tareas en tres estados, sobrio y bien terminado, con un solo acento índigo.
colors:
  accent: "#3858E9"
  accent-soft: "#E9EEFF"
  accent-ink: "#FFFFFF"
  bg: "#F6F7F9"
  surface: "#FFFFFF"
  surface-2: "#EEF0F4"
  ink: "#12151C"
  muted: "#4B5565"
  faint: "#667085"
  line: "#E2E6EC"
  line-strong: "#CDD3DC"
  pend: "#556074"
  pend-soft: "#E9ECF2"
  proc: "#A8480A"
  proc-soft: "#FDEFD9"
  comp: "#0B7A4B"
  comp-soft: "#DCF2E6"
  alta: "#C42B22"
  dark-bg: "#0E1116"
  dark-surface: "#151A22"
  dark-surface-2: "#1B212B"
  dark-ink: "#E7EBF2"
  dark-accent: "#8CA2FF"
  dark-accent-soft: "#1D2547"
  dark-accent-ink: "#0B1026"
typography:
  headline:
    fontFamily: "Hanken Grotesk, system-ui, -apple-system, Segoe UI, sans-serif"
    fontSize: "clamp(24px, 4vw, 30px)"
    fontWeight: 600
    lineHeight: 1.15
    letterSpacing: "-0.025em"
  title:
    fontFamily: "Hanken Grotesk, system-ui, -apple-system, Segoe UI, sans-serif"
    fontSize: "21px"
    fontWeight: 600
    lineHeight: 1.3
    letterSpacing: "-0.02em"
  body:
    fontFamily: "Hanken Grotesk, system-ui, -apple-system, Segoe UI, sans-serif"
    fontSize: "14.5px"
    fontWeight: 400
    lineHeight: 1.45
    fontFeature: "tabular-nums"
  card-text:
    fontFamily: "Hanken Grotesk, system-ui, -apple-system, Segoe UI, sans-serif"
    fontSize: "14.5px"
    fontWeight: 500
    lineHeight: 1.4
  label:
    fontFamily: "Hanken Grotesk, system-ui, -apple-system, Segoe UI, sans-serif"
    fontSize: "12.5px"
    fontWeight: 500
    lineHeight: 1.45
rounded:
  xs: "5px"
  sm: "8px"
  md: "10px"
  lg: "14px"
  xl: "16px"
  full: "99px"
spacing:
  xs: "6px"
  sm: "8px"
  md: "12px"
  lg: "16px"
  xl: "20px"
  page-top: "28px"
components:
  card:
    backgroundColor: "{colors.surface}"
    textColor: "{colors.ink}"
    rounded: "{rounded.md}"
    padding: "12px"
  column:
    backgroundColor: "{colors.surface-2}"
    rounded: "{rounded.lg}"
    padding: "12px"
  button-default:
    backgroundColor: "{colors.surface}"
    textColor: "{colors.ink}"
    rounded: "{rounded.sm}"
    height: "34px"
    padding: "0 12px"
  button-ghost:
    backgroundColor: "{colors.bg}"
    textColor: "{colors.muted}"
    rounded: "{rounded.sm}"
    height: "34px"
  button-primary:
    backgroundColor: "{colors.accent}"
    textColor: "{colors.accent-ink}"
    rounded: "{rounded.sm}"
    height: "42px"
    padding: "0 16px"
  input:
    backgroundColor: "{colors.bg}"
    textColor: "{colors.ink}"
    rounded: "{rounded.sm}"
    height: "40px"
    padding: "0 12px"
  pill:
    backgroundColor: "{colors.surface-2}"
    textColor: "{colors.muted}"
    rounded: "6px"
    padding: "2px 7px"
  tag:
    backgroundColor: "{colors.accent-soft}"
    textColor: "{colors.accent}"
    rounded: "6px"
    padding: "1px 8px"
  slide-over:
    backgroundColor: "{colors.surface}"
    textColor: "{colors.ink}"
    width: "480px"
  user-row:
    backgroundColor: "{colors.bg}"
    rounded: "{rounded.md}"
    padding: "12px"
---

# Design System: Pendientes

## Overview

**Creative North Star: "El cuaderno bien hecho"**

Pendientes es una app de tareas que se siente cálida porque está bien ejecutada, no porque tenga disfraz. Sigue el estándar de la categoría (Linear, Todoist, Things 3): neutros fríos apenas tintados, una sola familia tipográfica, hilos de 1px, una elevación suave y un único acento. La jerarquía la dan el peso y el tamaño, no los adornos.

El color trabaja. El índigo marca selección, foco y acciones; el estado de cada tarea tiene su propio color funcional (pizarra, ámbar, verde); la prioridad alta y los errores usan rojo. Todo lo demás es neutro. La interfaz es mobile primero (16px mínimo de margen lateral) y existe en claro y oscuro desde las mismas variables.

**Key Characteristics:**
- Neutros fríos tintados hacia el azul, superficies blancas sobre fondo gris perla.
- Un solo acento índigo, más tres colores de estado y un rojo de alerta.
- Hanken Grotesk en todo, pesos 400/500/600, numerales tabulares.
- Radio base de 10px, bordes de 1px, una elevación en reposo y una al pasar el mouse.
- Íconos SVG de trazo (16px, stroke 1.8), heredan `currentColor`.

## Colors

Paleta fría y contenida: casi todo es neutro, el índigo aparece solo donde hay acción o foco, y el color de estado solo donde hay estado.

### Primary
- **Índigo de acción** (#3858E9 en claro, #8CA2FF en oscuro): `--accent`. Botón primario, marca del logo, foco, pestaña activa, "mover" en celular, barra de progreso de subtareas, check de subtareas, avatares y etiquetas. Su fondo suave (`--accent-soft`, #E9EEFF / #1D2547) se usa para halo de foco, columna destino de arrastre y selección de texto.

### Secondary (estados)
- **Pizarra** (#556074, `--pend`): Pendiente; también prioridad baja.
- **Ámbar quemado** (#A8480A, `--proc`): En proceso; también prioridad media (`--media`).
- **Verde** (#0B7A4B, `--comp`): Completado, tilde de tarea, barra de avance general, mensaje de éxito.
- Cada estado tiene su versión suave (`--pend-soft`, `--proc-soft`, `--comp-soft`) para la etiqueta de estado del panel.

### Tertiary
- **Rojo de alerta** (#C42B22 claro, #FF8077 oscuro, `--alta`): prioridad alta, vencidas, errores, eliminar.

### Neutral
- **Gris perla** (#F6F7F9, `--bg`): fondo de página y de campos dentro de paneles.
- **Blanco** (#FFFFFF, `--surface`): tarjetas, paneles, login.
- **Gris hielo** (#EEF0F4, `--surface-2`): hover, píldoras, pista de la barra, selector segmentado, fondo de columnas (mezclado al 55%).
- **Tinta** (#12151C, `--ink`), **Texto secundario** (#4B5565, `--muted`), **Texto terciario** (#667085, `--faint`).
- **Hilo** (#E2E6EC, `--line`) y **Hilo firme** (#CDD3DC, `--line-strong`): bordes y divisores.
- **Oscuro:** fondo #0E1116, superficie #151A22, superficie 2 #1B212B, tinta #E7EBF2, hilos #252C38 / #364050. Se activa por `prefers-color-scheme` o por `data-theme="dark"` en `:root`; `data-theme="light"` fuerza el claro.

### Named Rules
**The One Accent Rule.** El índigo es el único color de acción. Los colores de estado describen estado y no se reutilizan como decoración ni como botones.

**The Paired Theme Rule.** Todo color nuevo se declara como variable en `:root` y en sus dos bloques oscuros; nada de hex sueltos en componentes.

## Typography

**Display Font:** Hanken Grotesk (con system-ui, -apple-system, Segoe UI, sans-serif)
**Body Font:** Hanken Grotesk, misma familia
**Label/Mono Font:** no hay; las etiquetas usan la misma familia

**Character:** Un grotesco humanista y neutro, con tracking levemente cerrado en los títulos. La diferencia entre niveles la hacen el tamaño y el peso (600 títulos, 500 énfasis, 400 lectura), nunca la mayúscula ni una segunda familia.

### Hierarchy
- **Headline** (600, clamp(24px, 4vw, 30px), 1.15, -0.025em): título del tablero ("Mi tablero").
- **Title** (600, 21px, 1.3, -0.02em): título editable de la tarea en el panel. Login h2 22px; encabezado de administración 17px; marca 16px.
- **Body** (400, 14.5px, 1.45): base de la página, notas, subtareas, campos.
- **Card text** (500, 14.5px, 1.4): texto de tarjeta; al completarse baja a 400, gris y tachado.
- **Label** (500, 12.5-13.5px): etiquetas de campo, contadores, botones (13.5px), píldoras (12px), tags (11.5px). Porcentaje de avance 20px/600.

### Named Rules
**The Tabular Rule.** Los numerales son tabulares en todo el documento (`font-variant-numeric: tabular-nums` en `body`), para que contadores y fechas no salten.

**The Weight Ladder Rule.** Solo 400, 500 y 600. Sin itálicas ni versalitas para jerarquía.

## Layout

Contenedor centrado de 1200px máximo, margen lateral mínimo de 16px (respeta `env(safe-area-inset-*)`), 28px arriba y 72px abajo. Barra superior pegajosa de 56px con fondo translúcido y desenfoque. Debajo, encabezado con título y conteo a la izquierda y avance general (máx. 320px) a la derecha, y un tablero de tres columnas parejas con 14px de separación. Ritmo de espaciado en múltiplos de 2 y 4 (6, 8, 10, 12, 14, 16, 20).

En 760px o menos, o en dispositivos sin hover: el tablero pasa a una columna controlada por un selector segmentado de estado, los encabezados de columna se ocultan, el botón "mover" aparece en cada tarjeta y los objetivos táctiles crecen (tick 22px, botones 40px). Los paneles ocupan todo el ancho. Breakpoint único: 760px.

## Elevation & Depth

Híbrido y contenido: la profundidad en reposo es tonal (superficie blanca sobre columna grisácea) más un hilo de 1px; la sombra aparece como respuesta y para lo flotante. Una tarjeta completada pierde su sombra.

### Shadow Vocabulary
- **Reposo** (`box-shadow: 0 1px 2px rgba(18,21,28,.06), 0 0 0 1px rgba(18,21,28,.02)`, `--shadow`): tarjetas y segmento activo.
- **Elevada** (`0 6px 16px -4px rgba(18,21,28,.14), 0 2px 4px rgba(18,21,28,.06)`, `--shadow-up`): tarjeta con hover, tarjeta de login.
- **Flotante** (`0 16px 40px -12px rgba(18,21,28,.3)`, `--shadow-pop`): paneles laterales.
- **Halo de foco** (`0 0 0 3px var(--accent-soft)` más borde índigo): campos con foco.

### Named Rules
**The Quiet Shadow Rule.** Sombras suaves, difusas y con desplazamiento vertical; nunca desplazadas de borde duro. Tres niveles, no se inventa un cuarto.

## Shapes

Esquinas suaves en escala corta: 5px (casillas), 6-7px (píldoras, tags, marca), 8px (botones, campos), 10px (`--r`: tarjetas, filas de usuario), 14px (columnas), 16px (login), 99px (barras y chips), 50% (tick, avatar, puntos). Bordes de 1px en `--line`; estados vacíos con borde punteado de 1px en `--line-strong`, y la fila de agregar también punteada hasta recibir foco. Los paneles laterales llevan solo borde izquierdo.

## Components

### Barra superior
Pegajosa, 56px, fondo `--bg` al 88% con desenfoque y borde inferior. Marca a la izquierda (cuadrado índigo de 26px, radio 7px, tilde blanca, nombre 16px/600). A la derecha, nombre del usuario (oculto en celular) y botones fantasma "Usuarios" (solo admin) y "Salir".

### Botones
- **Forma:** radio 8px, borde de 1px, ícono SVG de 16px con 7px de separación.
- **Default** (`.btn`): superficie blanca, borde `--line`, 34px (40px en celular), texto 13.5px/500. Hover: `--surface-2`.
- **Ghost:** transparente, texto `--muted`; hover a `--ink` sobre `--surface-2`.
- **Primario** (agregar, login, crear usuario): fondo `--accent`, texto `--accent-ink`, 600, alto 38-44px; hover con `brightness(1.08)`.
- **Secundario pequeño** (`.btn-s`): contorno, 36px (32px dentro de filas de usuario).
- **Destructivo** ("Eliminar"): contorno rojo al 35%, texto rojo; en dos pasos queda "armado" con fondo rojo sólido.
- **Foco:** `outline: 2px solid var(--accent)` con 2px de separación.

### Tarjeta de tarea
Superficie blanca, radio 10px, borde `--line`, sombra de reposo, 12px de relleno, 9px entre filas. Arriba, tick circular de 18px (hover y marcado en verde) y texto 14.5px/500. Abajo, línea de metadatos con sangría de 28px: píldora de prioridad (punto de 6px + texto, tinte del color de prioridad), fecha (roja si está vencida), notas y subtareas con mini-barra de 24x4px. Arrastrable; durante el arrastre baja a 40% de opacidad y la columna destino se tiñe de `--accent-soft`.

### Columna y selector de estado
Columna con fondo gris al 55%, borde de 1px, radio 14px. Encabezado con ícono de estado de 18px coloreado (círculo punteado, medio lleno, con tilde), nombre 14px/600 y contador. Fila de agregar al pie: campo punteado de 38px más botón índigo cuadrado de 38px. En celular, el selector segmentado (pista `--surface-2`, radio 12px, opción activa blanca con sombra de reposo) reemplaza los encabezados.

### Campos
Fondo `--bg`, borde `--line`, radio 8px, 40px de alto (42px en administración, 44px en login), texto 14.5px. Hover: borde `--line-strong`. Foco: borde índigo más halo de 3px. Selects con chevrón SVG propio. Etiquetas de 12.5px/500 en `--muted` sobre el campo.

### Panel de detalle (slide-over)
Panel fijo a la derecha, 480px máx., fondo superficie, borde izquierdo y sombra flotante, con scrim `--scrim` detrás. Cabecera con etiqueta de estado (punto + nombre, tinte del estado) y botón de cerrar de 40px. Cuerpo con título editable que se revela al hover/foco, grilla de dos columnas de campos (una en celular), lista de subtareas con casillas cuadradas de 5px de radio que marcan en índigo, y pie con sello de fechas y "Eliminar". Entrada con deslizamiento de 20px en .24s, solo con movimiento permitido.

### Panel de administración (slide-over)
Mismo marco que el detalle, 560px. Cabecera con título 17px/600, pestañas "Usuarios" y "Responsables" (subrayado índigo de 2px en la activa, 44px de alto), búsqueda, y mensajes de estado (rojo error, verde éxito). Usuarios: botón desplegable "+ Nuevo usuario" con formulario; lista de filas (fondo `--bg`, borde, radio 10px) con avatar circular de iniciales sobre `--accent-soft`, nombre 600, email 12.5px, tag índigo (o rojo si está desactivado) y acciones pequeñas. Responsables: ayuda en `--muted` y filas con chips de 99px de radio con quita de 26px.

### Acceso
Pantalla completa sobre `--bg`; tarjeta de 380px, radio 16px, sombra elevada, 28px de relleno, campos de 44px y botón primario de ancho completo.

## Do's and Don'ts

### Do:
- **Do** declarar todo color como variable en `:root` y en los dos bloques oscuros, y consumirlo con `var(--...)`.
- **Do** usar `--accent` solo para acción, selección y foco; el color de estado solo para estado.
- **Do** tintar fondos de prioridad y vencida con `color-mix(in srgb, <color> 11%, var(--surface))` para que sigan el tema.
- **Do** mantener 16px de margen lateral mínimo y objetivos táctiles de 40px o más en celular (el área clicable puede ampliarse con un pseudoelemento).
- **Do** usar íconos SVG de trazo con `class="i"`, heredando `currentColor`.
- **Do** envolver transiciones en `prefers-reduced-motion: no-preference`; duraciones de .15s a .4s con `cubic-bezier(.16, 1, .3, 1)` para entradas.

### Don't:
- **Don't** introducir una segunda familia tipográfica ni pesos fuera de 400/500/600.
- **Don't** usar sombras de borde duro ni una elevación distinta de las tres definidas.
- **Don't** usar glifos de texto o emoji como íconos.
- **Don't** colorear una tarjeta entera por estado o prioridad; el color vive en píldoras, puntos e íconos.
- **Don't** repetir como regla del sistema los defectos listados en el reporte de deriva (blanco fijo sobre colores de estado, píldora de subtareas con regla muerta).
