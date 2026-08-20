// ============================================================
// CONFIGURACIÓN DE FIREBASE — CopiapoGO!
// ============================================================
// 1. Ve a https://console.firebase.google.com/ y crea un proyecto
//    gratuito (plan "Spark").
// 2. Dentro del proyecto: "Configuración del proyecto" (ícono de
//    engranaje) > pestaña "General" > sección "Tus apps" > ícono
//    </> (Web) > registra la app (no necesitas Hosting).
// 3. Firebase te mostrará un objeto "firebaseConfig" muy parecido
//    al de abajo. Copia y pega TUS valores reales aquí abajo,
//    reemplazando los que dicen "REEMPLAZA_...".
// 4. Activa Firestore Database (modo producción) desde el menú lateral
//    del proyecto. (No hace falta activar Storage: la foto del QR se
//    guarda directo dentro de Firestore, sin costo.)
// 5. Revisa el archivo README.md de este proyecto: ahí están las
//    reglas de seguridad que debes pegar en Firestore.
// ============================================================

const firebaseConfig = {
  apiKey: "AIzaSyBJku9KYlga7I_j3_QZ-jDI2TsCoBKvCOU",
  authDomain: "pogodirectorio.firebaseapp.com",
  projectId: "pogodirectorio",
  storageBucket: "pogodirectorio.firebasestorage.app",
  messagingSenderId: "501416762566",
  appId: "1:501416762566:web:79ed636d7315090c4d0bc7"
};

// No edites nada debajo de esta línea.
export default firebaseConfig;
