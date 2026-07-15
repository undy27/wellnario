# Wellnario - Especificaciones

## Descripción y objetivos

Wellnario es una app multiplataforma (iOS, macOS, Web) para gestionar aspectos de la salud, destacando algunos que no están cubiertos por la mayoría de las apps generalistas de salud del mercado.

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

### Navegación principal

- La barra inferior contiene cinco destinos: **Hoy**, **Suplementos**, **Sueño**, **Salud** y **Fitness**.
- La selección se representa mediante una cápsula fucsia animada. La transición replica el lenguaje de movimiento de los selectores internos: la cápsula cambia de tamaño y transparencia mientras se desplaza.
- Los títulos de Sueño, Salud y Fitness permanecen visibles mientras se desplaza el contenido.

### Hoy

- Muestra tarjetas resumen compactas de Sueño, Recuperación, Estrés, Suplementos y Fitness.
- Ofrece accesos directos para:
    - Añadir una toma de suplementos.
    - Iniciar un entrenamiento.
    - Cargar una analítica.
    - Registrar un factor que pueda influir en el sueño, tanto predefinido como creado por el usuario.

### Sueño

- La última sesión de sueño se presenta en una única tarjeta con duración, horario, fuente y un hipnograma nocturno.
- El hipnograma representa Despierto, REM, Ligero y Profundo a lo largo de la noche, e indica a la derecha la duración total de cada fase con formato compacto, por ejemplo `1h 43m`.
- La tarjeta de estado de Apple Health sólo aparece cuando la integración está configurada. Permanece fija bajo el título, utiliza un 45 % de opacidad y conserva el mismo tamaño durante la sincronización y una vez completada.
- La gráfica de tendencia permite seleccionar las métricas Calidad, Duración, REM, Profundo y Ligero. Calidad corresponde a la puntuación de sueño disponible en Apple Health.
- Los intervalos disponibles son 7 días, 30 días, 6 meses y Desde el principio:
    - 7 días y 30 días: un dato por día.
    - 6 meses: una media por semana cuando existe al menos un mes de datos; en caso contrario, un dato por día.
    - Desde el principio: una media por año cuando existen al menos dos años de datos; en caso contrario, un dato por día.
- Las curvas de 6 meses y Desde el principio se suavizan para facilitar la lectura.
- La escala vertical se ajusta al rango real visible y muestra sus valores mínimo y máximo.
- El usuario puede mantener el dedo y arrastrarlo por la gráfica para consultar fecha y valor, con respuesta háptica al cambiar de punto.
- Un selector persistente permite mostrar exclusivamente Media o Tendencia. La opción predeterminada es Tendencia:
    - La media se dibuja en cyan.
    - La tendencia es una regresión lineal calculada con todos los datos diarios del intervalo, aunque la serie visible esté agregada. Se muestra en verde cuando asciende y en rojo cuando desciende, con sus valores inicial y final rotulados sobre la línea.

### Salud y Fitness

- Salud muestra los biomarcadores actuales y la edad biológica estimada.
- Su tarjeta de sincronización sigue la misma posición fija, tamaño y transparencia que la de Sueño.
- Fitness muestra el resumen de actividad y entrenamientos, con acceso directo para iniciar una sesión.

### Integración con Apple Health

- La configuración permite conectar Wellnario con Apple Health y solicitar permisos de lectura y escritura con las descripciones de privacidad requeridas por iOS.
- La sincronización se ejecuta únicamente al conectar Apple Health, al arrancar la app o al abandonar la selección de fuentes después de modificarla.
- Las fuentes disponibles se organizan en secciones desplegables: Sueño, Corazón, Actividad y Entrenamientos.
- Cada fuente puede activarse o desactivarse por categoría, permitiendo excluir dispositivos o aplicaciones cuyos datos no sean fiables.
- Los cambios de fuentes se acumulan en pantalla y provocan una sola resincronización al salir, siempre que haya modificaciones.
- La configuración también ofrece la conexión con Oura mediante su API.

### Apariencia y accesibilidad

- En Configuración se puede seleccionar **Oscuro**, **Claro** o **Sistema**.
- Oscuro es el modo predeterminado para instalaciones que aún no tengan una preferencia guardada.
- La selección persiste entre ejecuciones. Sistema sigue en vivo la apariencia configurada en iOS.
- La interfaz clara dispone de una paleta semántica completa para fondos, superficies, tarjetas, textos, campos, estados, gráficas y navegación, manteniendo el contraste y la jerarquía visual.
- Todos los selectores de la app utilizan fucsia como color de selección.
- La app responde inmediatamente a los cambios de tamaño de texto de iOS, tanto al aumentarlo como al reducirlo, sin necesidad de reiniciarla.
- Se respetan Reducir movimiento, Reducir transparencia, colores de mayor contraste y Dynamic Type.

### Configuración general

- El menú de configuración permite escoger idioma entre inglés y español. La app es multilenguaje.
- Configuración siempre ofrece una navegación de vuelta al resumen de Hoy.

### Dirección visual

Intenta hacer la interfaz de usuario lo más parecida posible a la de la app Peakwatch

Should have a super clean, minimalist design, very design-forward and aesthetic. Sweat all the tiny details and make everything feel super premium. Make every interaction extremely delightful - you can go so far as to write custom Metal shaders, custom UI components, etc, to make everything fluid, unique, delightful.

Me gustaría que la app tuviera muchas imágenes y animaciones. Puedes usar las extensiones Fal y/o Hyperframes para ello. Make every transition fluid and delightful, fun gestures, bouncy, Apple-y liquid glass kind of feel to it. Use shader effects to make transitions look special and memorable, to make image generation look good, even to make the chat and token streaming experience unique and fun. Think through the flows to make it usable and show me the information I need without cluttering the screen or making it too technical.

For the most part you should just use your best judgment, not ask me questions, unless you get hard stuck - I want you to interpret this however you want and show me what you are capable of. Build it end to end and verify all the interactions and transitions and functionality in the simulator if you can. Feel free to use the web to download any resources and documentation needed to make this feel great; don't just resort to the boring iOS standards for everything because that's easy. Dig deep and sweat every detail.

Find a way to carefully audit every frame/pixel and make it look absolutely stellar, like top 1% of human designers, instantly eligible for an Apple Design Award.
