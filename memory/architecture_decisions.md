---
name: architecture-decisions
description: Decisiones arquitecturales clave de SplitGrid, incluyendo cambios en mayo 2026
metadata:
  type: project
---

## Decisión: IVA incluido en precios
El IVA NO se calcula separado. Los precios ya incluyen IVA. `sessionTotal` y `calcPersonTotal` NO agregan tax. El campo `tax` en config solo es referencial.

**Why:** Pedido explícito del usuario (2026-05-21). Los precios de menú ya incluyen IVA.

## Decisión: Propina separada del total
`calcPersonTotal` retorna `{sub, tax:0, tip, total: sub + transferred}` — el `total` NO incluye propina. La propina es opcional (cliente elige entre 3%-15%). Se muestra por separado.

**Why:** La propina era aplicada automáticamente, causando discrepancias entre lo que veía el cliente y el restaurante.

## Decisión: Pagos en efectivo como pending_cash
Cuando el cliente paga con "Efectivo", el status del pago es `pending_cash` (no `paid`). El restaurante debe confirmarlo manualmente. Solo cuando confirma cambia a `paid` y la cuenta del cliente se deduce.

**Why:** El efectivo requiere confirmación física del restaurante.

## Estructura de un pago (payment object)
```js
{
  personId, amount, baseAmount, tipAmount, method,
  status: 'paid' | 'pending_cash',
  ref, paidAt, tipIncluded, tipPct
}
```
`baseAmount` = subtotal sin propina. `tipAmount` = propina pagada (0 si no incluida).

## Tables: números y IDs
Las mesas tienen `id` (único, puede ser cualquier número) y `number` (número visible). Se agregan en `saveConfig` cuando el usuario aumenta `numTables`. No se eliminan automáticamente.
