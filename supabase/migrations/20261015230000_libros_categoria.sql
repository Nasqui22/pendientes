-- Categoría de cada libro de la Biblioteca. Solo agrega una columna con valor por defecto.
alter table public.libros
  add column if not exists categoria text not null default 'general'
  check (categoria in ('power_automate', 'merlin', 'general', 'ayuda'));
