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
  created_at       timestamptz not null default now()
);

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
  created_at timestamptz not null default now()
);

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
  end as resultado
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
-- 7. SEGURIDAD (RLS)
--    Solo los usuarios con sesion iniciada (Supabase Auth) pueden leer o
--    escribir. Los usuarios se crean en Authentication > Users del panel.
-- ---------------------------------------------------------------------
do $$
declare t text;
begin
  foreach t in array array['configuracion','jugadores','torneos','torneo_equipos',
                           'juegos','juego_entradas','juego_lineup','juego_stats']
  loop
    execute format('alter table public.%I enable row level security', t);
    execute format('drop policy if exists "acceso_total_%1$s" on public.%1$I', t);
    execute format('create policy "acceso_total_%1$s" on public.%1$I
                    for all to authenticated using (true) with check (true)', t);
  end loop;
end $$;

-- Pantalla de login: permite leer SOLO el nombre del equipo y su logo sin haber
-- iniciado sesion (el manager y demas datos siguen protegidos).
drop policy if exists "config_publica_lectura" on public.configuracion;
create policy "config_publica_lectura" on public.configuracion
  for select to anon using (true);
revoke all on public.configuracion from anon;
grant select (nombre_equipo, logo_url) on public.configuracion to anon;

drop policy if exists "fotos_lectura"       on storage.objects;
drop policy if exists "fotos_subida"        on storage.objects;
drop policy if exists "fotos_actualizacion" on storage.objects;
drop policy if exists "fotos_borrado"       on storage.objects;

create policy "fotos_lectura" on storage.objects for select to authenticated
  using (bucket_id = 'fotos-jugadores');
create policy "fotos_subida" on storage.objects for insert to authenticated
  with check (bucket_id = 'fotos-jugadores');
create policy "fotos_actualizacion" on storage.objects for update to authenticated
  using (bucket_id = 'fotos-jugadores');
create policy "fotos_borrado" on storage.objects for delete to authenticated
  using (bucket_id = 'fotos-jugadores');
