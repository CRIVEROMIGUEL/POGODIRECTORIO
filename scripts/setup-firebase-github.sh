#!/usr/bin/env bash
# ============================================================
# setup-firebase-github.sh
# Automatiza (con supervisión tuya) los pasos del README:
#   1. Crear el proyecto Firebase
#   2. Registrar la app web y pegar la config en js/firebase-config.js
#   3. Crear la base de datos Firestore
#   4. Publicar las reglas de seguridad de Firestore
#   5. Crear el repositorio en GitHub y subir el sitio
#   6. Activar GitHub Pages
#
# Nota: este proyecto NO usa Firebase Storage (Google ahora exige el plan
# de pago Blaze para activarlo). La foto del código QR se guarda directo,
# comprimida, dentro de Firestore — que sigue siendo 100% gratis.
#
# IMPORTANTE — qué significa "con supervisión":
#   - Este script NO guarda ni usa ninguna contraseña tuya. Cuando toca
#     iniciar sesión en Firebase o GitHub, se abre tu navegador y TÚ
#     inicias sesión ahí normalmente.
#   - Antes de crear cosas (proyecto Firebase, repo de GitHub) el script
#     te pregunta y espera tu "sí" explícito.
#   - Debes correrlo en TU computador (no funciona dentro de un chat de
#     Claude), porque necesita tu cuenta de Google y tu cuenta de GitHub.
#
# Requisitos previos:
#   - Node.js y npm instalados (https://nodejs.org)
#   - GitHub CLI ("gh") instalado: https://cli.github.com
#     (Mac:  brew install gh   |   Windows: winget install GitHub.cli
#      Ubuntu/Debian: ver https://github.com/cli/cli/blob/trunk/docs/install_linux.md)
#
# Cómo correrlo:
#   cd copiapogo
#   bash scripts/setup-firebase-github.sh
# ============================================================

set -uo pipefail

# ---------- utilidades de salida ----------
BOLD="\033[1m"; DIM="\033[2m"; GREEN="\033[32m"; YELLOW="\033[33m"; RED="\033[31m"; RESET="\033[0m"

say()   { echo -e "${BOLD}${1}${RESET}"; }
info()  { echo -e "${DIM}   $1${RESET}"; }
ok()    { echo -e "${GREEN}✔ $1${RESET}"; }
warn()  { echo -e "${YELLOW}⚠ $1${RESET}"; }
fail()  { echo -e "${RED}✖ $1${RESET}"; }

confirm() {
  # confirm "pregunta" -> devuelve 0 si el usuario responde s/S/y/Y
  local prompt="$1"
  local answer
  read -r -p "$(echo -e "${BOLD}${prompt}${RESET} [s/N]: ")" answer
  [[ "$answer" =~ ^[sSyY]$ ]]
}

pause() {
  read -r -p "$(echo -e "${DIM}   Presiona ENTER cuando hayas terminado ese paso...${RESET}")" _
}

step() { echo ""; echo -e "${BOLD}────────────────────────────────────────────${RESET}"; echo -e "${BOLD}$1${RESET}"; echo -e "${BOLD}────────────────────────────────────────────${RESET}"; }

# ---------- ubicación del proyecto ----------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_DIR"

say "🌵 CopiapoGO! — instalador guiado"
info "Carpeta del proyecto: $PROJECT_DIR"
echo ""
warn "Este script hace cambios reales: crea un proyecto de Firebase (gratis) y"
warn "un repositorio en GitHub. Nada se hace sin que tú confirmes cada paso."
if ! confirm "¿Quieres continuar?"; then
  echo "Cancelado. No se hizo ningún cambio."
  exit 0
fi

# ============================================================
# 1. Verificar dependencias
# ============================================================
step "1/7 · Verificando herramientas necesarias"

if ! command -v node >/dev/null 2>&1; then
  fail "No se encontró Node.js. Instálalo desde https://nodejs.org y vuelve a correr este script."
  exit 1
fi
ok "Node.js encontrado ($(node -v))"

if ! command -v npm >/dev/null 2>&1; then
  fail "No se encontró npm (debería venir con Node.js)."
  exit 1
fi
ok "npm encontrado ($(npm -v))"

if ! command -v firebase >/dev/null 2>&1; then
  warn "No se encontró la Firebase CLI."
  if confirm "¿Instalarla ahora con 'npm install -g firebase-tools'?"; then
    npm install -g firebase-tools || { fail "No se pudo instalar firebase-tools."; exit 1; }
  else
    fail "La Firebase CLI es necesaria. Instálala manualmente: npm install -g firebase-tools"
    exit 1
  fi
fi
ok "Firebase CLI encontrada ($(firebase --version))"

if ! command -v gh >/dev/null 2>&1; then
  fail "No se encontró GitHub CLI ('gh')."
  info "Instálala desde https://cli.github.com y vuelve a correr este script."
  info "Mac: brew install gh   |   Windows: winget install GitHub.cli"
  exit 1
fi
ok "GitHub CLI encontrada ($(gh --version | head -n1))"

# ============================================================
# 2. Login en Firebase (abre tu navegador)
# ============================================================
step "2/7 · Iniciar sesión en Firebase"
info "Se abrirá tu navegador para que inicies sesión con la cuenta Google del club."
if ! firebase login; then
  fail "No se pudo iniciar sesión en Firebase."
  info "Si estás en un entorno remoto sin navegador, intenta: firebase login --no-localhost"
  exit 1
fi
ok "Sesión de Firebase activa."

# ============================================================
# 3. Crear el proyecto Firebase
# ============================================================
step "3/7 · Crear el proyecto Firebase"
info "El ID del proyecto de Google Cloud/Firebase SOLO admite minúsculas, números"
info "y guiones (nada de mayúsculas, espacios ni símbolos), y debe empezar con letra."
DEFAULT_ID="copiapogo-directorio-$RANDOM"

while true; do
  read -r -p "$(echo -e "${BOLD}ID del proyecto${RESET} [$DEFAULT_ID]: ")" PROJECT_ID_RAW
  PROJECT_ID_RAW="${PROJECT_ID_RAW:-$DEFAULT_ID}"

  # Normaliza: todo a minúsculas y cualquier carácter inválido -> guion
  NORMALIZED="$(echo "$PROJECT_ID_RAW" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9-]+/-/g; s/-+/-/g; s/^-+//; s/-+$//')"

  if [[ "$NORMALIZED" != "$PROJECT_ID_RAW" ]]; then
    warn "Ajusté el ID para que sea válido: '$PROJECT_ID_RAW' → '$NORMALIZED'"
  fi

  if [[ ${#NORMALIZED} -lt 6 ]]; then
    fail "El ID debe tener al menos 6 caracteres. Intenta de nuevo."
    continue
  fi
  if [[ ${#NORMALIZED} -gt 30 ]]; then
    NORMALIZED="${NORMALIZED:0:30}"
    NORMALIZED="$(echo "$NORMALIZED" | sed -E 's/-+$//')"
    warn "El ID era muy largo, lo recorté a: '$NORMALIZED'"
  fi
  if [[ ! "$NORMALIZED" =~ ^[a-z] ]]; then
    fail "El ID debe empezar con una letra minúscula. Intenta de nuevo."
    continue
  fi

  PROJECT_ID="$NORMALIZED"
  break
done

if confirm "¿Crear el proyecto Firebase '$PROJECT_ID'? (queda en el plan gratuito Spark)"; then
  if ! firebase projects:create "$PROJECT_ID" --display-name "CopiapoGO! Directorio" 2>/tmp/create_project_err.log; then
    fail "No se pudo crear el proyecto."
    cat /tmp/create_project_err.log 2>/dev/null | sed 's/^/   /'
    info "Causas típicas: ese ID ya está tomado por otra persona en el mundo (son"
    info "globales) — prueba con otro más específico; o tu cuenta de Google llegó al"
    info "límite de proyectos gratuitos — revisa https://console.cloud.google.com/projectcreate"
    info "para ver el mensaje completo de Google."
    exit 1
  fi
  ok "Proyecto '$PROJECT_ID' creado."
else
  echo "Cancelado."
  exit 0
fi

# ============================================================
# 4. Registrar la app web y pegar la configuración
# ============================================================
step "4/7 · Registrar la app web"
CREATE_OUT="$(firebase apps:create WEB "CopiapoGO Web" --project "$PROJECT_ID" --json)"
APP_ID="$(node -e "console.log(JSON.parse(process.argv[1]).result.appId)" "$CREATE_OUT" 2>/dev/null)"

if [[ -z "$APP_ID" ]]; then
  fail "No se pudo leer el ID de la app web recién creada."
  echo "$CREATE_OUT"
  exit 1
fi
ok "App web registrada (appId: $APP_ID)"

CONFIG_JSON="$(mktemp)"
firebase apps:sdkconfig WEB "$APP_ID" --project "$PROJECT_ID" -o "$CONFIG_JSON" >/dev/null
node "$SCRIPT_DIR/inject-firebase-config.js" "$CONFIG_JSON" "$PROJECT_DIR/js/firebase-config.js"
rm -f "$CONFIG_JSON"
ok "js/firebase-config.js actualizado con tus llaves reales."

# ============================================================
# 5. Firestore Database
# ============================================================
step "5/7 · Activar Firestore Database"
read -r -p "$(echo -e "${BOLD}Región de Firestore${RESET} [southamerica-east1]: ")" REGION
REGION="${REGION:-southamerica-east1}"

if firebase firestore:databases:create "(default)" --location="$REGION" --project "$PROJECT_ID" 2>/tmp/firestore_err.log; then
  ok "Firestore Database creada en $REGION."
else
  warn "No se pudo crear Firestore automáticamente (puede que tu versión de la CLI no soporte este comando)."
  cat /tmp/firestore_err.log 2>/dev/null | sed 's/^/   /'
  info "Créala manualmente aquí: https://console.firebase.google.com/project/$PROJECT_ID/firestore"
  pause
fi

# ============================================================
# 6. Publicar reglas de seguridad de Firestore
# ============================================================
step "6/7 · Publicar reglas de seguridad de Firestore"
info "(Este proyecto no usa Firebase Storage — la foto del QR se guarda"
info "comprimida dentro del mismo documento de Firestore, sin costo.)"
if firebase deploy --only firestore:rules --project "$PROJECT_ID"; then
  ok "Reglas publicadas."
else
  fail "No se pudieron publicar las reglas. Revisa el mensaje de arriba."
  info "Puedes reintentar luego con:"
  info "  firebase deploy --only firestore:rules --project $PROJECT_ID"
fi

echo "$PROJECT_ID" > "$PROJECT_DIR/.firebase-project-id"

# ============================================================
# 7. Repositorio en GitHub + GitHub Pages
# ============================================================
step "7/7 · Subir a GitHub y activar GitHub Pages"

if ! gh auth status >/dev/null 2>&1; then
  info "Se abrirá tu navegador para iniciar sesión en GitHub."
  gh auth login || { fail "No se pudo iniciar sesión en GitHub."; exit 1; }
fi
ok "Sesión de GitHub activa ($(gh api user -q .login 2>/dev/null))."

if [[ ! -d .git ]]; then
  git init -q
  git checkout -q -b main 2>/dev/null || git branch -M main
fi

git add -A
git commit -q -m "CopiapoGO! - directorio de entrenadores" 2>/dev/null || info "(nada nuevo que commitear)"

DEFAULT_REPO="copiapogo-directorio"
read -r -p "$(echo -e "${BOLD}Nombre del repositorio en GitHub${RESET} [$DEFAULT_REPO]: ")" REPO_NAME
REPO_NAME="${REPO_NAME:-$DEFAULT_REPO}"

VIS="public"
if confirm "¿Quieres que el repositorio sea PRIVADO? (GitHub Pages gratis solo funciona en repos privados con cuenta de pago; si no estás seguro, responde 'n')"; then
  VIS="private"
fi

if gh repo view "$REPO_NAME" >/dev/null 2>&1; then
  warn "Ya existe un repo tuyo llamado '$REPO_NAME'. Se usará ese (agregando este remoto si falta)."
  OWNER="$(gh api user -q .login)"
  git remote add origin "https://github.com/$OWNER/$REPO_NAME.git" 2>/dev/null || true
  git push -u origin main
else
  gh repo create "$REPO_NAME" --"$VIS" --source=. --remote=origin --push || {
    fail "No se pudo crear/subir el repositorio."
    exit 1
  }
fi
ok "Código subido a GitHub."

OWNER="$(gh api user -q .login)"
if gh api -X POST "repos/$OWNER/$REPO_NAME/pages" -f "source[branch]=main" -f "source[path]=/" >/dev/null 2>/tmp/pages_err.log; then
  ok "GitHub Pages activado."
else
  if grep -q "already exists" /tmp/pages_err.log 2>/dev/null; then
    ok "GitHub Pages ya estaba activado."
  else
    warn "No se pudo activar Pages automáticamente. Actívalo manualmente en:"
    info "https://github.com/$OWNER/$REPO_NAME/settings/pages (Source: main / root)"
  fi
fi

# ============================================================
# Resumen final
# ============================================================
step "🎉 Listo"
echo -e "Proyecto Firebase:   ${BOLD}$PROJECT_ID${RESET}"
echo -e "Repositorio GitHub:  ${BOLD}https://github.com/$OWNER/$REPO_NAME${RESET}"
echo -e "Sitio (en 1-2 min):  ${BOLD}https://$OWNER.github.io/$REPO_NAME/${RESET}"
echo -e "Código de acceso:    ${BOLD}COPIAPOGO2026@TACAM@${RESET}"
echo ""
info "Si el sitio no carga de inmediato, espera un par de minutos y recarga."
info "Puedes revisar/borrar registros desde: https://console.firebase.google.com/project/$PROJECT_ID/firestore"
