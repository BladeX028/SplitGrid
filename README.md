# SplitGrid — Sistema Distribuido de División de Gastos -UC
**Colombia · Brasil · Francia · Italia · Rusia**
*Universidad Central | Ingeniería de Sistemas | Sistemas Distribuidos | Versión 2.0*

---

## 📁 Estructura del proyecto

```
splitgrid/
├── index.html                  ← Inicio de sesión unificado (clientes y restaurantes)
├── splitgrid-cliente.html      ← App del comensal / cliente de mesa
├── splitgrid-restaurante.html  ← Panel de administración del restaurante
├── splitgrid-schema.sql        ← Esquema PostgreSQL completo
├── splitgrid.code-workspace    ← Abre este archivo en VS Code
├── css/
│   └── splitgrid.css           ← Estilos compartidos (tema oscuro, componentes)
└── js/
    └── shared.js               ← Lógica compartida, datos de países, utilidades
```

---

## 🚀 Cómo abrir en VS Code

1. Abre VS Code
2. **Archivo → Abrir área de trabajo desde archivo...**
3. Selecciona `splitgrid.code-workspace`
4. VS Code te pedirá instalar las extensiones recomendadas — acepta todas
5. En el explorador, haz clic derecho sobre `index.html` → **"Open with Live Server"**
6. El navegador abrirá automáticamente en `http://127.0.0.1:5500`

---

## 🔌 Extensiones recomendadas para VS Code

| Extensión | ID | Para qué sirve |
|-----------|-----|----------------|
| **Live Server** | `ritwickdey.LiveServer` | Recarga automática al guardar — **obligatoria** |
| **Prettier** | `esbenp.prettier-vscode` | Formatea HTML, CSS y JS automáticamente |
| **ESLint** | `dbaeumer.vscode-eslint` | Detecta errores en JavaScript |
| **Auto Rename Tag** | `formulahendry.auto-rename-tag` | Renombra etiquetas HTML en pares |
| **Auto Close Tag** | `formulahendry.auto-close-tag` | Cierra etiquetas HTML automáticamente |
| **SQLTools** | `mtxr.sqltools` | Visualiza y ejecuta el schema PostgreSQL |
| **Path IntelliSense** | `christian-kohler.path-intellisense` | Autocompleta rutas de archivos |
| **Color Highlight** | `naumovs.color-highlight` | Muestra colores CSS en el editor |
| **Live Share** | `ms-vscode.live-share` | Colaboración en tiempo real (trabajo en equipo) |

### Instalación rápida (todas a la vez)
Abre la terminal en VS Code (`Ctrl+Ñ` / `Ctrl+\``) y ejecuta:
```bash
code --install-extension ritwickdey.LiveServer
code --install-extension esbenp.prettier-vscode
code --install-extension dbaeumer.vscode-eslint
code --install-extension formulahendry.auto-rename-tag
code --install-extension formulahendry.auto-close-tag
code --install-extension mtxr.sqltools
code --install-extension christian-kohler.path-intellisense
code --install-extension naumovs.color-highlight
```

---

## 🌐 Flujo de uso de la aplicación

### 1. Como restaurante
1. Abre `http://127.0.0.1:5500` (o haz clic en `index.html` → Live Server)
2. Selecciona **"Soy restaurante"**
3. Ingresa cualquier email y contraseña (mín. 6 caracteres) — modo demo
4. El sistema detecta tu país automáticamente y carga el menú, moneda e idioma
5. En el panel: crea sesiones de mesa, gestiona pedidos y visualiza pagos en tiempo real

### 2. Como cliente / comensal
1. Abre `http://127.0.0.1:5500` en otra pestaña o dispositivo
2. Selecciona **"Soy cliente"**
3. Inicia sesión, entra como invitado, o usa Google
4. Ve a **"Unirse a mesa"** e ingresa el código `DEM012` (demo)
5. Visualiza pedidos, tu parte a pagar y liquida con el método de pago de tu país

### 3. Para probar los dos en simultáneo
- Pestaña 1: Panel del restaurante con la mesa DEM012 activa
- Pestaña 2: App del cliente unido a DEM012
- Los cambios se sincronizan en tiempo real vía `localStorage` compartido (mismo navegador)

---

## 🌍 Países y configuración automática

| País | Idioma | Moneda | IVA | Propina | Métodos de pago |
|------|--------|--------|-----|---------|-----------------|
| 🇨🇴 Colombia | es-CO | COP | 19% | 10% | Nequi, Daviplata, PSE, Tarjeta, Efecty |
| 🇧🇷 Brasil | pt-BR | BRL | 0% | 10% | PIX, Boleto, Cartão |
| 🇫🇷 Francia | fr-FR | EUR | 20% | 0% | Carte Bleue, Apple Pay, Google Pay, Virement |
| 🇮🇹 Italia | it-IT | EUR | 22% | 0% | Carta, Bonifico, Apple Pay, Satispay |
| 🇷🇺 Rusia | ru-RU | RUB | 20% | 0% | СБП, Мир, YooMoney |

La detección es automática por **zona horaria del navegador** y **idioma del sistema operativo**. No se le pide al usuario que seleccione el país manualmente.

---

## ⚡ Características implementadas

- ✅ **Login unificado** — un solo `index.html` para clientes y restaurantes
- ✅ **Detección automática de país** — por timezone + idioma del navegador
- ✅ **Moneda e idioma automáticos** — según el país detectado
- ✅ **Cerrar sesión funcional** — botón en sidebar de ambas apps, redirige a `index.html`
- ✅ **Compartir con selección múltiple** — elige personas específicas o "todos los comensales"
- ✅ **Comensal sin app (proxy)** — agrega personas sin teléfono; otro comensal gestiona sus pagos
- ✅ **Actualización en tiempo real** — polling cada 5 segundos vía localStorage compartido
- ✅ **Métodos de pago por país** — cada país muestra sus pasarelas locales
- ✅ **IVA y propina automáticos** — según configuración del restaurante y país

---

## 🗄️ Base de datos PostgreSQL

El archivo `splitgrid-schema.sql` contiene el esquema completo. Para usarlo:

```bash
# Crear la base de datos
createdb splitgrid

# Aplicar el schema
psql -d splitgrid -f splitgrid-schema.sql
```

Con la extensión **SQLTools** de VS Code puedes conectarte a PostgreSQL directamente desde el editor.

---

## 📝 Notas de arquitectura

- **Persistencia actual**: `localStorage` del navegador (simula la base de datos PostgreSQL para el prototipo)
- **Tiempo real**: polling cada 5s — en producción se reemplaza por WebSockets (socket.io / ws)
- **Sin dependencias externas**: el proyecto corre directamente con Live Server, sin npm ni bundlers
- **CSS compartido**: `css/splitgrid.css` — tema oscuro con variables CSS, sin frameworks
- **JS compartido**: `js/shared.js` — datos de países, funciones de formateo y utilidades

---

*SplitGrid v2.0 — Diana Marcela Garzón · Blade Gómez González*
*Universidad Central | Facultad de Ingeniería | Sistemas Distribuidos | 2026*
