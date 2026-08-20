<#
============================================================
 setup-firebase-github.ps1
 Version para Windows (PowerShell) del instalador guiado.
 Hace lo mismo que scripts/setup-firebase-github.sh pero sin
 necesitar Git Bash ni WSL.

 IMPORTANTE:
   - No hagas doble clic a este archivo en el Explorador de
     Windows: eso no funciona bien con scripts de PowerShell.
     Debes abrirlo desde una terminal (ver instrucciones abajo).
   - Este script no guarda ninguna contrasena tuya. Cuando toca
     iniciar sesion en Firebase o GitHub, se abre tu navegador y
     TU inicias sesion ahi normalmente.
   - Antes de crear cosas (proyecto Firebase, repo de GitHub) el
     script pregunta y espera tu "s" explicito.

 Requisitos previos:
   - Node.js (https://nodejs.org)
   - GitHub CLI: https://cli.github.com  (winget install GitHub.cli)

 Como correrlo:
   1. Abre "Windows PowerShell" (NO "Windows PowerShell ISE").
   2. Ve a la carpeta del proyecto, por ejemplo:
        cd "C:\Users\TuUsuario\Desktop\copiapogo"
   3. Si Windows bloquea el script por politica de ejecucion, corre
      primero (una sola vez, solo afecta esta ventana):
        Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
   4. Luego ejecuta:
        .\scripts\setup-firebase-github.ps1
============================================================
#>

# OJO: a proposito NO ponemos $ErrorActionPreference = "Stop" aqui.
# Firebase/gh/git escriben mensajes normales por stderr todo el tiempo, y con
# ErrorActionPreference=Stop, PowerShell convierte esas lineas en errores que
# CIERRAN el script de golpe aunque el comando en realidad haya funcionado
# bien (o aunque el error ya este siendo manejado mas abajo con $LASTEXITCODE).
# Por eso cada paso revisa $LASTEXITCODE explicitamente en vez de depender de
# excepciones.

function Say($msg)  { Write-Host $msg -ForegroundColor White }
function Info($msg) { Write-Host "   $msg" -ForegroundColor DarkGray }
function Ok($msg)   { Write-Host "OK  $msg" -ForegroundColor Green }
function Warn($msg) { Write-Host "!!  $msg" -ForegroundColor Yellow }
function Fail($msg) { Write-Host "X   $msg" -ForegroundColor Red }

function Step($msg) {
  Write-Host ""
  Write-Host "----------------------------------------------------" -ForegroundColor Cyan
  Write-Host $msg -ForegroundColor Cyan
  Write-Host "----------------------------------------------------" -ForegroundColor Cyan
}

function Confirm($prompt) {
  $answer = Read-Host "$prompt [s/N]"
  return ($answer -match '^[sSyY]$')
}

function Pause-Step {
  Read-Host "   Presiona ENTER cuando hayas terminado ese paso" | Out-Null
}

function Test-CommandExists($name) {
  return [bool](Get-Command $name -ErrorAction SilentlyContinue)
}

$ScriptDir  = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectDir = Split-Path -Parent $ScriptDir
Set-Location $ProjectDir

Say "CopiapoGO! - instalador guiado (Windows)"
Info "Carpeta del proyecto: $ProjectDir"
Write-Host ""
Warn "Este script crea un proyecto de Firebase (gratis) y un repositorio en GitHub."
Warn "Nada se hace sin que tu confirmes cada paso."
if (-not (Confirm "Quieres continuar?")) {
  Write-Host "Cancelado. No se hizo ningun cambio."
  exit 0
}

# ============================================================
# 1. Verificar dependencias
# ============================================================
Step "1/7 - Verificando herramientas necesarias"

if (-not (Test-CommandExists node)) {
  Fail "No se encontro Node.js. Instalalo desde https://nodejs.org y vuelve a correr este script."
  exit 1
}
Ok "Node.js encontrado ($(node -v))"

if (-not (Test-CommandExists npm)) {
  Fail "No se encontro npm (deberia venir con Node.js)."
  exit 1
}
Ok "npm encontrado ($(npm -v))"

if (-not (Test-CommandExists firebase)) {
  Warn "No se encontro la Firebase CLI."
  if (Confirm "Instalarla ahora con 'npm install -g firebase-tools'?") {
    npm install -g firebase-tools
    if ($LASTEXITCODE -ne 0) { Fail "No se pudo instalar firebase-tools."; exit 1 }
  } else {
    Fail "La Firebase CLI es necesaria: npm install -g firebase-tools"
    exit 1
  }
}
Ok "Firebase CLI encontrada"

if (-not (Test-CommandExists gh)) {
  Fail "No se encontro GitHub CLI ('gh')."
  Info "Instalala desde https://cli.github.com  (winget install GitHub.cli)"
  Info "y vuelve a correr este script."
  exit 1
}
Ok "GitHub CLI encontrada"

# ============================================================
# 2. Login en Firebase
# ============================================================
Step "2/7 - Iniciar sesion en Firebase"
Info "Se abrira tu navegador para que inicies sesion con la cuenta Google del club."
firebase login
if ($LASTEXITCODE -ne 0) {
  Fail "No se pudo iniciar sesion en Firebase."
  exit 1
}
Ok "Sesion de Firebase activa."

# ============================================================
# 3. Crear el proyecto Firebase
# ============================================================
Step "3/7 - Crear el proyecto Firebase"
Info "El ID del proyecto de Google Cloud/Firebase SOLO admite minusculas, numeros"
Info "y guiones (nada de mayusculas, espacios ni simbolos), y debe empezar con letra."
$defaultId = "copiapogo-directorio-$(Get-Random -Maximum 99999)"

$projectId = $null
while (-not $projectId) {
  $rawId = Read-Host "ID del proyecto [$defaultId]"
  if ([string]::IsNullOrWhiteSpace($rawId)) { $rawId = $defaultId }

  $normalized = $rawId.ToLowerInvariant()
  $normalized = [regex]::Replace($normalized, '[^a-z0-9-]+', '-')
  $normalized = [regex]::Replace($normalized, '-+', '-')
  $normalized = $normalized.Trim('-')

  if ($normalized -ne $rawId) {
    Warn "Ajuste el ID para que sea valido: '$rawId' -> '$normalized'"
  }

  if ($normalized.Length -lt 6) {
    Fail "El ID debe tener al menos 6 caracteres. Intenta de nuevo."
    continue
  }
  if ($normalized.Length -gt 30) {
    $normalized = $normalized.Substring(0, 30).Trim('-')
    Warn "El ID era muy largo, lo recorte a: '$normalized'"
  }
  if ($normalized -notmatch '^[a-z]') {
    Fail "El ID debe empezar con una letra minuscula. Intenta de nuevo."
    continue
  }

  $projectId = $normalized
}

if (Confirm "Crear el proyecto Firebase '$projectId'? (plan gratuito Spark)") {
  firebase projects:create $projectId --display-name "CopiapoGO! Directorio"
  if ($LASTEXITCODE -ne 0) {
    Fail "No se pudo crear el proyecto."
    Info "Causas tipicas: ese ID ya esta tomado por otra persona en el mundo (son"
    Info "globales) - prueba con otro mas especifico; o tu cuenta de Google llego al"
    Info "limite de proyectos gratuitos - revisa https://console.cloud.google.com/projectcreate"
    Info "para ver el mensaje completo de Google."
    exit 1
  }
  Ok "Proyecto '$projectId' creado."
} else {
  Write-Host "Cancelado."
  exit 0
}

# ============================================================
# 4. Registrar la app web y pegar la configuracion
# ============================================================
Step "4/7 - Registrar la app web"
$createOut = firebase apps:create WEB "CopiapoGO Web" --project $projectId --json
if ($LASTEXITCODE -ne 0) {
  Fail "No se pudo registrar la app web."
  Write-Host $createOut
  exit 1
}
try {
  $createObj = $createOut | ConvertFrom-Json
  $appId = $createObj.result.appId
} catch {
  Fail "No se pudo interpretar la respuesta de Firebase al registrar la app."
  Write-Host $createOut
  exit 1
}

if ([string]::IsNullOrWhiteSpace($appId)) {
  Fail "No se pudo leer el ID de la app web recien creada."
  Write-Host $createOut
  exit 1
}
Ok "App web registrada (appId: $appId)"

$configJsonPath = Join-Path $env:TEMP "copiapogo-firebase-config.json"
firebase apps:sdkconfig WEB $appId --project $projectId -o $configJsonPath | Out-Null

# Llamamos a node EXPLICITAMENTE (nunca hagas doble clic a este .js):
node "$ScriptDir\inject-firebase-config.js" "$configJsonPath" "$ProjectDir\js\firebase-config.js"
if ($LASTEXITCODE -ne 0) {
  Fail "No se pudo escribir js\firebase-config.js. Revisa el mensaje de arriba."
  exit 1
}
Remove-Item $configJsonPath -ErrorAction SilentlyContinue
Ok "js\firebase-config.js actualizado con tus llaves reales."

# ============================================================
# 5. Firestore Database
# ============================================================
Step "5/7 - Activar Firestore Database"
$region = Read-Host "Region de Firestore [southamerica-east1]"
if ([string]::IsNullOrWhiteSpace($region)) { $region = "southamerica-east1" }

firebase firestore:databases:create "(default)" --location=$region --project $projectId
if ($LASTEXITCODE -ne 0) {
  Warn "No se pudo crear Firestore automaticamente (puede que tu version de la CLI no soporte este comando)."
  Info "Creala manualmente aqui: https://console.firebase.google.com/project/$projectId/firestore"
  Pause-Step
} else {
  Ok "Firestore Database creada en $region."
}

# ============================================================
# 6. Publicar reglas de seguridad de Firestore
# ============================================================
Step "6/7 - Publicar reglas de seguridad de Firestore"
Info "(Este proyecto no usa Firebase Storage - la foto del QR se guarda"
Info "comprimida dentro del mismo documento de Firestore, sin costo.)"
firebase deploy --only firestore:rules --project $projectId
if ($LASTEXITCODE -ne 0) {
  Fail "No se pudieron publicar las reglas. Revisa el mensaje de arriba."
  Info "Puedes reintentar luego con:"
  Info "  firebase deploy --only firestore:rules --project $projectId"
} else {
  Ok "Reglas publicadas."
}
Set-Content -Path "$ProjectDir\.firebase-project-id" -Value $projectId

# ============================================================
# 7. Repositorio en GitHub + GitHub Pages
# ============================================================
Step "7/7 - Subir a GitHub y activar GitHub Pages"

gh auth status 2>$null 1>$null
if ($LASTEXITCODE -ne 0) {
  Info "Se abrira tu navegador para iniciar sesion en GitHub."
  gh auth login
  if ($LASTEXITCODE -ne 0) { Fail "No se pudo iniciar sesion en GitHub."; exit 1 }
}
$ghUser = (gh api user -q .login).Trim()
Ok "Sesion de GitHub activa ($ghUser)."

if (-not (Test-Path ".git")) {
  git init | Out-Null
  git checkout -b main 2>$null | Out-Null
}

git add -A
git commit -m "CopiapoGO! - directorio de entrenadores" 2>$null | Out-Null

$defaultRepo = "copiapogo-directorio"
$repoName = Read-Host "Nombre del repositorio en GitHub [$defaultRepo]"
if ([string]::IsNullOrWhiteSpace($repoName)) { $repoName = $defaultRepo }

$vis = "public"
if (Confirm "Quieres que el repositorio sea PRIVADO? (GitHub Pages gratis solo funciona en repos publicos, salvo cuenta de pago; si dudas, responde n)") {
  $vis = "private"
}

gh repo view $repoName 2>$null 1>$null
if ($LASTEXITCODE -eq 0) {
  Warn "Ya existe un repo tuyo llamado '$repoName'. Se usara ese."
  git remote add origin "https://github.com/$ghUser/$repoName.git" 2>$null
  git push -u origin main
} else {
  if ($vis -eq "private") {
    gh repo create $repoName --private --source=. --remote=origin --push
  } else {
    gh repo create $repoName --public --source=. --remote=origin --push
  }
  if ($LASTEXITCODE -ne 0) {
    Fail "No se pudo crear/subir el repositorio."
    exit 1
  }
}
Ok "Codigo subido a GitHub."

gh api -X POST "repos/$ghUser/$repoName/pages" -f "source[branch]=main" -f "source[path]=/" 2>$null 1>$null
if ($LASTEXITCODE -eq 0) {
  Ok "GitHub Pages activado."
} else {
  Warn "No se pudo activar Pages automaticamente (puede que ya estuviera activado)."
  Info "Revisa/activa manualmente en: https://github.com/$ghUser/$repoName/settings/pages"
}

# ============================================================
# Resumen final
# ============================================================
Step "Listo"
Write-Host "Proyecto Firebase:   $projectId"
Write-Host "Repositorio GitHub:  https://github.com/$ghUser/$repoName"
Write-Host "Sitio (en 1-2 min):  https://$ghUser.github.io/$repoName/"
Write-Host "Codigo de acceso:    COPIAPOGO2026@TACAM@"
Write-Host ""
Info "Si el sitio no carga de inmediato, espera un par de minutos y recarga."
Info "Puedes revisar/borrar registros desde: https://console.firebase.google.com/project/$projectId/firestore"
