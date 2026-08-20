#!/usr/bin/env node
// ============================================================
// inject-firebase-config.js
// Toma el JSON de configuración que entrega
// "firebase apps:sdkconfig WEB <appId> -o config.json"
// y lo escribe dentro de js/firebase-config.js, reemplazando
// el objeto firebaseConfig completo (sin tocar los comentarios).
// ============================================================
const fs = require("fs");
const path = require("path");

const [, , jsonPath, targetPath] = process.argv;

if (!jsonPath || !targetPath) {
  console.error("Uso: node inject-firebase-config.js <config.json> <js/firebase-config.js>");
  process.exit(1);
}

const raw = fs.readFileSync(jsonPath, "utf8");
const parsed = JSON.parse(raw);

// El JSON que entrega el CLI puede venir anidado bajo distintas claves
// según la versión de firebase-tools. Normalizamos.
const cfg = parsed.result || parsed.sdkConfig || parsed;

const required = ["apiKey", "authDomain", "projectId", "storageBucket", "messagingSenderId", "appId"];
const missing = required.filter((k) => !cfg[k]);
if (missing.length) {
  console.error("⚠️  Faltan campos en el config recibido de Firebase:", missing.join(", "));
  console.error("Contenido recibido:", JSON.stringify(cfg, null, 2));
  process.exit(1);
}

const newBlock = `const firebaseConfig = {
  apiKey: ${JSON.stringify(cfg.apiKey)},
  authDomain: ${JSON.stringify(cfg.authDomain)},
  projectId: ${JSON.stringify(cfg.projectId)},
  storageBucket: ${JSON.stringify(cfg.storageBucket)},
  messagingSenderId: ${JSON.stringify(cfg.messagingSenderId)},
  appId: ${JSON.stringify(cfg.appId)}
};`;

let content = fs.readFileSync(targetPath, "utf8");
content = content.replace(/const firebaseConfig = \{[\s\S]*?\};/, newBlock);
fs.writeFileSync(targetPath, content, "utf8");

console.log(`✅ ${path.basename(targetPath)} actualizado con la configuración real de Firebase (proyecto: ${cfg.projectId}).`);
