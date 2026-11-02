# Sin Rial 3.5.1 - Build 100

Fecha: 2026-11-02. Sin Rial 3.5.1, build 100.

## Cambios sobre build 99

- Transferencias USD a USD: el usuario introduce el monto enviado y el recibido. La diferencia genera la comision y su porcentaje; el monto enviado ya incluye esa comision, sin otro debito. Se aceptan comisiones cero y se rechazan montos recibidos mayores al enviado.
- Al editar una transferencia antigua con comision adicional, se conserva el debito original y el monto recibido. Crear, editar, borrar y deshacer actualizan ambos saldos y el gasto por comision.
- Transicion de 240 ms entre Inicio, Plan y Menu: fundido con desplazamiento vertical de 5 px, sin pasar por una pestana intermedia. Las pantallas visitadas conservan su estado; las ocultas no reciben toques, foco ni animaciones. Respeta movimiento reducido.
- Mantenimiento automatico de Bs. 684 en cuentas bancarias nacionales VES corrientes y de ahorro. Cargo el dia 31 en meses de 31 dias; en los demas, el primer dia siguiente. Calendario de Caracas, incluido febrero bisiesto.
- Descripcion del cargo: `Comision mantenimiento mensual <mes>` (con tilde en la app). El mes es el periodo cerrado: noviembre se registra el 1 de diciembre. Los identificadores y cursores existentes se conservan para evitar duplicados. Las cuentas nuevas comienzan en el siguiente cierre y no se recuperan periodos antiguos omitidos.
- Changelog y novedades de actualizacion incluyen estos cambios. Se mantienen las mejoras de precision, copias portatiles, USDT y rendimiento de build 99.

## Verificacion

- Suite completa: 514 pruebas Flutter aprobadas. Un benchmark opcional omitido.
- Suite nativa de la app: 140 pruebas aprobadas, sin fallos, errores ni omisiones, sobre SDK 24 y 36.
- Analizador: 0 errores, 0 advertencias y 451 avisos informativos; salida 0 con `--no-fatal-infos`.
- Siete pruebas focalizadas aprobadas tambien con fuentes reales. Capturas inspeccionadas en 320x640 y 390x844: montos, comision y total visibles, sin desplazamiento vertical. Se retiro el control manual de tratamiento de comision del flujo automatico.
- Cubiertos: diferencia exacta de centavos, validacion de montos, saldo origen/destino, gasto de comision, edicion heredada, borrado/deshacer y cambios rapidos de pestana con y sin movimiento reducido.
- Mantenimiento: meses de 30 y 31 dias, febrero normal y bisiesto, cambio de ano, nombre del mes, alta de ahorro y migracion del cursor sin duplicar cargos existentes.
- Novedades: las siete paginas, tamanos pequenos, texto ampliado, omision/finalizacion persistente y separacion del recorrido inicial.
- 256 archivos de codigo, pruebas, assets y configuracion coinciden entre repo y staging. Se excluye el registro generado de plugins.
- `git diff --check` aprobado. ADB sin dispositivos conectados.
- Matriz del actualizador: 10 comprobaciones aprobadas usando las versiones instaladas 3.2.2+89, 3.5.0+97, 3.5.0+98, 3.5.1+99 y 3.5.1+100. Las anteriores detectan la 100; la 100 no ofrece actualizarse a si misma.

## APK

- `release/sin-rial-3.5.1-build100.apk`: 70.292.419 bytes.
- Paquete `com.lacaprichosa.app`, nombre Sin Rial, versionName 3.5.1, versionCode 100.
- No depurable; minSdk 24, targetSdk 36; ARM32, ARM64 y x86_64.
- SHA-256: `6dc4fb18470e65254e817adf9d8285beabaa08f7c7477a4c851d6ec67f1eb4ab`.
- Firma v2 y alineacion de 16 KiB verificadas.
- Certificado SHA-256: `6e0965ff509debd2db0a5b628f6d55441457cf2fff320b44e70d2d33e62aa2a3`, igual al APK local de build 99. Se conserva la firma existente para permitir actualizaciones.
- Sin IntegrationTestPlugin en el registro generado de release ni en DEX.
- La copia entregada coincide con el APK de staging.

## Evidencia

Staging: `C:/Users/Arturo/AppData/Local/SinRialBuilds/finance-final-20260916-124535`.

- `build/test-build100-final.log`
- `build/native-build100.log` y `build/app/test-results/testDebugUnitTest`
- `build/analyze-build100.log`
- `build/visual-build100.log` y `build/release100-qa`
- `build/apk-build100-final.log`
- `build/publish100-upgrade-{89,97,98,99,100}.log`

Compilacion: `flutter build apk --release --build-name=3.5.1 --build-number=100`, con regeneracion normal de plugins (sin `--no-pub`).

## Limites

- No se instalo en un telefono ni se midieron FPS o tiempo real de apertura en Android.
- El mantenimiento es un registro en la app, no una orden de cobro al banco. El importe y calendario son la regla solicitada, no una verificacion de tarifas bancarias externas.
- Android puede aplazar tareas de segundo plano. La conciliacion al abrir recupera el cierre pendiente y usa su fecha contable; no se garantiza ejecucion exacta a medianoche.
- `release/latest.json` identifica 3.5.1+100, con el tamano y SHA-256 del APK validado. La publicacion usa el tag `v3.5.1+100`.
