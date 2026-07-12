# Wellnario - Especificaciones

## Descripción y objetivos

Wellnario es una app multiplataforma (iOS, macOS, Web) para gestionar aspectos de la salud que, destacando algunos que no están cubiertos por la mayoría de las apps generalistas de salud que hay en el mercadoles.

### Funcionalidades

- Registro de las tomas de suplementos nutricionales
- Análisis del sueño, identificando patrones y potenciales factores que influyen en la duración y calidad del sueño
- Registro de marcadores de salud y análisis de su evolución
- Estimación de la edad biológica
- Entrenamientos de fuerza: registro y análisis de rendimiento
- Estimación de métricas de estrés, fatiga y recuperación

### Detalle de las funcionalidades

#### Gestión de suplementos alimenticios

- La app permitirá que el usuario cree:
    - Suplementos. Un suplemento es una marca y un modelo concretos. El tipo de presentación será: polvo, pastillas, cápsulas, etc. Para cada suplemento, el usuario indicará los activos que contiene y que le interesa monitorizar, indicando la cantidad por unidad de presentación
    - Instancia de suplementos. Una instancia representa un lote o unidad específica del suplemento almacenada por el usuario, permitiendo registrar información como la etiqueta identificativa, la fecha de caducidad y notas adicionales.
    - Activos. Un activo es una sustancia química o componente específico (por ejemplo, vitamina C, omega-3, cafeína). El usuario podrá indicar cuál es su consumo objetivo de cada componente.
- El usuario podrá registrar el consumo de suplementos, incluyendo la instancia del suplemento, la cantidad consumida, la fecha y hora del consumo
- El usuario podrá ver gráficas de consumo semanal, mensual, anual o en intervalo especificado. En las gráficas se mostrarán las bandas de consumo objetivo, además del consumo diario y la línea media de consumo en el período

## Arquitectura tecnológica

- Backend: Dart
- Frontend: UIKit (iOS/macOS), Flutter (Web)
- Base de datos:
    - Remota: PostreSQL en Railway
    - Local: SQLite

## Modelo de datos

### Gestión de suplementos: tablas

- Usuario
- Activo. Atributos:
    - id (UUID)
    - nombre (VARCHAR)
    - descripcion (TEXT)
    - consumo_diario_propuesto_hombres (DECIMAL)
    - consumo_diario_propuesto_mujeres (DECIMAL)
    - unidad_medida_consumo
    - imagen_representativa
    - fecha_creacion (TIMESTAMP)
    - fecha_actualizacion (TIMESTAMP)
- Suplemento. Atributos:
    - id (UUID)
    - nombre (VARCHAR)
    - descripcion (TEXT)
    - categoria (VARCHAR)
    - marca (VARCHAR)
    - precio (DECIMAL)
    - imagen_url (VARCHAR)
    - tipo_presentacion (VARCHAR)
    - fecha_creacion (TIMESTAMP)
    - fecha_actualizacion (TIMESTAMP)
- SuplementoActivo. Atributos:
    - id (UUID)
    - suplemento_id (UUID, FK)
    - activo_id (UUID, FK)
    - cantidad_activo (DECIMAL)
    - unidad_medida_activo (VARCHAR)
    - cantidad_suplemento (DECIMAL)
    - unidad_medida_suplemento (VARCHAR)
    - fecha_creacion (TIMESTAMP)
    - fecha_actualizacion (TIMESTAMP)
- Usuario_Activo. Atributos:
    - usuario_id (UUID)
    - activo_id (UUID)
    - limite_inferior_consumo_objetivo (DECIMAL)
    - limite_superior_consumo_objetivo (DECIMAL)
    - fecha_creacion (TIMESTAMP)
    - fecha_actualizacion (TIMESTAMP)
- Instancia_Suplemento. Atributos:
    - id (UUID)
    - suplemento_id (UUID, FK)
    - usuario_id (UUID, FK)
    - etiqueta_identificativa (VARCHAR)
    - fecha_caducidad (TIMESTAMP)
    - notas (TEXT)
    - fecha_creacion (TIMESTAMP)
    - fecha_actualizacion (TIMESTAMP)
- Consumo. Atributos:
    - id (UUID)
    - instancia_suplemento_id (UUID, FK)
    - usuario_id (UUID, FK)
    - cantidad_consumida (DECIMAL)
    - fecha_consumo (TIMESTAMP)
    - hora_consumo (TIME)
    - notas (TEXT)
    - fecha_creacion (TIMESTAMP)
    - fecha_actualizacion (TIMESTAMP)
- TipoPresentacion. Atributos:
    - id (UUID)
    - nombre (VARCHAR)
    - fecha_creacion (TIMESTAMP)
    - fecha_actualizacion (TIMESTAMP)
- TipoPresentacion_Imagen. Atributos:
    - id (UUID)
    - tipo_presentacion_id (UUID, FK)
    - imagen
    - descripcion (TEXT)
    - fecha_creacion (TIMESTAMP)
    - fecha_actualizacion (TIMESTAMP)

### Gestión de suplementos: carga inicial
- La aplicación incluirá datos predefinidos de:
    - Activos comunes
    - Tipos de presentación comunes, incluyendo varias imágenes


## Interfaz de usuario

Inicialmente desarrollaremos únicamente la funcionalidad de gestión de suplementos, pero crearemos placeholders de menús y opciones de menú para las otras funcionalidades

Instrucciones para el diseño de la interfaz:

El menú de configuración permitirá escoger idioma (entre inglés y español). La app será multilenguaje.

Intenta hacer la interfaz de usuario lo más parecida posible a la de la app Peakwatch

Should have a super clean, minimalist design, very design-forward and aesthetic. Sweat all the tiny details and make everything feel super premium. Make every interaction extremely delightful - you can go so far as to write custom Metal shaders, custom UI components, etc, to make everything fluid, unique, delightful.

Me gustaría que la app tuviera muchas imágenes y animaciones. Puedes usar las extensiones Fal y/o Hyperframes para ello. Make every transition fluid and delightful, fun gestures, bouncy, Apple-y liquid glass kind of feel to it. Use shader effects to make transitions look special and memorable, to make image generation look good, even to make the chat and token streaming experience unique and fun. Think through the flows to make it usable and show me the information I need without cluttering the screen or making it too technical.

For the most part you should just use your best judgment, not ask me questions, unless you get hard stuck - I want you to interpret this however you want and show me what you are capable of. Build it end to end and verify all the interactions and transitions and functionality in the simulator if you can. Feel free to use the web to download any resources and documentation needed to make this feel great; don't just resort to the boring iOS standards for everything because that's easy. Dig deep and sweat every detail.

Find a way to carefully audit every frame/pixel and make it look absolutely stellar, like top 1% of human designers, instantly eligible for an Apple Design Award.