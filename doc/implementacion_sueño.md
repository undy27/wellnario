# Implementación técnica de la puntuación de sueño

Este documento describe cómo Wellnario construye las sesiones de sueño a partir
de Apple Health y cómo calcula su **calidad del sueño** en una escala de 0 a
100. Incluye las entradas, las reglas de ausencia de datos, la configuración
de pesos, las correcciones manuales y la métrica de caída nocturna de la
frecuencia cardíaca.

La puntuación es un indicador de bienestar configurable. No es una medición
clínica ni un diagnóstico.

## Componentes principales

- `Wellnario/Services/AppleHealth/AppleHealthSyncService.swift`
  - Importa los datos de HealthKit.
  - Agrega los segmentos de sueño.
  - Guarda el histórico bruto en `AppleHealthSnapshot.sleepTrend`.
  - Define `SleepQualityCalculator`, `SleepHeartRateDropCalculator` y las
    preferencias de calidad.
- `Wellnario/Features/Wellness/SleepViewController.swift`
  - Muestra el desglose de la última puntuación disponible.
- `Wellnario/Features/More/SettingsViewController.swift`
  - Permite cambiar la duración objetivo y los pesos de los factores.
- `Wellnario/Widgets/SleepWidgetSnapshotUpdater.swift`
  - Calcula la puntuación efectiva que consume el widget.
- `WellnarioTests/AppleHealthSyncTests.swift`
  - Cubre cálculo, agregación, migración y compatibilidad de caché.

## Flujo de datos

```text
HealthKit: sleepAnalysis + heartRate
              │
              ▼
AppleHealthSleepAggregator
              │  AppleHealthSleepDay (histórico bruto)
              ▼
SleepManualOverrideStore
              │  aplica objetivo, pesos y correcciones manuales
              ▼
SleepQualityCalculator
              │
              ▼
qualityScore 0...100 + SleepQualityBreakdown
```

Durante una sincronización se siguen estos pasos:

1. Se leen los segmentos `sleepAnalysis` autorizados de Apple Health y se
   convierten en sesiones (`AppleHealthSleepSession`).
2. En una sincronización ordinaria se recuperan las muestras de `heartRate` de
   los últimos 35 días, respetando las fuentes que la persona haya desactivado.
   Así el histórico cardíaco completo no forma parte del camino crítico.
3. Las sesiones se agregan por el día local en que terminan para crear
   `AppleHealthSleepDay`.
4. En esa agregación se calcula, cuando hay suficientes lecturas, la caída
   nocturna de frecuencia cardíaca de la sesión principal. Las muestras se
   ordenan una vez y cada sesión localiza su intervalo mediante búsqueda
   binaria, sin recorrer el histórico completo por cada noche.
5. Después de terminar la sincronización visible, una migración reanudable
   completa las caídas cardíacas antiguas en ventanas de 30 días. Cada ventana
   usa una sola consulta de HealthKit, actualiza el histórico y persiste los
   días ya inspeccionados antes de continuar. Esta tarea no mantiene activo el
   indicador de sincronización.
6. El snapshot conserva ese histórico **sin una puntuación fija**. Cada vez
   que se presenta el sueño, `SleepManualOverrideStore` aplica las
   preferencias actuales y recalcula la calidad. Así, cambiar el objetivo o
   los pesos no obliga a volver a consultar HealthKit.

La tendencia efectiva de calidad también se pasa a los factores automáticos
del sueño y al cálculo de estrés, de modo que ambos consumen la misma calidad
que ve la persona en la aplicación.

### Tendencia «Desde el principio»

La sincronización de sueño consulta todas las muestras `sleepAnalysis`
autorizadas y guarda un `AppleHealthSleepDay` bruto por día. Por ello, la
tendencia completa no depende de que la persona haya abierto o seleccionado
previamente cada fecha en la pantalla **Hoy**.

Al elegir «Desde el principio», la aplicación no vuelve a consultar
HealthKit. Parte del histórico guardado, recalcula sus puntuaciones en memoria
y agrupa la visualización por meses o años según la amplitud temporal. Con
unos cientos de días, este trabajo es lineal y pequeño.

Un cambio de ponderaciones sigue el mismo camino local:

```text
preferencias nuevas
        │
        ▼
histórico bruto cacheado
        │  SleepQualityCalculator
        ▼
puntuaciones y tendencia actualizadas
```

La única operación histórica de HealthKit necesaria para esta métrica es la
migración de la caída cardíaca. No se repite al cambiar pesos.

## Construcción de sesiones y días de sueño

### Segmentos de Apple Health

Se aceptan los tipos de sueño `inBed`, `awake`, `asleepUnspecified`, `core`,
`deep` y `REM`. Los segmentos inválidos o de duración no positiva se descartan.

Los segmentos ordenados se separan en sesiones cuando el hueco desde el final
de una agrupación al siguiente segmento es de al menos tres horas. Esto evita
unir una siesta con el sueño principal.

### Agregación diaria

Cada sesión se asigna al día local de `endDate`. Para ese día se acumulan las
horas dormidas, fases y vigilia de todas las sesiones. La **sesión principal**
es la de más segundos dormidos; en empate se elige la que termina más tarde.

La sesión principal aporta:

- `sleepStartDate`: primer tramo no despierto; si no hay fases, inicio de la
  sesión.
- La caída de frecuencia cardíaca.

La vigilia usada en el cálculo se limita a los tramos despiertos situados entre
el primer y el último intervalo dormido. De esta forma no se penaliza el tiempo
en cama antes de quedarse dormido o después de despertarse definitivamente.

`AppleHealthSleepDay` conserva, entre otros, estos campos:

| Campo | Uso |
|---|---|
| `hours` | Duración total dormida del día. Es imprescindible para puntuar. |
| `sleepStartDate` | Regularidad de la hora de acostarse. |
| `awakeHours` y `sleepPeriodHours` | Porcentaje de interrupciones. |
| `heartRateDropPercentage` | Caída nocturna porcentual de la sesión principal. |
| `qualityScore` | Resultado efectivo calculado o corrección manual. |

## Duración objetivo

La duración objetivo puede ser personalizada entre un minuto y 24 horas. Si no
se ha definido una, se toma el punto medio de la recomendación por edad de
`SleepDurationRecommendation`.

| Grupo de edad | Rango de referencia | Objetivo implícito |
|---|---:|---:|
| Recién nacido | 14–17 h | 15,5 h |
| Bebé | 12–15 h | 13,5 h |
| Niño pequeño | 11–14 h | 12,5 h |
| Preescolar | 10–13 h | 11,5 h |
| Escolar | 9–11 h | 10 h |
| Adolescente | 8–10 h | 9 h |
| Adulto joven / adulto | 7–9 h | 8 h |
| Adulto mayor | 7–8 h | 7,5 h |

Si Apple Health no proporciona una fecha de nacimiento válida, se usa el
objetivo adulto de 8 horas.

## Factores de la puntuación

La calidad usa cuatro subpuntuaciones en el intervalo `0...100`.

### 1. Duración

La duración crece linealmente hasta el objetivo y queda limitada a 100:

```text
D = 100 × clamp(horas_dormidas / objetivo_horas, 0, 1)
```

Una noche igual o superior al objetivo obtiene 100 en este factor. Si no hay
duración o el objetivo no es positivo, no se calcula una calidad automática.

### 2. Regularidad

Se toma una ventana de siete días que termina en el día evaluado. Para cada día
con `sleepStartDate` se convierten hora, minuto y segundo a minutos desde las
00:00. La media se calcula de forma circular, por lo que 23:50 y 00:10 se
consideran horarios cercanos, no separados por casi 24 horas.

Un día cumple cuando su distancia circular a esa media es de como máximo 60
minutos. Los días sin sesión no aportan cumplimiento. La puntuación es:

```text
R = 100 × noches_regulares / 7
```

### 3. Interrupciones

Cuando el día contiene `awakeHours`, se calcula el porcentaje de vigilia
dentro del periodo puntuado:

```text
vigilia_% = 100 × awakeHours / sleepPeriodHours
I = 100 × max(0, 1 - vigilia_% / 15)
```

Por tanto, 0 % despierto equivale a 100 y 15 % o más equivale a 0. Si
`awakeHours` no está disponible, `I` queda en 0: los datos desconocidos no se
convierten en una noche sin despertares.

### 4. Caída de frecuencia cardíaca

La caída se calcula solamente con muestras de frecuencia cardíaca de la sesión
principal. Se descartan valores no finitos y los que están fuera de 25–220
latidos por minuto.

1. Se identifica el inicio y final reales del sueño a partir de los intervalos
   no despiertos; si faltan fases se usan los límites de la sesión.
2. Se toma la mediana de las lecturas de la primera hora (`FC_inicial`). Deben
   existir al menos dos muestras.
3. Del resto de la sesión se toma el percentil 20 de las lecturas
   (`FC_baja_estable`). Deben existir al menos cuatro muestras y la lectura que
   cae exactamente en el límite de la primera hora se asigna sólo al primer
   tramo.
4. Se calcula y limita el porcentaje:

```text
caída_% = clamp(100 × (FC_inicial - FC_baja_estable) / FC_inicial, 0, 100)
H = 100 × min(caída_% / 25, 1)
```

Una caída de 25 % o superior obtiene 100 en este factor. Por ejemplo, 15 %
equivale a 60 puntos y 21 % equivale a 84. El umbral es una calibración interna,
no un límite clínico: evita que valores altos diferentes saturen demasiado
pronto. Como contexto, se han publicado descensos nocturnos medios de
aproximadamente 11–13 % en adultos y de 18 ± 6 % en un pequeño grupo de buenos
durmientes, aunque esos estudios comparan periodos distintos a los de
Wellnario.

Si no se cumplen los requisitos de datos, `H` no se calcula; no se infiere a
partir de la frecuencia cardíaca en reposo ni se usa una muestra aislada.

## Pesos y fórmula final

Los pesos son enteros no negativos y deben sumar siempre 100. La configuración
inicial es:

| Factor | Peso predeterminado |
|---|---:|
| Duración | 63 % |
| Regularidad | 9 % |
| Interrupciones | 18 % |
| Caída de FC | 10 % |

La puntuación se obtiene de la media ponderada:

```text
W = D×w_duración + R×w_regularidad + I×w_interrupciones + H×w_caída
Q = clamp(W / peso_efectivo, 0, 100)
```

Si existe `H`, `peso_efectivo = 100`. Si no hay suficientes muestras de
frecuencia cardíaca, se elimina sólo su peso del denominador:

```text
peso_efectivo = 100 - w_caída
```

Así una ausencia de datos cardíacos no rebaja la calidad por sí misma. Con los
pesos predeterminados, el resto se normaliza de forma equivalente a los pesos
históricos 70 % de duración, 10 % de regularidad y 20 % de interrupciones.

El caso límite en que el peso efectivo sea cero devuelve 0, ya que no existe
ningún factor con el que construir una puntuación.

## Preferencias, migración y correcciones manuales

`SleepQualityPreferences` guarda el objetivo y los cuatro pesos en
`UserDefaults`. Los cambios publican
`wellnarioSleepQualityPreferencesDidChange`, por lo que las pantallas y el
widget pueden recalcularse sin sincronización.

Las instalaciones que ya guardaban los tres pesos antiguos se migran al leer
las preferencias: los pesos previos se escalan a 90 % y se reserva 10 % para la
caída de frecuencia cardíaca. La corrección mantiene el total en 100 y evita
que los factores existentes pierdan su proporción relativa.

Las correcciones manuales se guardan por `LocalDay` en
`SleepManualOverrideStore`:

- Una duración manual sustituye `hours` antes de calcular la calidad.
- Una calidad manual válida (0–100) sustituye el `qualityScore` automático
  final para ese día.
- Las correcciones no se escriben de vuelta en Apple Health y sobreviven a una
  nueva sincronización.

## Presentación

La pantalla de sueño muestra la puntuación total y un desglose de duración,
regularidad, interrupciones y caída de frecuencia cardíaca. Las contribuciones
que se muestran se normalizan con el mismo `peso_efectivo` de la fórmula; por
ello suman el total visible. Si la caída cardíaca no está disponible, su fila
explica que faltan lecturas y no muestra una contribución ficticia.

La tarjeta de sueño de **Hoy** también usa el desglose recalculado con las
preferencias actuales, nunca el `qualityScore` que pudiera contener una entrada
cacheada. Al seleccionar un día histórico, la puntuación automática permanece
vacía hasta que termine su actualización de Apple Health; una puntuación
introducida manualmente sí se muestra de inmediato. La tarjeta presenta cinco
anillos compactos: calidad, duración, regularidad, interrupciones y caída de
frecuencia cardíaca. Este último muestra la caída porcentual y rellena el anillo
con su puntuación normalizada.

En **Ajustes → Sueño → Calidad del sueño** se pueden modificar los cuatro
pesos. Al mover uno, los demás se reequilibran proporcionalmente para que el
total siga siendo 100.

## Persistencia, migración histórica y compatibilidad

El snapshot de Apple Health guarda `AppleHealthSleepDay` como `Codable`.
`heartRateDropPercentage` es opcional, por lo que los snapshots de versiones
anteriores se decodifican con el valor `nil`. La siguiente sincronización
reconstruye primero el periodo reciente y conserva los valores históricos que
pertenecen a la versión vigente del algoritmo.

El snapshot guarda además:

- `heartRateDropCalculationVersion`, que invalida resultados si cambia el
  algoritmo;
- `heartRateDropProcessedDays`, que registra tanto los días con resultado como
  aquellos que se consultaron pero no tenían suficientes lecturas.

Tras la sincronización ordinaria, `AppleHealthHeartRateDropBackfill` selecciona
los días pendientes empezando por los más recientes. Los procesa en ventanas
máximas de 30 días, guarda `sleepTrend` y el registro de días después de cada
ventana y notifica a la interfaz para actualizar la gráfica. Si la aplicación
se suspende o se cierra, la próxima sincronización continúa desde el último
bloque persistido. Un día sin suficientes muestras se marca como inspeccionado
y su `heartRateDropPercentage` permanece en `nil`, por lo que no penaliza la
puntuación.

Los factores automáticos reutilizan esas muestras recientes durante las
sincronizaciones incrementales. Sólo una reconstrucción completa de su caché
consulta la ventana histórica de seis meses, y lo hace en paralelo con el resto
de sus consultas.

La calidad se conserva de forma intencionada como derivación de la tendencia
bruta, no como una decisión inmutable de la sincronización. Esto permite que
el histórico se adapte de inmediato a un nuevo objetivo, una nueva ponderación
o una corrección manual, sin alterar los datos originales importados.

## Pruebas relevantes

`AppleHealthSyncTests` cubre al menos:

- cálculo de duración, regularidad e interrupciones;
- cálculo de la caída con mediana inicial y percentil bajo posterior;
- cálculo por lotes limitado a las muestras de cada sesión;
- división del histórico cardíaco en ventanas acotadas, empezando por las más
  recientes;
- selección de la sesión principal durante la migración histórica;
- persistencia de la versión y de los días ya inspeccionados;
- recálculo de una tendencia cacheada de 300 días al cambiar los pesos, sin
  sincronización;
- conservación del valor histórico fuera de la ventana incremental;
- persistencia de la caída en la tendencia de sueño;
- ausencia de penalización cuando faltan lecturas cardíacas;
- migración de preferencias de tres a cuatro pesos;
- decodificación de cachés antiguas;
- presencia del cuarto factor en el desglose de la interfaz.

Las pruebas de navegación verifican también que el control del cuarto peso se
encuentra disponible en Ajustes.
