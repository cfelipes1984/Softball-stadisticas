# Sistema de Estadísticas de Softball

Aplicación web (un solo archivo HTML) con base de datos en **Supabase** para llevar las estadísticas de un equipo de softball.

## Versión móvil
- `movil.html` es la versión para celulares: barra de pestañas abajo, botones grandes y una ficha por jugador para anotar el juego con el pulgar.
- Si abres `index.html` desde un celular, te lleva sola a la versión móvil. Para ver la de escritorio agrega `?desktop` a la dirección.
- Es instalable como app: en Android, menú del navegador → *Instalar aplicación*; en iPhone, Compartir → *Añadir a pantalla de inicio*.
- Con **GitHub Pages** activado (*Settings → Pages → rama `main`, carpeta raíz*) se abre desde cualquier celular con el enlace que te da GitHub.

## Usuarios, perfiles y permisos
Cada usuario tiene un **perfil** y cada perfil una lista de **permisos**. El módulo **Usuarios y Perfiles** (solo para quien tenga el permiso de administrar) permite crear usuarios, cambiarles el perfil, desactivarlos y editar los permisos de cada perfil o crear perfiles nuevos.

| Perfil | Qué puede hacer |
|---|---|
| **Administrador** | Todo, incluido usuarios y perfiles (no se puede modificar) |
| **Manager** | Todo el equipo: jugadores, torneos, juegos, configuración; sin administrar usuarios |
| **Anotador** | Registrar juegos y anotar estadísticas y cambios; solo ver lo demás |
| **Consulta** | Solo ver |
| **Sin acceso** | Cuenta nueva pendiente de aprobación: no ve nada |

Permisos disponibles: ver inicio; jugadores (ver, registrar, editar, eliminar); torneos (ver, registrar); juegos (ver, registrar, anotar, eliminar); ver resultados; configuración (ver, modificar); administrar usuarios y perfiles.

Los permisos se hacen cumplir en la **base de datos** (Row Level Security), no solo en la pantalla. Quien se registre por su cuenta queda como *Sin acceso* hasta que un administrador le asigne un perfil. Siempre debe existir al menos un Administrador activo.

> Recomendado: si vas a crear los usuarios solo desde Supabase, desactiva *Allow new users to sign up* en *Authentication → Sign In / Providers*. Si quieres crearlos desde la app, déjalo activado.

## Módulos
- **Inicio**: estadísticas acumuladas de todos los jugadores y del equipo, y récord de ganados/perdidos.
- **Registrar Jugador**: datos, número de camiseta único, foto y ficha técnica con los colores del logo del equipo.
- **Registrar Torneo**: torneos, equipos participantes y récord por torneo.
- **Juego**: line up de 12 (ampliable a 15), reserva, cambios durante el juego, carreras por entrada y estadísticas en vivo.
- **Resultados**: marcador y estadísticas por jugador de cada juego, con el jugador más valioso.
- **Usuarios y Perfiles**: usuarios, perfiles y permisos.
- **Configuración** (siempre el último): nombre del equipo, manager e imagen del equipo.

Incluye inicio de sesión con Supabase Auth.

## Puesta en marcha
1. En Supabase abre **SQL Editor**, pega todo `schema.sql` y ejecútalo (se puede volver a ejecutar sin perder datos).
2. En **Authentication → Users → Add user** crea tu usuario (marca *Auto Confirm User*). **El primer usuario que se crea queda como Administrador** automáticamente.
3. Abre `index.html` en el navegador o publícalo en un hosting estático (por ejemplo GitHub Pages).
4. La app ya viene conectada al proyecto de Supabase (URL y clave pública *publishable* al inicio del script en `index.html`). Para usar otro proyecto, cambia `SUPABASE_URL` y `SUPABASE_KEY`. Nunca pongas aquí la clave `service_role`.

## Jugador más valioso
Bases totales + carreras anotadas + carreras impulsadas + ½ (BB + HBP + BR) − ½ errores − ¼ ponches.
