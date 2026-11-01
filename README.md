# Sistema de Estadísticas de Softball

Aplicación web (un solo archivo HTML) con base de datos en **Supabase** para llevar las estadísticas de un equipo de softball.

## Versión móvil
- `movil.html` es la versión para celulares: barra de pestañas abajo, botones grandes y una ficha por jugador para anotar el juego con el pulgar.
- Si abres `index.html` desde un celular, te lleva sola a la versión móvil. Para ver la de escritorio agrega `?desktop` a la dirección.
- Es instalable como app: en Android, menú del navegador → *Instalar aplicación*; en iPhone, Compartir → *Añadir a pantalla de inicio*.
- Con **GitHub Pages** activado (*Settings → Pages → rama `main`, carpeta raíz*) se abre desde cualquier celular con el enlace que te da GitHub.

## Módulos
- **Inicio**: estadísticas acumuladas de todos los jugadores y del equipo, y récord de ganados/perdidos.
- **Registrar Jugador**: datos, número de camiseta único, foto y ficha técnica con los colores del logo del equipo.
- **Registrar Torneo**: torneos, equipos participantes y récord por torneo.
- **Juego**: line up de 12 (ampliable a 15), reserva, cambios durante el juego, carreras por entrada y estadísticas en vivo.
- **Resultados**: marcador y estadísticas por jugador de cada juego, con el jugador más valioso.
- **Configuración**: nombre del equipo, manager e imagen del equipo.

Incluye inicio de sesión con Supabase Auth.

## Puesta en marcha
1. En Supabase abre **SQL Editor**, pega todo `schema.sql` y ejecútalo (se puede volver a ejecutar sin perder datos).
2. En **Authentication → Users → Add user** crea tu usuario (marca *Auto Confirm User*).
3. Abre `index.html` en el navegador o publícalo en un hosting estático (por ejemplo GitHub Pages).
4. La app ya viene conectada al proyecto de Supabase (URL y clave pública *publishable* al inicio del script en `index.html`). Para usar otro proyecto, cambia `SUPABASE_URL` y `SUPABASE_KEY`. Nunca pongas aquí la clave `service_role`.

## Jugador más valioso
Bases totales + carreras anotadas + carreras impulsadas + ½ (BB + HBP + BR) − ½ errores − ¼ ponches.
