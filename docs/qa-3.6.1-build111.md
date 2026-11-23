# Sin Rial 3.6.1 / build 111 — prueba local

Validación realizada el 23 de noviembre de 2026. APK preparada para prueba manual; no se publicó en GitHub ni se modificó `release/latest.json`.

## Cambios de esta revisión

- Se eliminó la limpieza destructiva de proveedores retirados. Las cuentas antiguas de Kontigo, sus movimientos, transferencias, ajustes y reglas recurrentes se conservan al cargar datos y al exportar/importar respaldos. Kontigo sigue fuera del catálogo para crear cuentas nuevas. Esto no recupera datos que una versión anterior ya haya eliminado.
- Se corrigió el ancho disponible del selector de cuentas, incluyendo el borde exterior, para mantener las cuatro opciones en una fila. Las etiquetas tienen una altura común para conservar su alineación cuando un texto largo se reduce.
- Se aclaró que las copias periódicas se intentan al usar la app; con la app cerrada quedan pendientes hasta volver a abrirla y desbloquearla.
- Se incrementó el número de compilación de 110 a 111, conservando la versión 3.6.1. La APK incluye los cambios locales que ya existían en la build 110.

## Validación

| Comprobación | Resultado |
| --- | --- |
| Suite Flutter completa | 600 aprobadas, 0 fallidas, 1 omitida |
| Regresión de historial, respaldo cifrado, selector y versión | 8 aprobadas |
| Pruebas nativas de la app (`:app:testDebugUnitTest`) | 175 aprobadas en 14 suites, sin fallos ni errores |
| Análisis estático | 0 errores, 0 advertencias, 491 observaciones informativas; el comando devuelve 1 por esas observaciones |
| Capturas con tipografía real | Selector y cuentas a 320 y 412 píxeles; texto al 130 % |
| Paridad de código, pruebas, recursos y fuentes Android | 287 archivos coincidentes entre proyecto y copia de compilación |
| Firma APK | v2 válida; certificado coincidente con la APK pública de la build 100 |
| Alineación ZIP | Verificada para páginas de 16 KiB |
| Registro de integración en DEX de release | No contiene `IntegrationTestPlugin` |

La ejecución amplia `testDebugUnitTest` también intentó ejecutar las pruebas propias de la dependencia `local_auth_android`. Dos clases no pudieron inicializarse porque su versión de Robolectric admite API 35 como máximo y la aplicación apunta a API 36. No se alteró la dependencia para ocultar este resultado. La suite nativa propia de Sin Rial se ejecutó después de forma explícita y pasó completa.

## APK

- Archivo entregado: `C:/Users/Arturo/Downloads/sin-rial-3.6.1-prueba-build111.apk`
- Paquete: `com.lacaprichosa.app`
- Versión: `3.6.1`; código: `111`
- minSdk: 24; targetSdk: 36
- Arquitecturas: ARM32, ARM64 y x86_64
- Tamaño: 73 877 811 bytes
- SHA-256: `59c5e2c1dd8a9e0900bac6801b560cb3a528e0d33dc9e3240abe3f428fa681c2`
- Certificado SHA-256: `6e0965ff509debd2db0a5b628f6d55441457cf2fff320b44e70d2d33e62aa2a3`

Compilación aislada en `C:/Users/Arturo/AppData/Local/SinRialBuilds/trial-111-20261123`, con Flutter 3.47.2 y Android Studio JBR. Evidencia: `focused-111.log`, `full-111.log`, `analyze-111-final.log`, `apk-111.log`, `signature-111.log`, `native-111.log`, `native-app-111.log` y `build/design-qa/`.

## Prueba manual pendiente

No había dispositivo Android ni emulador conectado. La instalación, biometría y comportamiento real de notificaciones siguen pendientes de prueba en teléfono.

1. Exportar un respaldo cifrado e instalar la APK sobre la app existente, sin desinstalarla.
2. Comprobar cuentas, saldos e historial; crear y editar una cuenta desde el selector.
3. Registrar un gasto y una transferencia, comprobar sus comisiones y revertir los movimientos de prueba.
4. Revisar un pago de tarjeta, el resumen mensual y la exportación de un presupuesto.
5. Probar PIN/biometría y guardar un respaldo manual; comprobar el estado de las copias periódicas.

La publicación queda pendiente de la prueba del usuario.
