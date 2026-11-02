# Sin Rial 3.5.1 - Build 99

Fecha: 2026-11-02. Entrega local; sin commit, push ni publicacion.

## Cambios

- Buscador, selector de mes, resumen y filtros de movimientos con mayor area tactil y jerarquia consistente. Busqueda con debounce y categorias en cache por revision.
- Dos decimales truncados hacia cero en importes, calculadora, portapapeles y widgets. Conversiones decimales y sumas por centavos para evitar errores binarios. Los datos historicos no se reescriben.
- USDT se consulta al abrir o volver del segundo plano, no por temporizador ni actualizacion manual de BCV. Las versiones de ambas tasas se concilian de forma independiente.
- Lectura inicial mediante un snapshot cifrado y autenticado, validado contra la revision y los metadatos del almacenamiento canonico. Cache de descifrado acotada a 8 MiB. Guardado transaccional; widgets y recordatorios se actualizan despues de confirmar el guardado.
- Exportacion e importacion de copias portatiles con contrasena independiente del PIN. Vista previa y confirmacion antes de reemplazar datos. La restauracion conserva la seguridad del dispositivo de destino.
- Changelog y novedades de actualizacion para 3.5.1.

## Verificacion

- Suite completa: 506 pruebas Flutter aprobadas; 1 benchmark opcional omitido en esta ejecucion.
- Benchmark opcional ejecutado aparte y aprobado con 10.000 movimientos sinteticos. En host Flutter: calculo inicial de inicio 767,06 ms; lectura de cache 0,000153 ms. No son tiempos de arranque ni FPS de Android.
- Suite Android de la app: 132 pruebas aprobadas, sin fallos, errores ni omisiones.
- Analizador: 0 errores, 0 advertencias y 451 avisos informativos. Salida 0 con `--no-fatal-infos`.
- Pruebas focalizadas de cifrado, restauracion, precision, USDT y layouts aprobadas. Capturas con fuentes reales en 320x640 y 390x844, claro y oscuro; inspeccion de movimientos y copias.
- Validados contrasena incorrecta, archivo alterado, datos malformados, cancelacion de restauracion, error de escritura y conservacion del PIN.
- Validados snapshot corrupto con lectura canonica de respaldo, rollback transaccional y carga de 1.000 registros con como maximo 2 descifrados en frio y 4 al guardar un cambio.
- 254 archivos de codigo, pruebas, assets y configuracion coinciden entre repo y staging, excluido el registro de plugins generado por Flutter.
- `git diff --check` aprobado. ADB sin dispositivos conectados.

## APK

- `release/sin-rial-3.5.1-build99.apk`: 70.112.195 bytes.
- Paquete `com.lacaprichosa.app`, nombre Sin Rial, versionName 3.5.1, versionCode 99.
- No depurable; minSdk 24, targetSdk 36; ARM32, ARM64 y x86_64.
- SHA-256: `45a3f5cb3ebbcb45587156634407b38a9e96d4c765bc763c40efd6a0248b4614`.
- Firma v2 y alineacion de 16 KiB verificadas.
- Certificado SHA-256: `6e0965ff509debd2db0a5b628f6d55441457cf2fff320b44e70d2d33e62aa2a3`, igual al APK local de build 98. Se conserva la identidad de firma existente para permitir actualizaciones.
- Sin IntegrationTestPlugin en el registro generado de release ni en DEX.
- La copia entregada coincide con el artefacto de staging.
- `release/latest.json` permanece en 3.5.0+98.

## Reproduccion y evidencia

Staging: `C:/Users/Arturo/AppData/Local/SinRialBuilds/finance-final-20260916-124535`.

- `build/test-build99-final.log`
- `build/visual-build99-final.log` y `build/release99-qa`
- `build/native-app-tests-build99-final.log`
- `build/performance-build99.log`
- `build/analyze-build99-final.log`
- `build/apk-build99-final.log`

Compilacion: `flutter build apk --release --build-name=3.5.1 --build-number=99`.
Tras pruebas debug, no usar `--no-pub` en esta version de Flutter: omite la regeneracion del registro de plugins para release y deja una referencia al complemento de integracion excluido de produccion. El segundo build, con regeneracion normal, compilo correctamente.

Pruebas nativas: `gradlew :app:testDebugUnitTest`. La tarea raiz tambien ejecuta pruebas de terceros; las de local_auth_android fallan al inicializar su entorno Robolectric, fuera de la suite de la app.

## Limites pendientes de hardware

- No se instalo el APK ni se midieron arranque, FPS o latencia de guardado en un telefono real. No se afirma haber medido una reduccion de los cinco segundos reportados.
- La seleccion y escritura real con proveedores de documentos Android queda pendiente de prueba en dispositivo. La logica de exportacion, autenticacion, restauracion y persistencia se probo automaticamente.
- El formato de copia es portable; esta entrega es Android, no una distribucion nueva para iOS o Windows. La restauracion reemplaza los datos actuales y requiere la contrasena de la copia.
