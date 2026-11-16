# Automatic bank-app shortcuts

Verified against Google Play listings on 2026-11-16. Android checks only the packages declared in `AndroidManifest.xml`; it does not enumerate the user's installed apps. Dart uses the catalog below, not package overrides from imported backups.

| Provider | Google Play listing |
| --- | --- |
| Venezuela | https://play.google.com/store/apps/details?id=com.bancodevenezuela.bdvdigital |
| Venezolano de Credito | https://play.google.com/store/apps/details?id=com.venezolano.vol_app |
| Mercantil | https://play.google.com/store/apps/details?id=com.mercantilbanco.mercantilmovil |
| Provincial | https://play.google.com/store/apps/details?id=com.totaltexto.bancamovil |
| Bancaribe | https://play.google.com/store/apps/details?id=bancaribe.miconexion |
| Caroni | https://play.google.com/store/apps/details?id=com.click.caroni.normal.app.click |
| Banesco | https://play.google.com/store/apps/details?id=com.banesco.samfbancamovilunificada |
| Bancamiga | https://play.google.com/store/apps/details?id=com.bancamiga |
| Banplus | https://play.google.com/store/apps/details?id=com.asociadosgerenciales.banpluspay |
| BNC | https://play.google.com/store/apps/details?id=bnc.bncnet.mobile2 |
| Ubii | https://play.google.com/store/apps/details?id=ubii.ubiipagos.com.ubiiapp |
| Zinli | https://play.google.com/store/apps/details?id=com.zinli.app |
| Wally Tech | https://play.google.com/store/apps/details?id=com.kinpos.wallytech |

Installed apps launch without account, amount or credential extras. Missing apps open their exact Play listing; without Play, the same listing opens in the browser. Providers outside the verified catalog use a Play search for the provider name. Cash and food-balance accounts have no shortcut. Package IDs and availability can change; extend the catalog only after checking the actual publisher.

Robolectric tests cover Android 11 and 16 launch/fallback behavior. Actual installation, OEM restrictions and bank-app startup still need physical-device testing.
