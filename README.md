# CopiapoGO! — Directorio de Entrenadores

Sitio web estático para el club de Pokémon GO **CopiapoGO!** (Copiapó, Región de
Atacama). Permite que los miembros se registren en un directorio compartido con
sus datos de juego, y que cualquier miembro pueda buscar a otros entrenadores.

- Acceso protegido por un código de club compartido.
- Registro individual (nombre, ID, equipo, frecuencia de juego, disponibilidad
  remota, comuna, Pokémon favorito, foto del QR de amigo, etc.).
- Directorio buscable con filtros.
- Contador de entrenadores registrados (total + por frecuencia de juego).
- Backend: **Firebase Firestore**, plan gratuito "Spark" — suficiente para un
  club de decenas o cientos de miembros, **sin necesitar tarjeta de crédito**.
  (No se usa Firebase Storage: desde fines de 2024 Google exige el plan de
  pago Blaze para activarlo. En vez de eso, la foto del código QR se
  comprime en el navegador y se guarda directo dentro del registro del
  jugador en Firestore — sigue siendo 100% gratis.)

---

## 0. Instalación automática (opcional)

Si prefieres no hacer los pasos 2 y 4 a mano, hay un script que automatiza casi
todo — crear el proyecto Firebase, registrar la app, pegar la configuración,
publicar las reglas, crear el repo en GitHub y activar GitHub Pages. Corre en
**tu computador** (no dentro de un chat) porque necesita que inicies sesión con
tu propia cuenta de Google y de GitHub; el script se detiene en cada paso a
esperar tu confirmación.

**En Mac o Linux** (Terminal):

```bash
cd copiapogo
bash scripts/setup-firebase-github.sh
```

**En Windows** (PowerShell — no uses el Símbolo del sistema/CMD, y NO hagas
doble clic a los archivos `.sh` ni `.js`, ábrelos siempre desde una terminal):

```powershell
cd copiapogo
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
.\scripts\setup-firebase-github.ps1
```

(El `Set-ExecutionPolicy` de arriba solo aplica a esa ventana de PowerShell;
Windows bloquea por defecto los scripts `.ps1` descargados de internet.)

Ambas versiones requieren tener instalado Node.js y [GitHub CLI](https://cli.github.com)
(`gh`); la Firebase CLI se instala sola si falta. Todo el proceso queda dentro
del plan gratuito de Firebase — no se activa Storage ni se pide tarjeta en
ningún paso. Si prefieres hacerlo todo manualmente, sigue las secciones 2 a 4
de abajo.

> **Sobre el ID del proyecto:** Firebase/Google Cloud solo aceptan minúsculas,
> números y guiones (nada de mayúsculas ni espacios), y debe empezar con una
> letra. El script corrige automáticamente lo que escribas para que cumpla esta
> regla. Si aun así falla la creación del proyecto, la causa más común es que
> ese ID ya lo usa otra persona en el mundo (son globales, no solo dentro de tu
> cuenta) — prueba con otro más específico.

---

## 1. Estructura del proyecto

```
copiapogo/
├── index.html          → Página de login (código de acceso)
├── directorio.html      → Directorio + formulario de registro (requiere login)
├── css/style.css         → Estilos y paleta de colores
├── js/auth.js            → Control de acceso por código
├── js/firebase-config.js → ⚠️ AQUÍ debes pegar tus llaves de Firebase
├── js/directory.js       → Lógica de registro, búsqueda y contador
├── assets/logo.png              → Logo del club
├── assets/logo-transparent.png  → Logo recortado en círculo (favicon/header)
├── firestore.rules       → Reglas de seguridad de Firestore (ver sección 2.1)
├── firebase.json         → Configuración para `firebase deploy`
└── scripts/
    ├── setup-firebase-github.sh    → Instalador automático (Mac/Linux, ver sección 0)
    ├── setup-firebase-github.ps1   → Instalador automático (Windows, ver sección 0)
    └── inject-firebase-config.js   → Helper que usan ambos instaladores
```

## 2. Crear tu proyecto Firebase (gratis, ~5 minutos)

1. Entra a **https://console.firebase.google.com/** con una cuenta Google del club.
2. **Crear un proyecto** → ponle un nombre, por ejemplo `copiapogo-directorio`.
   No necesitas activar Google Analytics.
3. Dentro del proyecto, ve a **Configuración del proyecto** (ícono ⚙️ arriba a la
   izquierda) → pestaña **General** → sección **"Tus apps"** → botón **</>** (Web).
4. Ponle un apodo a la app (ej. "CopiapoGO Web") y presiona **Registrar app**.
   **No** marques "Configurar también Firebase Hosting" (usaremos GitHub Pages).
5. Firebase te mostrará un bloque `firebaseConfig = { ... }`. Copia esos valores
   y pégalos en **`js/firebase-config.js`**, reemplazando los textos que dicen
   `REEMPLAZA_...`.

### 2.1 Activar Firestore Database

1. Menú lateral izquierdo → **Compilación → Firestore Database** → **Crear base de datos**.
2. Elige la ubicación más cercana (por ejemplo `southamerica-east1`).
3. Empieza en **modo producción** (no en modo de prueba).
4. Cuando esté creada, ve a la pestaña **Reglas** y reemplaza todo por esto:

```
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    match /jugadores/{docId} {
      allow read: if true;

      allow create: if
        request.resource.data.keys().hasAll(
          ['nombreJugador','codigoID','equipo','frecuencia',
           'disponibilidadRemoto','comuna','pokemonFavorito','fechaRegistro'])
        && request.resource.data.nombreJugador is string
        && request.resource.data.nombreJugador.size() > 0
        && request.resource.data.nombreJugador.size() < 60
        && request.resource.data.codigoID is string
        && request.resource.data.codigoID.size() > 0
        && request.resource.data.codigoID.size() < 30
        && request.resource.data.equipo in ['valor','sabiduria','instinto']
        && request.resource.data.frecuencia in ['activo','eventual','ocasional']
        && request.resource.data.disponibilidadRemoto in
           ['cuenta_conmigo','tal_vez','no_juego_remotos'];

      // Nadie puede editar ni borrar registros desde la web pública.
      // Los administradores del club pueden hacerlo desde la consola de Firebase.
      allow update, delete: if false;

      // La foto del QR vive en un sub-documento aparte (no en Storage, que
      // ahora exige el plan de pago Blaze) para que listar/buscar el
      // directorio no tenga que descargar todas las imágenes de una vez.
      match /qr/{qrDoc} {
        allow read: if true;
        allow create: if
          request.resource.data.keys().hasAll(['data', 'fechaRegistro'])
          && request.resource.data.data is string
          && request.resource.data.data.size() < 750000;
        allow update, delete: if false;
      }
    }
  }
}
```

5. Presiona **Publicar**.

> Con estas reglas, cualquier persona puede **leer** el directorio (para poder
> buscarse entre sí) y **crear** un nuevo registro con datos válidos, pero nadie
> puede editar ni borrar registros ajenos desde el navegador. Para borrar un
> registro duplicado, falso o de alguien que se salió del club, un administrador
> lo hace directamente desde la consola de Firebase (Firestore Database → colección
> `jugadores`).
>
> **¿Por qué no se usa Firebase Storage?** Desde fines de 2024, Google exige
> tener el plan de pago Blaze (con tarjeta asociada, aunque no te cobren si no
> superas la cuota gratuita) para poder activar Storage en un proyecto nuevo.
> Para no depender de eso, la foto del QR se comprime en el navegador de cada
> jugador y se guarda directo como imagen dentro de Firestore — que sigue
> siendo 100% gratis sin tarjeta. La única diferencia práctica es que las
> fotos deben ser livianas (el sitio las comprime solo, automáticamente).

## 3. Probar el sitio en tu computador

No necesitas instalar nada especial, pero los navegadores bloquean los módulos de
JavaScript (`type="module"`) si abres el `.html` directamente con doble clic. Usa un
servidor local simple:

```bash
cd copiapogo
python3 -m http.server 8000
```

Y abre `http://localhost:8000` en tu navegador.

**Código de acceso al sitio:** `COPIAPOGO2026@TACAM@`

> Importante: este código es solo una barrera de privacidad para que gente fuera
> del club no entre a curiosear — no es un sistema de seguridad real, ya que el
> código queda visible en el código fuente (`js/auth.js`). No es necesario cambiarlo,
> pero si el código se filtra ampliamente, edítalo en ese archivo y vuelve a publicar
> el sitio.

## 4. Subir el sitio a GitHub Pages

1. Crea un repositorio nuevo en GitHub (puede ser público o privado, aunque GitHub
   Pages gratuito para repos **privados** requiere una cuenta paga — si quieres que
   sea gratis y privado del todo, considera dejarlo público, ya que igualmente el
   directorio está protegido por el código de acceso).
2. Sube todos los archivos de esta carpeta (`index.html`, `directorio.html`, `css/`,
   `js/`, `assets/`, `README.md`) a la raíz del repositorio.
3. En GitHub, ve a **Settings → Pages**.
4. En "Source", elige la rama `main` (o `master`) y la carpeta `/ (root)`.
5. Guarda. En un par de minutos tu sitio quedará disponible en una URL como:
   `https://tu-usuario.github.io/tu-repositorio/`

## 5. Personalización rápida

- **Cambiar el código de acceso:** edita la constante `ACCESS_CODE` en `js/auth.js`.
- **Colores:** todos los tonos están centralizados como variables CSS al inicio de
  `css/style.css` (sección `:root`), extraídos del logo del club y del desierto de
  Atacama (arena, cordillera, flor del desierto, cactus).
- **Textos del club / crédito de marca:** al final de `directorio.html`, en la
  sección `<p class="footer-note">`.

## 6. Moderación de datos

Como administrador, entra a **Firebase Console → Firestore Database → colección
`jugadores`** para ver, exportar o eliminar cualquier registro (por ejemplo si
alguien se registra con datos falsos o pide ser eliminado del directorio).
