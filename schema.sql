-- =====================================================================
--  SISTEMA DE ESTADISTICAS DE SOFTBALL  -  Esquema para SUPABASE
--  Uso: Supabase > SQL Editor > New query > pegar todo > Run
--  Es seguro ejecutarlo mas de una vez (usa IF NOT EXISTS / OR REPLACE).
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. CONFIGURACION (una sola fila: equipo y manager)
-- ---------------------------------------------------------------------
create table if not exists public.configuracion (
  id            smallint primary key default 1 check (id = 1),
  nombre_equipo text not null,
  manager       text not null,
  logo_url      text,
  updated_at    timestamptz not null default now()
);
-- Si ya habias ejecutado una version anterior del script, esto agrega la columna del logo:
alter table public.configuracion add column if not exists logo_url text;

-- ---------------------------------------------------------------------
-- 2. JUGADORES  (correlativo automatico; camiseta y cedula no se repiten)
-- ---------------------------------------------------------------------
create table if not exists public.jugadores (
  correlativo      bigint generated always as identity primary key,
  nombre_apellido  text    not null,
  cedula           text    not null unique,
  fecha_nacimiento date    not null,
  numero_camiseta  integer not null unique check (numero_camiseta between 0 and 999),
  foto_url         text,
  activo           boolean not null default true,   -- Status: true = Activo, false = Inactivo
  created_at       timestamptz not null default now()
);
-- Si ya habias ejecutado una version anterior del script, esto agrega el Status:
alter table public.jugadores add column if not exists activo boolean not null default true;

-- ---------------------------------------------------------------------
-- 3. TORNEOS Y EQUIPOS PARTICIPANTES
-- ---------------------------------------------------------------------
create table if not exists public.torneos (
  id         bigint generated always as identity primary key,
  nombre     text not null,
  created_at timestamptz not null default now()
);

create table if not exists public.torneo_equipos (
  id         bigint generated always as identity primary key,
  torneo_id  bigint  not null references public.torneos(id) on delete cascade,
  nombre     text    not null,
  es_nuestro boolean not null default false
);
create unique index if not exists torneo_equipos_unico
  on public.torneo_equipos (torneo_id, lower(nombre));

-- ---------------------------------------------------------------------
-- 4. JUEGOS
-- ---------------------------------------------------------------------
create table if not exists public.juegos (
  id         bigint generated always as identity primary key,
  torneo_id  bigint not null references public.torneos(id)        on delete cascade,
  rival_id   bigint not null references public.torneo_equipos(id) on delete restrict,
  fecha      date   not null,
  estado     text   not null default 'en_juego' check (estado in ('en_juego','finalizado')),
  forfeit    boolean not null default false,   -- true = el rival no se presento (victoria para nuestro equipo)
  created_at timestamptz not null default now()
);
-- Si ya habias ejecutado una version anterior del script, esto agrega el Forfeit:
alter table public.juegos add column if not exists forfeit boolean not null default false;

-- Carreras por entrada de los 2 equipos
create table if not exists public.juego_entradas (
  juego_id         bigint   not null references public.juegos(id) on delete cascade,
  entrada          smallint not null check (entrada >= 1),
  carreras_nuestras integer not null default 0 check (carreras_nuestras >= 0),
  carreras_rival    integer not null default 0 check (carreras_rival >= 0),
  primary key (juego_id, entrada)
);

-- Line up (orden al bate y posicion)
create table if not exists public.juego_lineup (
  id         bigint generated always as identity primary key,
  juego_id   bigint   not null references public.juegos(id) on delete cascade,
  orden      smallint not null check (orden >= 1),
  jugador_id bigint   not null references public.jugadores(correlativo) on delete restrict,
  posicion   text,
  rol        text     not null default 'titular' check (rol in ('titular','reserva','salio')),
  unique (juego_id, orden),
  unique (juego_id, jugador_id)
);
-- Si ya habias ejecutado una version anterior del script, esto la actualiza:
--   titular = en el orden al bate (orden 1..N) | reserva (orden 101+) | salio = sustituido (orden 201+)
alter table public.juego_lineup add column if not exists rol text not null default 'titular';
alter table public.juego_lineup drop constraint if exists juego_lineup_rol_check;
alter table public.juego_lineup add constraint juego_lineup_rol_check check (rol in ('titular','reserva','salio'));
alter table public.juego_lineup drop constraint if exists juego_lineup_orden_check;
alter table public.juego_lineup add constraint juego_lineup_orden_check check (orden >= 1);

-- Estadisticas de cada jugador en cada juego
--   vb=veces al bate, h=hits, d2=dobles, d3=triples, hr=jonrones,
--   ca=carreras anotadas, ci=carreras impulsadas, bb=bases por bolas,
--   k=ponches, hbp=golpeado, sf=fly de sacrificio, br=bases robadas, e=errores
create table if not exists public.juego_stats (
  id         bigint generated always as identity primary key,
  juego_id   bigint not null references public.juegos(id)             on delete cascade,
  jugador_id bigint not null references public.jugadores(correlativo) on delete restrict,
  vb  integer not null default 0 check (vb  >= 0),
  h   integer not null default 0 check (h   >= 0),
  d2  integer not null default 0 check (d2  >= 0),
  d3  integer not null default 0 check (d3  >= 0),
  hr  integer not null default 0 check (hr  >= 0),
  ca  integer not null default 0 check (ca  >= 0),
  ci  integer not null default 0 check (ci  >= 0),
  bb  integer not null default 0 check (bb  >= 0),
  k   integer not null default 0 check (k   >= 0),
  hbp integer not null default 0 check (hbp >= 0),
  sf  integer not null default 0 check (sf  >= 0),
  br  integer not null default 0 check (br  >= 0),
  e   integer not null default 0 check (e   >= 0),
  unique (juego_id, jugador_id),
  check (h <= vb),
  check (d2 + d3 + hr <= h),
  check (h + k <= vb)
);

create index if not exists idx_juegos_torneo      on public.juegos (torneo_id);
create index if not exists idx_juego_stats_juego  on public.juego_stats (juego_id);
create index if not exists idx_juego_stats_jug    on public.juego_stats (jugador_id);
create index if not exists idx_juego_lineup_juego on public.juego_lineup (juego_id);

-- ---------------------------------------------------------------------
-- 5. VISTAS DE CONSULTA (opcionales, utiles para reportes en SQL)
-- ---------------------------------------------------------------------

-- Marcador y resultado de cada juego
create or replace view public.v_juegos_resultado with (security_invoker = true) as
select
  j.id as juego_id, j.torneo_id, t.nombre as torneo, j.fecha, j.estado,
  r.nombre as rival,
  coalesce(sum(e.carreras_nuestras),0)::int as carreras_nuestras,
  coalesce(sum(e.carreras_rival),0)::int    as carreras_rival,
  case
    when j.estado <> 'finalizado' then null
    when coalesce(sum(e.carreras_nuestras),0) > coalesce(sum(e.carreras_rival),0) then 'G'
    when coalesce(sum(e.carreras_nuestras),0) < coalesce(sum(e.carreras_rival),0) then 'P'
    else 'E'
  end as resultado,
  j.forfeit
from public.juegos j
join public.torneos t          on t.id = j.torneo_id
join public.torneo_equipos r   on r.id = j.rival_id
left join public.juego_entradas e on e.juego_id = j.id
group by j.id, t.nombre, r.nombre;

-- Record ganados / perdidos / empatados por torneo
create or replace view public.v_torneo_record with (security_invoker = true) as
select
  t.id as torneo_id, t.nombre,
  count(v.juego_id) filter (where v.estado = 'finalizado')::int as juegos,
  count(*) filter (where v.resultado = 'G')::int as ganados,
  count(*) filter (where v.resultado = 'P')::int as perdidos,
  count(*) filter (where v.resultado = 'E')::int as empatados
from public.torneos t
left join public.v_juegos_resultado v on v.torneo_id = t.id
group by t.id, t.nombre;

-- Estadisticas acumuladas por jugador con AVG, OBP, SLG y OPS
create or replace view public.v_stats_acumuladas with (security_invoker = true) as
with s as (
  select p.correlativo, p.numero_camiseta, p.nombre_apellido,
         count(st.id)::int as jj,
         coalesce(sum(st.vb),0)::int  as vb,  coalesce(sum(st.h),0)::int   as h,
         coalesce(sum(st.d2),0)::int  as d2,  coalesce(sum(st.d3),0)::int  as d3,
         coalesce(sum(st.hr),0)::int  as hr,  coalesce(sum(st.ca),0)::int  as ca,
         coalesce(sum(st.ci),0)::int  as ci,  coalesce(sum(st.bb),0)::int  as bb,
         coalesce(sum(st.k),0)::int   as k,   coalesce(sum(st.hbp),0)::int as hbp,
         coalesce(sum(st.sf),0)::int  as sf,  coalesce(sum(st.br),0)::int  as br,
         coalesce(sum(st.e),0)::int   as e
  from public.jugadores p
  left join public.juego_stats st on st.jugador_id = p.correlativo
  group by p.correlativo, p.numero_camiseta, p.nombre_apellido
)
select s.*,
  case when vb > 0 then round(h::numeric / vb, 3) else 0 end as avg,
  case when (vb+bb+hbp+sf) > 0 then round((h+bb+hbp)::numeric / (vb+bb+hbp+sf), 3) else 0 end as obp,
  case when vb > 0 then round((h + d2 + 2*d3 + 3*hr)::numeric / vb, 3) else 0 end as slg,
  (case when (vb+bb+hbp+sf) > 0 then round((h+bb+hbp)::numeric / (vb+bb+hbp+sf), 3) else 0 end
   + case when vb > 0 then round((h + d2 + 2*d3 + 3*hr)::numeric / vb, 3) else 0 end) as ops
from s;

-- ---------------------------------------------------------------------
-- 6. ALMACENAMIENTO DE FOTOS DE JUGADORES (bucket publico)
-- ---------------------------------------------------------------------
insert into storage.buckets (id, name, public)
values ('fotos-jugadores', 'fotos-jugadores', true)
on conflict (id) do nothing;

-- ---------------------------------------------------------------------
-- 7. PERFILES, USUARIOS Y PERMISOS
--    Permisos disponibles (texto "modulo.accion"):
--      inicio.ver
--      jugadores.ver | crear | editar | eliminar
--      torneos.ver   | crear
--      juegos.ver    | crear (registrar juego) | anotar (estadisticas y cambios) | eliminar
--      resultados.ver
--      config.ver    | editar
--      usuarios.gestionar (crear usuarios y editar perfiles)
-- ---------------------------------------------------------------------
create table if not exists public.perfiles (
  id          bigint generated always as identity primary key,
  nombre      text   not null unique,
  descripcion text,
  permisos    text[] not null default '{}',
  es_sistema  boolean not null default false,
  created_at  timestamptz not null default now()
);

create table if not exists public.usuarios (
  id         uuid primary key references auth.users(id) on delete cascade,
  email      text,
  nombre     text,
  perfil_id  bigint  not null references public.perfiles(id) on delete restrict,
  activo     boolean not null default true,
  created_at timestamptz not null default now()
);
create index if not exists idx_usuarios_perfil on public.usuarios (perfil_id);

-- Perfiles base (los cuatro primeros se pueden editar desde la app, excepto Administrador)
insert into public.perfiles (nombre, descripcion, permisos, es_sistema) values
 ('Administrador', 'Acceso total, incluye usuarios y perfiles',
   array['inicio.ver','jugadores.ver','jugadores.crear','jugadores.editar','jugadores.eliminar',
         'torneos.ver','torneos.crear','juegos.ver','juegos.crear','juegos.anotar','juegos.eliminar',
         'resultados.ver','config.ver','config.editar','usuarios.gestionar'], true),
 ('Manager', 'Maneja todo el equipo, sin administrar usuarios',
   array['inicio.ver','jugadores.ver','jugadores.crear','jugadores.editar','jugadores.eliminar',
         'torneos.ver','torneos.crear','juegos.ver','juegos.crear','juegos.anotar','juegos.eliminar',
         'resultados.ver','config.ver','config.editar'], false),
 ('Anotador', 'Registra juegos y anota las estadisticas',
   array['inicio.ver','jugadores.ver','torneos.ver','juegos.ver','juegos.crear','juegos.anotar','resultados.ver'], false),
 ('Consulta', 'Solo puede ver la informacion',
   array['inicio.ver','jugadores.ver','torneos.ver','juegos.ver','resultados.ver'], false),
 ('Sin acceso', 'Cuenta nueva pendiente de aprobacion: no ve nada', '{}', true)
on conflict (nombre) do nothing;

-- El Administrador siempre tiene todos los permisos (se actualiza si se agregan nuevos)
update public.perfiles set es_sistema = true,
  permisos = array['inicio.ver','jugadores.ver','jugadores.crear','jugadores.editar','jugadores.eliminar',
                   'torneos.ver','torneos.crear','juegos.ver','juegos.crear','juegos.anotar','juegos.eliminar',
                   'resultados.ver','config.ver','config.editar','usuarios.gestionar']
where nombre = 'Administrador';

-- Funciones que usan las politicas de seguridad
create or replace function public.tiene_permiso(p text) returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((select p = any(pf.permisos)
                   from public.usuarios u join public.perfiles pf on pf.id = u.perfil_id
                   where u.id = auth.uid() and u.activo), false);
$$;

create or replace function public.acceso_activo() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((select cardinality(pf.permisos) > 0
                   from public.usuarios u join public.perfiles pf on pf.id = u.perfil_id
                   where u.id = auth.uid() and u.activo), false);
$$;

revoke all on function public.tiene_permiso(text), public.acceso_activo() from public, anon;
grant execute on function public.tiene_permiso(text), public.acceso_activo() to authenticated;

-- Cada usuario nuevo de Supabase Auth recibe su fila en "usuarios":
--   * el primero (mientras no exista ningun Administrador activo) queda como Administrador
--   * los demas quedan como "Sin acceso" hasta que un administrador les asigne un perfil
create or replace function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
declare v_perfil bigint;
begin
  if not exists (select 1 from public.usuarios u join public.perfiles pf on pf.id = u.perfil_id
                 where pf.nombre = 'Administrador' and u.activo) then
    select id into v_perfil from public.perfiles where nombre = 'Administrador';
  else
    select id into v_perfil from public.perfiles where nombre = 'Sin acceso';
  end if;
  insert into public.usuarios (id, email, nombre, perfil_id)
  values (new.id, new.email, split_part(new.email, '@', 1), v_perfil)
  on conflict (id) do nothing;
  return new;
end $$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users
  for each row execute function public.handle_new_user();

-- Usuarios que ya existian antes de este script: el mas antiguo es Administrador, los demas "Sin acceso"
insert into public.usuarios (id, email, nombre, perfil_id)
select au.id, au.email, split_part(au.email, '@', 1),
  (select id from public.perfiles where nombre =
     case when au.id = (select id from auth.users order by created_at asc limit 1)
               and not exists (select 1 from public.usuarios u2 join public.perfiles p2 on p2.id = u2.perfil_id
                               where p2.nombre = 'Administrador')
          then 'Administrador' else 'Sin acceso' end)
from auth.users au
where not exists (select 1 from public.usuarios u where u.id = au.id);

-- Protecciones: nunca dejar el sistema sin Administrador, ni tocar los perfiles del sistema
create or replace function public.proteger_ultimo_admin() returns trigger
language plpgsql security definer set search_path = public as $$
declare v_admin bigint; v_otros int;
begin
  select id into v_admin from public.perfiles where nombre = 'Administrador';
  if old.perfil_id = v_admin and old.activo then
    if tg_op = 'DELETE' or new.perfil_id <> v_admin or not new.activo then
      select count(*) into v_otros from public.usuarios where perfil_id = v_admin and activo and id <> old.id;
      if v_otros = 0 then raise exception 'Debe existir al menos un Administrador activo'; end if;
    end if;
  end if;
  if tg_op = 'DELETE' then return old; end if;
  return new;
end $$;
drop trigger if exists trg_proteger_ultimo_admin on public.usuarios;
create trigger trg_proteger_ultimo_admin before update or delete on public.usuarios
  for each row execute function public.proteger_ultimo_admin();

create or replace function public.proteger_perfiles() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then            -- ejecutado desde el SQL Editor: se permite
    if tg_op = 'DELETE' then return old; end if; return new;
  end if;
  if tg_op = 'DELETE' then
    if old.es_sistema then raise exception 'Los perfiles del sistema no se pueden eliminar'; end if;
    return old;
  end if;
  if old.es_sistema then new.nombre := old.nombre; new.es_sistema := true; end if;
  if old.nombre = 'Administrador' then new.permisos := old.permisos; end if;
  if old.nombre = 'Sin acceso'    then new.permisos := '{}'; end if;
  return new;
end $$;
drop trigger if exists trg_proteger_perfiles on public.perfiles;
create trigger trg_proteger_perfiles before update or delete on public.perfiles
  for each row execute function public.proteger_perfiles();

-- ---------------------------------------------------------------------
-- 8. SEGURIDAD (RLS) POR PERMISOS
--    * LEER: cualquier usuario activo con un perfil que tenga algun permiso.
--    * ESCRIBIR: solo quien tenga el permiso correspondiente.
--    * Quien se registre por su cuenta queda como "Sin acceso" y no ve ni modifica nada.
-- ---------------------------------------------------------------------
alter table public.perfiles enable row level security;
alter table public.usuarios enable row level security;
revoke all on public.perfiles, public.usuarios from anon;

drop policy if exists "perfiles_leer"     on public.perfiles;
drop policy if exists "perfiles_insertar" on public.perfiles;
drop policy if exists "perfiles_editar"   on public.perfiles;
drop policy if exists "perfiles_borrar"   on public.perfiles;
create policy "perfiles_leer"     on public.perfiles for select to authenticated using (true);
create policy "perfiles_insertar" on public.perfiles for insert to authenticated
  with check (public.tiene_permiso('usuarios.gestionar'));
create policy "perfiles_editar"   on public.perfiles for update to authenticated
  using (public.tiene_permiso('usuarios.gestionar')) with check (public.tiene_permiso('usuarios.gestionar'));
create policy "perfiles_borrar"   on public.perfiles for delete to authenticated
  using (public.tiene_permiso('usuarios.gestionar'));

drop policy if exists "usuarios_leer"   on public.usuarios;
drop policy if exists "usuarios_editar" on public.usuarios;
create policy "usuarios_leer"   on public.usuarios for select to authenticated
  using (id = auth.uid() or public.tiene_permiso('usuarios.gestionar'));
create policy "usuarios_editar" on public.usuarios for update to authenticated
  using (public.tiene_permiso('usuarios.gestionar')) with check (public.tiene_permiso('usuarios.gestionar'));

-- Lectura de las tablas del sistema
do $$
declare t text;
begin
  foreach t in array array['configuracion','jugadores','torneos','torneo_equipos',
                           'juegos','juego_entradas','juego_lineup','juego_stats']
  loop
    execute format('alter table public.%I enable row level security', t);
    execute format('drop policy if exists "acceso_total_%s" on public.%I', t, t);
    execute format('drop policy if exists "lectura_%s" on public.%I', t, t);
    execute format('create policy "lectura_%s" on public.%I for select to authenticated using (public.acceso_activo())', t, t);
  end loop;
end $$;

-- Escritura segun permiso
do $$
declare r record;
begin
  for r in select * from (values
    ('configuracion','insert','config.editar'),   ('configuracion','update','config.editar'),
    ('jugadores','insert','jugadores.crear'),     ('jugadores','update','jugadores.editar'),
    ('jugadores','delete','jugadores.eliminar'),
    ('torneos','insert','torneos.crear'),         ('torneo_equipos','insert','torneos.crear'),
    ('juegos','insert','juegos.crear'),           ('juegos','update','juegos.anotar'),
    ('juegos','delete','juegos.eliminar'),
    ('juego_entradas','update','juegos.anotar'),  ('juego_entradas','delete','juegos.anotar'),
    ('juego_lineup','update','juegos.anotar'),    ('juego_lineup','delete','juegos.anotar'),
    ('juego_stats','update','juegos.anotar'),     ('juego_stats','delete','juegos.anotar')
  ) as v(tabla, cmd, perm)
  loop
    execute format('drop policy if exists "perm_%s_%s" on public.%I', r.tabla, r.cmd, r.tabla);
    if r.cmd = 'insert' then
      execute format('create policy "perm_%s_%s" on public.%I for insert to authenticated with check (public.tiene_permiso(%L))',
                     r.tabla, r.cmd, r.tabla, r.perm);
    elsif r.cmd = 'update' then
      execute format('create policy "perm_%s_%s" on public.%I for update to authenticated using (public.tiene_permiso(%L)) with check (public.tiene_permiso(%L))',
                     r.tabla, r.cmd, r.tabla, r.perm, r.perm);
    else
      execute format('create policy "perm_%s_%s" on public.%I for delete to authenticated using (public.tiene_permiso(%L))',
                     r.tabla, r.cmd, r.tabla, r.perm);
    end if;
  end loop;
end $$;

-- Registrar un juego (o agregar entradas / cambios durante el juego) inserta en estas tablas
do $$
declare t text;
begin
  foreach t in array array['juego_entradas','juego_lineup','juego_stats']
  loop
    execute format('drop policy if exists "perm_%s_insert" on public.%I', t, t);
    execute format('create policy "perm_%s_insert" on public.%I for insert to authenticated with check (public.tiene_permiso(%L) or public.tiene_permiso(%L))',
                   t, t, 'juegos.crear', 'juegos.anotar');
  end loop;
end $$;

-- Pantalla de login: permite leer SOLO el nombre del equipo y su logo sin haber
-- iniciado sesion (el manager y demas datos siguen protegidos).
drop policy if exists "config_publica_lectura" on public.configuracion;
create policy "config_publica_lectura" on public.configuracion
  for select to anon using (true);
revoke all on public.configuracion from anon;
grant select (nombre_equipo, logo_url) on public.configuracion to anon;

-- Fotos (el bucket es publico para mostrar las imagenes; subir o borrar requiere permiso)
drop policy if exists "fotos_lectura"       on storage.objects;
drop policy if exists "fotos_subida"        on storage.objects;
drop policy if exists "fotos_actualizacion" on storage.objects;
drop policy if exists "fotos_borrado"       on storage.objects;

create policy "fotos_lectura" on storage.objects for select to authenticated
  using (bucket_id = 'fotos-jugadores' and public.acceso_activo());
create policy "fotos_subida" on storage.objects for insert to authenticated
  with check (bucket_id = 'fotos-jugadores' and (public.tiene_permiso('jugadores.crear')
              or public.tiene_permiso('jugadores.editar') or public.tiene_permiso('config.editar')));
create policy "fotos_actualizacion" on storage.objects for update to authenticated
  using (bucket_id = 'fotos-jugadores' and (public.tiene_permiso('jugadores.editar') or public.tiene_permiso('config.editar')));
create policy "fotos_borrado" on storage.objects for delete to authenticated
  using (bucket_id = 'fotos-jugadores' and (public.tiene_permiso('jugadores.editar') or public.tiene_permiso('config.editar')));
