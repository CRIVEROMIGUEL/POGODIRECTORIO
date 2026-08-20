// ============================================================
// auth.js — Control de acceso simple por código de club
// ============================================================
// IMPORTANTE: esto NO es un sistema de seguridad real. El código
// vive en este archivo público, así que cualquier persona con
// conocimientos técnicos podría verlo en el código fuente. Sirve
// como una "puerta" para que solo los miembros del club (que
// conocen el código) entren al directorio, no para proteger datos
// sensibles. No pidas contraseñas personales ni datos bancarios
// en este sitio.
// ============================================================

const ACCESS_CODE = "COPIAPOGO2026@TACAM@";
const AUTH_KEY = "copiapogo_auth_ok";

function isAuthenticated() {
  return localStorage.getItem(AUTH_KEY) === "1";
}

function setAuthenticated() {
  localStorage.setItem(AUTH_KEY, "1");
}

function logout() {
  localStorage.removeItem(AUTH_KEY);
  window.location.href = "index.html";
}

// Protege una página: si no hay sesión, redirige al login.
function requireAuth() {
  if (!isAuthenticated()) {
    window.location.href = "index.html";
  }
}

// Lógica del formulario de login (solo se ejecuta en index.html)
function initLoginForm() {
  const form = document.getElementById("login-form");
  if (!form) return;

  // Si ya inició sesión antes, lo mandamos directo al directorio.
  if (isAuthenticated()) {
    window.location.href = "directorio.html";
    return;
  }

  const input = document.getElementById("access-code");
  const errorMsg = document.getElementById("login-error");
  const btn = document.getElementById("login-btn");

  form.addEventListener("submit", (e) => {
    e.preventDefault();
    const value = (input.value || "").trim();

    if (value === ACCESS_CODE) {
      errorMsg.classList.remove("show");
      btn.disabled = true;
      btn.innerHTML = '<span class="loader"></span> Ingresando...';
      setAuthenticated();
      window.location.href = "directorio.html";
    } else {
      errorMsg.textContent = "Código incorrecto. Verifica mayúsculas y símbolos, e inténtalo de nuevo.";
      errorMsg.classList.add("show");
      input.select();
    }
  });
}

document.addEventListener("DOMContentLoaded", initLoginForm);
