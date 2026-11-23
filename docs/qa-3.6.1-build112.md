# Sin Rial 3.6.1 / build 112 — prueba local

Revisión del 23 de noviembre de 2026 a partir de las capturas del usuario. Sin publicación en GitHub; `release/latest.json` sigue sin cambios.

## Correcciones

- Inicio: balance dentro de una superficie con degradado discreto y gráfico contenido; menús con filas redondeadas coherentes con los submenús.
- Submenús: fondo opaco sin desenfoque costoso. Las acciones esperan el cierre de la hoja anterior y se ignoran pulsaciones repetidas durante el cierre.
- Nueva cuenta: desaparece el selector de diseño. Las cuentas normales usan siempre la identidad de su banco/proveedor, incluidas las cuentas importadas que tenían otro diseño guardado. El cambio de tipo anima la altura y la entrada de los campos. Las tarjetas de crédito conservan su selector de diseño.
- Cuentas: excluye tarjetas de crédito y su acceso directo; siguen disponibles en su sección propia e Inicio.
- Tarjetas: Venezuela con dos tonos grises y cinta de colores lateral; información financiera separada de la decoración. Chip y contactless juntos, moneda «Bolívares» y proporción de tarjeta física en cuentas. Logo Wally ajustado al círculo.
- Movimientos: botón Guardar medido a su altura real; el teclado activa el formulario compacto, con campos desplazables. Se probaron ingreso, gasto y transferencia en ambos temas con texto al 130 %.
- Hora: selector Material Android de reloj como entrada principal, con modo de teclado numérico, validación, cancelar y conservación de la fecha del movimiento.
- UVC: actualización inmediata al desbloquear; se mantienen los disparadores al iniciar, regresar, medianoche y cada 30 minutos mientras la app está activa. Un historial importado con fechas inválidas ya no interrumpe la actualización.

## Validación

- Suite Flutter completa: 615 aprobadas, 0 fallidas, 1 omitida.
- Suite nativa propia de Android: 175 aprobadas en 14 suites, sin fallos ni errores.
- Análisis estático: 0 errores, 0 advertencias y 488 observaciones informativas.
- Capturas reales de Manrope revisadas: Inicio, menús, cuentas, selector de movimiento, teclado, reloj y tarjeta Venezuela. Pruebas específicas a 320, 360, 390 y 412 px, temas claro/oscuro y texto ampliado.
- Consulta HTTPS directa al BCV: HTTP 200. El lector de la app reconoció 50 cotizaciones; última fecha elegible y publicada en la respuesta: 2026-11-20; IDI: 4.49179977. No se sustituyó la fecha de publicación por la fecha de consulta.
- Regresiones UVC: revaluación al desbloquear y por temporizador, conservación de saldos bancarios y límite aprobado, rechazo de fechas futuras e historial inválido.
- Comprobaciones APK: firma v2 válida con el certificado anterior; ZIP alineado a 16 KiB; DEX sin `IntegrationTestPlugin`.

Las comprobaciones de geometría antiguas se adaptaron al gráfico con márgenes y a las filas redondeadas, conservando límites de ancho/altura y contención del texto. La selección de mes en una prueba ahora espera que la fila desplazada esté visible y acepte el toque.

## Artefacto

- Archivo: `C:/Users/Arturo/Downloads/sin-rial-3.6.1-prueba-build112.apk`
- Paquete: `com.lacaprichosa.app`; versión `3.6.1`; build `112`
- Android mínimo API 24; objetivo API 36; ARM32, ARM64 y x86_64
- Tamaño: 73 877 811 bytes
- SHA-256: `d5be1104c1607d0b14a3d0ee4c2255235ecb1ceca129fbb521f5325ed53b48fd`
- Certificado SHA-256: `6e0965ff509debd2db0a5b628f6d55441457cf2fff320b44e70d2d33e62aa2a3`

## Prueba en teléfono

No había dispositivo conectado. Pendiente verificar fluidez real, teclado del fabricante y biometría. Las pruebas de widgets no equivalen a medir rendimiento en un teléfono.

Instalar sobre la app existente sin desinstalar. Revisar Inicio/Menú, alternar tipos de cuenta, crear un movimiento con teclado abierto, elegir hora en ambos modos y comprobar que una tarjeta indexada conserva su fecha de IDI. La actualización UVC requiere conectividad y disponibilidad de la fuente; no se promete ejecución continua con la app cerrada.

Evidencia conservada en la carpeta de compilación: `full-112-final.log`, `analyze-112-final.log`, `verify-112.log`, `native-112.log`, `apk-112.log`, `signature-112.log`, `bcv-live-112.html` y `build/design-qa/`. La copia anterior de los archivos modificados está en `original-source-backup/`.
