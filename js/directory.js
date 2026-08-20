// ============================================================
// directory.js — Lógica del directorio de entrenadores CopiapoGO!
// Usa Firebase (solo Firestore, plan gratuito Spark) vía SDK
// modular v10 (CDN).
//
// Nota sobre las fotos de QR: Firebase Storage ahora exige el plan
// de pago Blaze para poder usarse, así que en vez de subir la foto
// a Storage, la comprimimos en el navegador y la guardamos como
// imagen (base64) dentro de un sub-documento de Firestore
// (jugadores/{id}/qr/imagen). Así todo se queda 100% en el plan
// gratuito. Para que el directorio siga cargando rápido aunque el
// club crezca, esa imagen NO se trae al listar/buscar — solo se
// descarga cuando alguien hace clic en "Ver código QR".
// ============================================================

import firebaseConfig from "./firebase-config.js";

// ---- 0. Protege esta página: exige haber iniciado sesión ----
requireAuth();

// ---- 1. Firebase se carga de forma DIFERIDA (import dinámico) ----
// Si el club aún no configuró js/firebase-config.js, o si el navegador
// no tiene internet / bloquea el CDN de Google, esto NO debe romper el
// resto del sitio: las pestañas, el formulario y la selección de equipo
// deben seguir funcionando igual. Solo lo que depende de la base de
// datos (buscar, contar, registrar) se avisa como no disponible.
let db, firestoreApi, firebaseReady = false;

async function initFirebase() {
  if (!firebaseConfig.apiKey || firebaseConfig.apiKey.startsWith("REEMPLAZA")) {
    console.warn("Firebase aún no está configurado (js/firebase-config.js).");
    firebaseReady = false;
    return;
  }
  try {
    const [{ initializeApp }, firestoreMod] = await Promise.all([
      import("https://www.gstatic.com/firebasejs/10.12.2/firebase-app.js"),
      import("https://www.gstatic.com/firebasejs/10.12.2/firebase-firestore.js"),
    ]);
    const app = initializeApp(firebaseConfig);
    firestoreApi = firestoreMod;
    db = firestoreMod.getFirestore(app);
    firebaseReady = true;
  } catch (err) {
    console.error("Error cargando/inicializando Firebase:", err);
    firebaseReady = false;
  }
}

// ---- 2. Referencias DOM ----
const logoutBtn = document.getElementById("logout-btn");
const tabButtons = document.querySelectorAll(".tab-btn");
const tabPanels = {
  buscar: document.getElementById("tab-buscar"),
  registro: document.getElementById("tab-registro"),
};

const statTotal = document.getElementById("stat-total");
const statActivo = document.getElementById("stat-activo");
const statEventual = document.getElementById("stat-eventual");
const statOcasional = document.getElementById("stat-ocasional");

const searchText = document.getElementById("search-text");
const filterEquipo = document.getElementById("filter-equipo");
const filterFrecuencia = document.getElementById("filter-frecuencia");
const filterRemoto = document.getElementById("filter-remoto");
const resultsCount = document.getElementById("results-count");
const playerGrid = document.getElementById("player-grid");

const registroForm = document.getElementById("registro-form");
const registroError = document.getElementById("registro-error");
const registroSuccess = document.getElementById("registro-success");
const registroBtn = document.getElementById("registro-btn");

const teamOptions = document.querySelectorAll(".team-option");
const qrFileInput = document.getElementById("qrFile");
const qrPreview = document.getElementById("qr-preview");
const qrUploadText = document.getElementById("qr-upload-text");

const qrModal = document.getElementById("qr-modal");
const qrModalImg = document.getElementById("qr-modal-img");
const qrModalLoader = document.getElementById("qr-modal-loader");
const qrModalClose = document.getElementById("qr-modal-close");

let jugadoresCache = [];
let qrCompressedDataUrl = null;

// ---- 3. Logout ----
logoutBtn.addEventListener("click", logout);

// ---- 4. Tabs ----
tabButtons.forEach((btn) => {
  btn.addEventListener("click", () => {
    tabButtons.forEach((b) => b.classList.remove("active"));
    Object.values(tabPanels).forEach((p) => p.classList.remove("active"));
    btn.classList.add("active");
    tabPanels[btn.dataset.tab].classList.add("active");
  });
});

// ---- 5. Selección visual de equipo ----
teamOptions.forEach((opt) => {
  opt.addEventListener("click", () => {
    teamOptions.forEach((o) => o.classList.remove("selected"));
    opt.classList.add("selected");
  });
});

// ---- 6. Vista previa + compresión de imagen QR ----
// Se guarda directo dentro de Firestore (no en Storage), así que la
// comprimimos hasta que quepa cómoda bajo el límite de 1 MiB por
// documento que tiene Firestore, dejando harto margen.
const QR_MAX_DATAURL_LENGTH = 700 * 1024; // ~700 KB en texto base64

function readImage(file) {
  return new Promise((resolve, reject) => {
    const reader = new FileReader();
    reader.onload = (e) => {
      const img = new Image();
      img.onload = () => resolve(img);
      img.onerror = () => reject(new Error("No se pudo leer la imagen."));
      img.src = e.target.result;
    };
    reader.onerror = () => reject(new Error("No se pudo leer el archivo."));
    reader.readAsDataURL(file);
  });
}

function imageToBlob(img, maxWidth, quality) {
  return new Promise((resolve, reject) => {
    const scale = Math.min(1, maxWidth / img.width);
    const canvas = document.createElement("canvas");
    canvas.width = Math.max(1, Math.round(img.width * scale));
    canvas.height = Math.max(1, Math.round(img.height * scale));
    const ctx = canvas.getContext("2d");
    ctx.drawImage(img, 0, 0, canvas.width, canvas.height);
    canvas.toBlob(
      (blob) => (blob ? resolve(blob) : reject(new Error("No se pudo comprimir la imagen."))),
      "image/jpeg",
      quality
    );
  });
}

function blobToDataUrl(blob) {
  return new Promise((resolve, reject) => {
    const reader = new FileReader();
    reader.onload = () => resolve(reader.result);
    reader.onerror = () => reject(new Error("No se pudo procesar la imagen comprimida."));
    reader.readAsDataURL(blob);
  });
}

// Comprime en varios intentos (reduciendo tamaño/calidad) hasta que el
// resultado quepa bajo QR_MAX_DATAURL_LENGTH.
async function compressQrImage(file) {
  const img = await readImage(file);
  let width = 900;
  let quality = 0.82;
  let blob, dataUrl;

  for (let attempt = 0; attempt < 6; attempt++) {
    blob = await imageToBlob(img, width, quality);
    dataUrl = await blobToDataUrl(blob);
    if (dataUrl.length <= QR_MAX_DATAURL_LENGTH) {
      return { blob, dataUrl };
    }
    width = Math.round(width * 0.75);
    quality = Math.max(0.45, quality - 0.12);
  }

  throw new Error(
    "La imagen sigue siendo muy pesada incluso comprimida. Prueba recortarla más o usar otra foto."
  );
}

qrFileInput.addEventListener("change", async () => {
  const file = qrFileInput.files[0];
  if (!file) return;
  try {
    qrUploadText.textContent = "Procesando imagen...";
    const { blob, dataUrl } = await compressQrImage(file);
    qrCompressedDataUrl = dataUrl;
    qrPreview.src = URL.createObjectURL(blob);
    qrPreview.style.display = "block";
    qrUploadText.textContent = "✅ Imagen lista — toca para cambiarla";
  } catch (err) {
    console.error(err);
    qrUploadText.textContent = `⚠️ ${err.message || "No se pudo leer la imagen, intenta con otra."}`;
    qrCompressedDataUrl = null;
  }
});

// ---- 7. Modal QR (carga la imagen solo cuando se abre) ----
function openQrModalLoading() {
  qrModalImg.classList.remove("show");
  qrModalImg.removeAttribute("src");
  qrModalLoader.innerHTML = '<span class="loader loader-lg"></span>';
  qrModalLoader.classList.add("show");
  qrModal.classList.add("show");
}
function closeQrModal() {
  qrModal.classList.remove("show");
  qrModalImg.classList.remove("show");
  qrModalImg.removeAttribute("src");
}
qrModalClose.addEventListener("click", closeQrModal);
qrModal.addEventListener("click", (e) => {
  if (e.target === qrModal) closeQrModal();
});

async function showPlayerQr(playerId, playerName) {
  if (!firebaseReady || !db) return;
  openQrModalLoading();
  try {
    const qrDocRef = firestoreApi.doc(db, "jugadores", playerId, "qr", "imagen");
    const snap = await firestoreApi.getDoc(qrDocRef);
    qrModalLoader.classList.remove("show");
    if (snap.exists() && snap.data().data) {
      qrModalImg.alt = `Código QR de ${playerName}`;
      qrModalImg.src = snap.data().data;
      qrModalImg.classList.add("show");
    } else {
      showQrModalMessage("No se encontró la imagen del código QR de este entrenador.");
    }
  } catch (err) {
    console.error(err);
    qrModalLoader.classList.remove("show");
    showQrModalMessage("No se pudo cargar el código QR. Intenta de nuevo.");
  }
}

function showQrModalMessage(text) {
  qrModalLoader.classList.remove("show");
  qrModalLoader.innerHTML = `<p style="color:#fff;max-width:280px;text-align:center;">${escapeHtml(text)}</p>`;
  qrModalLoader.classList.add("show");
}

// ---- 8. Envío del formulario de registro ----
registroForm.addEventListener("submit", async (e) => {
  e.preventDefault();
  registroError.classList.remove("show");
  registroSuccess.classList.remove("show");

  if (!firebaseReady || !db) {
    registroError.textContent =
      "⚠️ El directorio todavía no está conectado a la base de datos (Firebase). El administrador del sitio debe completar js/firebase-config.js.";
    registroError.classList.add("show");
    return;
  }

  const nombreJugador = document.getElementById("nombreJugador").value.trim();
  const codigoID = document.getElementById("codigoID").value.trim();
  const telefono = document.getElementById("telefono").value.trim();
  const comuna = document.getElementById("comuna").value.trim();
  const pokemonFavorito = document.getElementById("pokemonFavorito").value.trim();
  const equipo = registroForm.querySelector('input[name="equipo"]:checked');
  const frecuencia = registroForm.querySelector('input[name="frecuencia"]:checked');
  const disponibilidadRemoto = registroForm.querySelector('input[name="disponibilidadRemoto"]:checked');
  const cuentaConmigoPara = Array.from(
    registroForm.querySelectorAll('input[name="cuentaConmigoPara"]:checked')
  ).map((el) => el.value);

  if (!nombreJugador || !codigoID || !comuna || !pokemonFavorito || !equipo || !frecuencia || !disponibilidadRemoto) {
    registroError.textContent = "Por favor completa todos los campos obligatorios (*).";
    registroError.classList.add("show");
    return;
  }
  if (!qrCompressedDataUrl) {
    registroError.textContent = "Por favor sube una captura de tu código QR.";
    registroError.classList.add("show");
    return;
  }

  registroBtn.disabled = true;
  registroBtn.innerHTML = '<span class="loader"></span> Registrando...';

  try {
    // Escribimos el registro y la imagen QR juntos, en un solo batch,
    // para que ambos se guarden o ninguno (evita registros a medias).
    const batch = firestoreApi.writeBatch(db);
    const playerRef = firestoreApi.doc(firestoreApi.collection(db, "jugadores"));

    batch.set(playerRef, {
      nombreJugador,
      codigoID,
      telefono: telefono || null,
      comuna,
      pokemonFavorito,
      equipo: equipo.value,
      frecuencia: frecuencia.value,
      disponibilidadRemoto: disponibilidadRemoto.value,
      cuentaConmigoPara,
      tieneQr: true,
      fechaRegistro: firestoreApi.serverTimestamp(),
    });

    const qrRef = firestoreApi.doc(db, "jugadores", playerRef.id, "qr", "imagen");
    batch.set(qrRef, {
      data: qrCompressedDataUrl,
      fechaRegistro: firestoreApi.serverTimestamp(),
    });

    await batch.commit();

    registroSuccess.textContent = "🎉 ¡Listo! Ya apareces en el directorio. Revisa la pestaña 'Buscar Directorio'.";
    registroSuccess.classList.add("show");
    registroForm.reset();
    teamOptions.forEach((o) => o.classList.remove("selected"));
    qrPreview.style.display = "none";
    qrCompressedDataUrl = null;
    qrUploadText.textContent = "📷 Toca para elegir una imagen desde tu galería";

    await loadDirectory();
  } catch (err) {
    console.error(err);
    registroError.textContent = "⚠️ Ocurrió un error al guardar tu registro. Intenta nuevamente en unos minutos.";
    registroError.classList.add("show");
  } finally {
    registroBtn.disabled = false;
    registroBtn.textContent = "Registrarme en el Directorio";
  }
});

// ---- 9. Carga y muestra del directorio ----
const FRECUENCIA_LABEL = {
  activo: "Entrenador Activo",
  eventual: "Entrenador Eventual",
  ocasional: "Entrenador Ocasional",
};
const EQUIPO_LABEL = {
  valor: "🔴 Valor",
  sabiduria: "🔵 Sabiduría",
  instinto: "🟡 Instinto",
};
const REMOTO_LABEL = {
  cuenta_conmigo: "Cuenta conmigo",
  tal_vez: "Tal vez pueda",
  no_juego_remotos: "No juego remotos",
};
const REMOTO_CLASS = {
  cuenta_conmigo: "remote-si",
  tal_vez: "remote-tal-vez",
  no_juego_remotos: "remote-no",
};
const EXTRA_LABEL = {
  envio_regalos: "🎁 Regalos",
  raids: "⚔️ Raids",
  cambios: "🔄 Cambios",
  pvp: "🥊 PVP",
  consejos: "💡 Consejos",
};

async function loadDirectory() {
  if (!firebaseReady || !db) {
    resultsCount.textContent = "⚠️ El directorio aún no está conectado a Firebase. Revisa el README.";
    statTotal.textContent = "—";
    statActivo.textContent = "—";
    statEventual.textContent = "—";
    statOcasional.textContent = "—";
    return;
  }
  try {
    // Ojo: esto NO trae las imágenes QR (viven en un sub-documento
    // aparte) — así el directorio carga rápido sin importar cuántos
    // socios tenga el club.
    const q = firestoreApi.query(
      firestoreApi.collection(db, "jugadores"),
      firestoreApi.orderBy("fechaRegistro", "desc")
    );
    const snap = await firestoreApi.getDocs(q);
    jugadoresCache = snap.docs.map((d) => ({ id: d.id, ...d.data() }));
    updateStats();
    renderDirectory();
  } catch (err) {
    console.error(err);
    resultsCount.textContent = "⚠️ No se pudo cargar el directorio. Revisa la configuración de Firebase.";
  }
}

function updateStats() {
  statTotal.textContent = jugadoresCache.length;
  statActivo.textContent = jugadoresCache.filter((j) => j.frecuencia === "activo").length;
  statEventual.textContent = jugadoresCache.filter((j) => j.frecuencia === "eventual").length;
  statOcasional.textContent = jugadoresCache.filter((j) => j.frecuencia === "ocasional").length;
}

function renderDirectory() {
  const text = (searchText.value || "").trim().toLowerCase();
  const eqFilter = filterEquipo.value;
  const frFilter = filterFrecuencia.value;
  const remFilter = filterRemoto.value;

  const filtered = jugadoresCache.filter((j) => {
    if (eqFilter && j.equipo !== eqFilter) return false;
    if (frFilter && j.frecuencia !== frFilter) return false;
    if (remFilter && j.disponibilidadRemoto !== remFilter) return false;
    if (text) {
      const haystack = `${j.nombreJugador} ${j.comuna} ${j.pokemonFavorito} ${j.codigoID}`.toLowerCase();
      if (!haystack.includes(text)) return false;
    }
    return true;
  });

  resultsCount.textContent = `Mostrando ${filtered.length} de ${jugadoresCache.length} entrenadores registrados.`;

  if (filtered.length === 0) {
    playerGrid.innerHTML = `
      <div class="empty-state" style="grid-column:1/-1;">
        <div class="big-emoji">🌵</div>
        <p>No encontramos entrenadores con esos filtros. ¡Sé el primero en registrarte con esos datos!</p>
      </div>`;
    return;
  }

  playerGrid.innerHTML = filtered.map(renderCard).join("");

  playerGrid.querySelectorAll("[data-player-id]").forEach((el) => {
    el.addEventListener("click", () => showPlayerQr(el.dataset.playerId, el.dataset.playerName));
  });
}

function renderCard(j) {
  const extras = (j.cuentaConmigoPara || [])
    .map((v) => `<span class="tag">${EXTRA_LABEL[v] || v}</span>`)
    .join("");

  return `
  <article class="player-card team-${j.equipo}">
    <div class="pc-head">
      <div>
        <h3>${escapeHtml(j.nombreJugador)}</h3>
        <div class="pc-id">ID: ${escapeHtml(j.codigoID)}</div>
      </div>
      <span class="badge badge-${j.equipo}">${EQUIPO_LABEL[j.equipo] || j.equipo}</span>
    </div>

    <div class="pc-meta">
      <span class="tag">${FRECUENCIA_LABEL[j.frecuencia] || j.frecuencia}</span>
      <span class="tag ${REMOTO_CLASS[j.disponibilidadRemoto] || ""}">🛰️ ${REMOTO_LABEL[j.disponibilidadRemoto] || j.disponibilidadRemoto}</span>
    </div>

    <div class="pc-details">
      <div class="row"><b>Comuna/Región</b> <span>${escapeHtml(j.comuna)}</span></div>
      <div class="row"><b>Pokémon fav.</b> <span>${escapeHtml(j.pokemonFavorito)}</span></div>
      ${j.telefono ? `<div class="row"><b>Teléfono</b> <span>${escapeHtml(j.telefono)}</span></div>` : ""}
    </div>

    ${extras ? `<div class="pc-extras">${extras}</div>` : ""}

    ${j.tieneQr !== false ? `
    <div class="pc-qr">
      <button type="button" class="link-btn" data-player-id="${j.id}" data-player-name="${escapeHtml(j.nombreJugador)}">📷 Ver código QR</button>
    </div>` : ""}
  </article>`;
}

function escapeHtml(str) {
  if (str === undefined || str === null) return "";
  return String(str)
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;");
}

// ---- 10. Listeners de búsqueda/filtros ----
[searchText, filterEquipo, filterFrecuencia, filterRemoto].forEach((el) => {
  el.addEventListener("input", renderDirectory);
  el.addEventListener("change", renderDirectory);
});

// ---- 11. Arranque ----
// La interfaz (pestañas, formulario, selección de equipo, QR) ya quedó
// lista y funcionando arriba. Ahora, en paralelo, intentamos conectar
// con Firebase para traer los datos reales del directorio.
initFirebase().then(loadDirectory);
