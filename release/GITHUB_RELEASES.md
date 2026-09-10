# Actualizaciones con GitHub Releases

La app puede revisar actualizaciones fuera de Play Store usando GitHub Releases.

## Opcion recomendada

Compila la app conectada a la API publica del repositorio:

```powershell
flutter build apk --release `
  --dart-define=SIN_RIAL_GITHUB_OWNER=TU_USUARIO `
  --dart-define=SIN_RIAL_GITHUB_REPO=TU_REPO
```

Luego crea un release con tag en este formato:

```text
v2.1.6+56
```

Adjunta el APK al release. La app busca el ultimo release, lee el tag y abre el primer asset `.apk` disponible.

## Opcion con manifest

Si prefieres controlar el enlace exacto, compila con:

```powershell
flutter build apk --release `
  --dart-define=SIN_RIAL_UPDATE_URL=https://github.com/TU_USUARIO/TU_REPO/releases/latest/download/latest.json
```

En cada release adjunta un archivo `latest.json` junto al APK. Puedes usar `latest.json.example` como base.

## Importante

Android solo instala una actualizacion encima de otra si ambos APK estan firmados con la misma clave. Si cambias de PC, de keystore o usas GitHub Actions sin configurar la misma firma, Android pedira desinstalar la app anterior.
