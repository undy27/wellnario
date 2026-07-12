# Wellnario

Aplicación iPhone nativa para gestionar suplementos, sus existencias y las tomas diarias. Esta primera entrega implementa el alcance de suplementos descrito en `doc/specs.md`; el resto de áreas de salud aparecen como destinos _coming soon_.

## Stack

- UIKit y Swift 6, sin SwiftUI ni Flutter.
- iOS 17 o posterior; destino exclusivo iPhone.
- SQLite local mediante la biblioteca nativa `sqlite3`, sin dependencias de ejecución.
- Proyecto reproducible con XcodeGen y un `Wellnario.xcodeproj` ya generado.
- Español e inglés, seleccionables en Ajustes sin reiniciar la app.

No existe aún un servidor: todos los datos permanecen en el dispositivo. La UI consume `WellnarioRepositoryProtocol`, por lo que una implementación futura podrá sincronizar con el backend Dart/PostgreSQL sin acoplar UIKit al transporte o al esquema remoto.

## Funcionalidad incluida

- CRUD de suplementos, composición por activos y unidades compatibles.
- CRUD de existencias/lotes con etiqueta, caducidad y notas.
- Catálogo inicial bilingüe de activos y presentaciones; creación de activos propios.
- Objetivos personales por activo con historial de vigencia.
- Registro, edición y eliminación de tomas con fecha, hora, cantidad, lote y notas.
- Diario agrupado por día, panel de hoy, alertas de caducidad y acceso rápido a una toma.
- Tendencias semanales, mensuales, anuales y personalizadas con consumo diario, media y banda objetivo.
- Historial consistente: cada toma guarda una instantánea de producto, lote y aportes activos, de modo que una edición posterior no altera las gráficas pasadas.
- Archivado seguro para registros que ya tienen historial y borrado físico para registros sin uso.
- Dynamic Type, VoiceOver, estados vacíos, reducción de movimiento/transparencia y contraste adaptado.

## Abrir y ejecutar

1. Abre `Wellnario.xcodeproj` con Xcode.
2. Selecciona el esquema `Wellnario` y un simulador de iPhone con iOS 17 o posterior.
3. Ejecuta con `⌘R`.

Si modificas `project.yml`, regenera el proyecto con:

```sh
xcodegen generate
```

Compilación reproducible desde terminal:

```sh
xcodebuild \
  -project Wellnario.xcodeproj \
  -scheme Wellnario \
  -sdk iphonesimulator \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO build
```

## Pruebas

El esquema incluye pruebas unitarias del repositorio y pruebas de interfaz para navegación, cambio de idioma y el flujo completo suplemento → existencia → toma.

```sh
xcodebuild \
  -project Wellnario.xcodeproj \
  -scheme Wellnario \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  CODE_SIGNING_ALLOWED=NO test
```

Las pruebas de interfaz aceptan estos argumentos de lanzamiento internos: `--ui-testing`, `--reset-data`, `--language es|en` y `--initial-tab today|supplements|diary|trends|more`.

## TestFlight

El script `./upload_testflight.sh` crea un archive de distribución, exporta el IPA y lo sube con una clave de App Store Connect. Guarda estas credenciales en `.env` (el archivo está ignorado por Git):

```sh
APP_STORE_CONNECT_API_KEY_ID="…"
APP_STORE_CONNECT_API_ISSUER_ID="…"
APP_STORE_CONNECT_API_KEY_PATH="/ruta/segura/AuthKey_….p8"
```

Para publicar una versión:

```sh
TESTFLIGHT_BUILD_NAME=1.0.1 ./upload_testflight.sh
```

El número de compilación es una marca de tiempo única por defecto. Para crear y validar el IPA sin subirlo, añade `TESTFLIGHT_SKIP_UPLOAD=1`.

## Persistencia y evolución

La base de datos se crea en Application Support como `Wellnario.sqlite`. Las migraciones se versionan en `schema_migrations`, se activan claves foráneas e índices y los decimales se guardan como texto canónico para no perder precisión binaria.

Para el backend futuro se mantendrá Dart como única tecnología de servidor y PostgreSQL como almacenamiento remoto. La siguiente etapa natural es añadir una implementación remota/sincronizable del protocolo del repositorio, autenticación y resolución de conflictos, conservando SQLite como caché _offline-first_.

> Wellnario es una herramienta de registro y no sustituye el diagnóstico ni el consejo de un profesional sanitario.
