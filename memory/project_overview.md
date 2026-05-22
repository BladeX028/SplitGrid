---
name: project-overview
description: Stack y estructura principal de SplitGrid — app de división de cuentas para restaurantes
metadata:
  type: project
---

SplitGrid es una app de división de cuentas para restaurantes. Stack: HTML/CSS/JS vanilla, sin frameworks, localStorage para persistencia de estado.

Archivos principales:
- `index.html` — login unificado (restaurante y cliente)
- `splitgrid-restaurante.html` — panel del restaurante
- `splitgrid-cliente.html` — app del cliente
- `js/shared.js` — funciones compartidas: países, cálculos, localStorage
- `css/splitgrid.css` — estilos dark-theme

**Why:** Es un prototipo/MVP que no requiere backend. Todo corre en el navegador con localStorage.
**How to apply:** Al hacer cambios, verificar que los datos compartidos entre restaurante y cliente se sincronizan vía localStorage (polling cada 5 segundos).
