#README

########## NOTAS SOBRE DECISIONES DE DISEÑO IMPORTANTES ##########

1. Control de Acceso (AccessControl de OpenZeppelin)

✅ Ventajas

Seguridad: restringe las funciones críticas (solo ADMIN_ROLE).

Escalabilidad: se pueden crear más roles en el futuro solo permite "BANK_MANAGER_ROLE"

⚠️ Desventajas 

Más gas: El AccessControl permite agregar almacenamiento extra.

Más complejidad: si no se administran correctamente los roles, podrías bloquear funciones 


2. Soporte Multi-token (ETH + ERC-20)

✅ Ventajas

Mayor flexibilidad: usuarios pueden usar distintos activos.

Facilita agregar mas tokens.

⚠️ Desventajas

Complejidad : hay que manejar decimales, diferencias en decimals() y casos especiales.

Incremento en almacenamiento: balances por token/usuarios

🧮 3. Contabilidad Multi-token (Mappings anidados)

✅ Ventajas

Separación clara de saldos por token.

Lectura eficiente 

Compatible con nuevas funciones sin romper el esquema.

⚠️ Desventajas

Los mapping no pueden recorrerse fácilmente.

Más memoria

📡 4. Oráculo Chainlink

✅ Ventajas

Datos de precio confiables, descentralizados y auditados.

Permite límites dinámicos en USD 

⚠️ Desventajas

Costo de gas adicional: cada consulta  consume gas.

Si Chainlink falla o se retrasa, el contrato no puede calcular correctamente límites o conversiones.

El contrato no puede “forzar” un precio; depende de la red de oráculos.

🔢 5. Conversión de Decimales / Normalización

✅ Ventajas

Evita errores contables cuando se combina tokens con diferentes decimals().

Facilita visualización y reportes.

⚠️ Desventajas

Al reducir decimales puedes truncar valores mínimos.

Mayor lógica y gas

🧱 6. Seguridad (ReentrancyGuard + CEI Pattern + SafeERC20)

✅ Ventajas

Protege transferencias externas .

SafeERC20 asegura compatibilidad incluso con tokens problemáticos.

⚠️ Desventajas

Más gas

No puedes anidar funciones nonReentrant, limitando composición.

🧩 7. Variables immutable / constant

✅ Ventajas

Optimiza gas 

Evita manipulación posterior (mayor seguridad).

Mejora auditabilidad: parámetros fijos visibles en el deploy.

⚠️ Desventajas

No pueden cambiarse; si el mercado cambia, hay que desplegar un nuevo contrato.

Menos flexibilidad operativa

🔐 8. Bloqueo de depósitos directos (receive/fallback revert)

✅ Ventajas

Previene pérdidas accidentales de ETH enviadas directamente.

Obliga a usar las funciones seguras deposit().

⚠️ Desventajas

Menos flexibilidad

🧾 9. Eventos y Errores Personalizados

✅ Ventajas

Facilitan auditoría y debugging (eventos claros).

Los error personalizados consumen menos gas 

Mejora la legibilidad y trazabilidad.

⚠️ Desvenajas 

Cada error tiene un selector distinto.

Si agregas nuevos errores/eventos, debes reflejarlos en tus pruebas y front-end.

#################### MEJORAS REALIZADAS Y MOTIVOS ####################

Variables locales en deposit y withdraw

Se redujo lecturas de storage y se simplifico calculos temporales.

Checks-Effects-Interactions

Primero se actualizo el estado antes de transferir tokens o ETH.

Motivo: Previene ataques de reentrada 

Custom errors

Por ejemplo el : ZeroDepositNotAllowed(), BankCapExceeded().

Motivo: Ahorra gas comparado con require  y hace los errores más claros.

Seguridad en transferencias

ETH se envía con call y ERC20 con safeTransfer.

Motivo: Manejo seguro de tokens que no devuelven bool y evita fallas silenciosas.

Soporte dinámico de tokens

Funciones para agregar y quitar tokens 


Motivo: Flexibilidad y control por roles (BANK_MANAGER_ROLE).


