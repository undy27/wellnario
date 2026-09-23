# Implementación técnica de la puntuación de sueño

Este documento describe cómo Wellnario construye las sesiones de sueño a partir
de Apple Health y cómo calcula su **calidad del sueño** en una escala de 0 a
100. Incluye las entradas, las reglas de ausencia de datos, la configuración
de pesos, las correcciones manuales, la caída nocturna de la frecuencia
cardíaca, el estrés medio, la proporción de sueño REM y profundo y la latencia.

La puntuación es un indicador de bienestar configurable. No es una medición
clínica ni un diagnóstico.

## Componentes principales

- `Wellnario/Services/AppleHealth/AppleHealthSyncService.swift`
  - Importa los datos de HealthKit.
  - Agrega los segmentos de sueño.
  - Guarda el histórico bruto en `AppleHealthSnapshot.sleepTrend`.
  - Define `SleepQualityCalculator`, `SleepHeartRateDropCalculator`, el
    cálculo de estrés nocturno y las preferencias de calidad.
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
HealthKit: sleepAnalysis + señales fisiológicas
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
   `AppleHealthSleepDay`. En la sesión principal se deriva la latencia cuando
   un intervalo `inBed` contiene el comienzo del primer tramo dormido.
4. En esa agregación se calcula, cuando hay suficientes lecturas, la caída
   nocturna de frecuencia cardíaca de la sesión principal. Las muestras se
   ordenan una vez y cada sesión localiza su intervalo mediante búsqueda
   binaria, sin recorrer el histórico completo por cada noche.
5. Después de terminar la sincronización visible, una migración reanudable
   completa las caídas cardíacas antiguas en ventanas de 30 días. Cada ventana
   usa una sola consulta de HealthKit, actualiza el histórico y persiste los
   días ya inspeccionados antes de continuar. Esta tarea no mantiene activo el
   indicador de sincronización.
6. Para cada sesión principal con datos fisiológicos suficientes se estiman
   cuatro puntos distribuidos durante la noche. Su media se guarda como
   `averageSleepStressScore`; el trabajo comparte las observaciones y bases
   históricas por fase, por lo que no genera una cronología completa por cada
   muestra ni alarga linealmente la sincronización.
7. El snapshot conserva ese histórico **sin una puntuación fija**. Cada vez
   que se presenta el sueño, `SleepManualOverrideStore` aplica las
   preferencias actuales y recalcula la calidad. Así, cambiar el objetivo o
   los pesos no obliga a volver a consultar HealthKit.

La tendencia efectiva de calidad también se pasa a los factores automáticos
del sueño y al cálculo de estrés, de modo que ambos consumen la misma calidad
que ve la persona en la aplicación.

### Tendencia «Todo el período»

La sincronización de sueño consulta todas las muestras `sleepAnalysis`
autorizadas y guarda un `AppleHealthSleepDay` bruto por día. Por ello, la
tendencia completa no depende de que la persona haya abierto o seleccionado
previamente cada fecha en la pantalla **Hoy**.

El catálogo de fuentes de `sleepAnalysis` también se consulta sin limitarlo a
los últimos meses. Cada fuente se identifica por la combinación del productor
y su nombre, lo que permite presentar por separado, por ejemplo, un Apple
Watch y un iPhone aunque HealthKit les asigne el mismo identificador de app.
Las exclusiones antiguas que estaban guardadas sólo con ese identificador se
expanden a todas las fuentes correspondientes. De este modo, una configuración
que deja Oura como única fuente no vuelve a admitir silenciosamente muestras
históricas de dispositivos que no aparecían en la ventana reciente.

Al elegir «Todo el período», la aplicación no vuelve a consultar
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

La latencia no añade una consulta histórica: se deriva de los segmentos
`sleepAnalysis` que ya se importan. La única operación histórica adicional de
HealthKit es la migración de la caída cardíaca. Ninguna se repite al cambiar
pesos.

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
- `averageSleepStressScore`: estrés fisiológico medio 0–100 de la sesión
  principal, cuando hay suficientes datos para estimarlo.
- `sleepLatencyMinutes`: diferencia entre el inicio del intervalo `inBed`
  coincidente y el primer tramo dormido.

La vigilia usada en el cálculo suma todos los tramos que Apple Health marca como
despierto dentro de cada sesión, incluidos los que aparezcan al principio o al
final. Así, el porcentaje de interrupciones describe exactamente el mismo
intervalo inicio-fin que se muestra al usuario para la sesión.

`AppleHealthSleepDay` conserva, entre otros, estos campos:

| Campo | Uso |
|---|---|
| `hours` | Duración total dormida del día. Es imprescindible para puntuar. |
| `sleepStartDate` | Regularidad de la hora de acostarse. |
| `awakeHours` y `sleepPeriodHours` | Porcentaje de interrupciones: toda la vigilia registrada y la duración combinada de los intervalos inicio-fin de las sesiones. |
| `remHours`, `deepHours` y `lightHours` | Proporción de sueño REM y profundo sobre las fases identificadas. |
| `heartRateDropPercentage` | Caída nocturna porcentual de la sesión principal. |
| `sleepLatencyMinutes` | Minutos hasta dormirse; es opcional si HealthKit no aporta un intervalo `inBed` fiable. |
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

La calidad usa siete subpuntuaciones en el intervalo `0...100`.

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

La puntuación de cada día se obtiene con la distancia circular `d` entre su
hora de inicio y esa media. Los días sin `sleepStartDate` obtienen 0 en este
factor y no contribuyen a la media. La escala es:

```text
R = 100,                          si d ≤ 30 min
R = 100 × (240 - d) / (240 - 30), si 30 min < d < 240 min
R = 0,                            si d ≥ 240 min (4 h)
```

El detalle de la interfaz indica además cuántas noches de la ventana quedaron
dentro de la banda de puntuación máxima (±30 minutos), pero la puntuación del
día es siempre la de su propia hora de inicio frente a la media semanal.

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

Por ejemplo, una sesión mostrada como 00:50–10:15 dura 9 h 25 min; si contiene
1 h 17 min marcada como despierto, el factor usa `77 / 565 × 100 = 13,6 %`.

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

### 5. Estrés medio durante el sueño

Se estima el StressScore fisiológico en cuatro puntos igualmente repartidos
por la sesión principal (12,5 %, 37,5 %, 62,5 % y 87,5 % de su duración). Cada
punto se calibra contra el mismo momento relativo de las noches anteriores y
los valores válidos se promedian. Esto evita comparar el inicio de una noche
con el final de otra y limita el coste de cálculo durante la sincronización.

El valor medio `estrés_%` se limita a `0...100`. La puntuación de calidad baja
linealmente hasta 0 cuando el estrés nocturno medio alcanza 50:

```text
S = 100 × max(0, 1 - estrés_% / 50)
```

Por tanto, 0 % de estrés equivale a 100 puntos, 20 % a 60 puntos, 25 % a 50
puntos y cualquier media de 50 % o superior a 0. El umbral no es clínico: es
una calibración de la escala interna. Una observación nocturna fisiológicamente
normal se sitúa alrededor de 20/100, mientras que 50/100 ya representa una
activación elevada y sostenida respecto a la referencia nocturna personal. De
este modo el peor resultado es alcanzable sin exigir una media nocturna de
100/100, extremadamente improbable.

Si no hay suficientes estimaciones fisiológicas fiables, `S` no se calcula y
su peso se redistribuye entre los demás factores: la ausencia de datos no se
interpreta como estrés alto.

### 6. Porcentaje de sueño REM y profundo

La fase REM y la fase profunda (N3) se suman y se dividen únicamente entre el
sueño con fase identificada. La vigilia y los tramos `asleepUnspecified` no
forman parte del denominador:

```text
sueño_clasificado = REM + profundo + esencial
RP_% = 100 × (REM + profundo) / sueño_clasificado
```

Para evitar porcentajes sesgados por una noche casi sin fases, el sueño
clasificado debe representar al menos el 80 % de la duración dormida total. Si
no alcanza esa cobertura, el factor no se calcula y su peso se redistribuye.

La banda de 35–45 % obtiene la puntuación máxima. Por debajo se asciende
linealmente desde 0; por encima se desciende de forma más gradual hasta 0 al
llegar al 100 %:

```text
P = 100 × RP_% / 35,              si RP_% < 35
P = 100,                            si 35 ≤ RP_% ≤ 45
P = 100 × (100 - RP_%) / 55,     si RP_% > 45
```

El intervalo se basa en las referencias habituales para adultos: REM suele
representar aproximadamente 20–25 % y el sueño profundo 15–25 %
([NCBI](https://www.ncbi.nlm.nih.gov/books/NBK482512/)). Es una referencia de
bienestar; Apple Watch estima las fases mediante sensores y aprendizaje
automático, y no sustituye una polisomnografía
([validación de Apple](https://www.apple.com/health/pdf/Estimating_Sleep_Stages_from_Apple_Watch_Oct_2025.pdf)).

### 7. Latencia del sueño

La latencia `L_min` se calcula solamente para la sesión principal. Se busca el
primer segmento dormido (`asleepUnspecified`, `core`, `deep` o `REM`) y un
segmento `inBed` que contenga ese instante. Si existen varios, se prefiere uno
de la misma fuente que el inicio del sueño. Si esa fuente publica un intervalo
completo y otros intervalos anidados, se toma el que haya comenzado antes, ya
que representa el momento en que el usuario se acostó. Solo cuando falta un
`inBed` de esa fuente se utiliza como respaldo el intervalo de otra fuente que
haya comenzado más tarde, para evitar mezclar las fases de un wearable con una
franja amplia programada en el teléfono:

```text
L_min = (inicio_primer_sueño - inicio_inBed) / 60
```

No se usa el comienzo de la sesión como sustituto: si HealthKit sólo aporta
fases dormidas, hacerlo produciría una latencia ficticia de cero. Apple indica
que la latencia puede derivarse comparando estos intervalos, pero también
advierte de que las muestras de Apple Watch pueden no cubrir el principio o el
final del periodo en cama
([HealthKit](https://developer.apple.com/documentation/healthkit/hkcategoryvaluesleepanalysis)).

La puntuación máxima usa una banda tolerante de 5–20 minutos. Fuera de ella se
interpola linealmente hasta 0 en los extremos de 0 y 60 minutos:

```text
L = 100 × L_min / 5,                 si 0 ≤ L_min < 5
L = 100,                               si 5 ≤ L_min ≤ 20
L = 100 × (60 - L_min) / 40,       si 20 < L_min < 60
L = 0,                                 si L_min ≥ 60
```

Oura usa 15–20 minutos como referencia ideal y señala que menos de 5 minutos
puede indicar cansancio excesivo
([Oura](https://support.ouraring.com/hc/en-us/articles/360057792293-Sleep-Contributors)).
Wellnario amplía la banda máxima hasta 5 minutos para no sobrerreaccionar a la
precisión limitada del inicio `inBed`. Es una calibración de bienestar, no un
criterio diagnóstico.

Si no hay un `inBed` coincidente, `L` no se calcula y su peso se redistribuye.

## Pesos y fórmula final

Los pesos son enteros no negativos y deben sumar siempre 100. La configuración
inicial es:

| Factor | Peso predeterminado |
|---|---:|
| Duración | 46 % |
| Regularidad | 6 % |
| Interrupciones | 14 % |
| Caída de FC | 7 % |
| Estrés durante el sueño | 8 % |
| REM y profundo | 9 % |
| Latencia | 10 % |

La puntuación se obtiene de la media ponderada:

```text
W = D×w_duración + R×w_regularidad + I×w_interrupciones + H×w_caída + S×w_estrés + P×w_REM_profundo + L×w_latencia
Q = clamp(W / peso_efectivo, 0, 100)
```

Si están disponibles `H`, `S`, `P` y `L`, `peso_efectivo = 100`. Si falta cualquiera
de los factores derivados, se elimina únicamente su peso del denominador:

```text
peso_efectivo = 100
    - (w_caída si H no existe)
    - (w_estrés si S no existe)
    - (w_REM_profundo si P no existe)
    - (w_latencia si L no existe)
```

Así una ausencia de datos cardíacos, de estrés, de fases o de tiempo en cama no rebaja la calidad
por sí misma.

El caso límite en que el peso efectivo sea cero devuelve 0, ya que no existe
ningún factor con el que construir una puntuación.

## Preferencias, migración y correcciones manuales

`SleepQualityPreferences` guarda el objetivo y los siete pesos en
`UserDefaults`. Los cambios publican
`wellnarioSleepQualityPreferencesDidChange`, por lo que las pantallas y el
widget pueden recalcularse sin sincronización.

Las instalaciones que ya guardaban seis pesos los escalan a 90 % y reservan
10 % para latencia. Las migraciones desde cinco, cuatro o tres pesos reservan
también los factores derivados que aún no existían. En todos los casos se
mantiene el total en 100 y, salvo el ajuste inevitable por redondeo, la
proporción de los pesos existentes.

Las correcciones manuales se guardan por `LocalDay` en
`SleepManualOverrideStore`:

- Una duración manual sustituye `hours` antes de calcular la calidad.
- Una calidad manual válida (0–100) sustituye el `qualityScore` automático
  final para ese día.
- Las correcciones no se escriben de vuelta en Apple Health y sobreviven a una
  nueva sincronización.

## Presentación

La pantalla de sueño muestra la puntuación total y un desglose de duración,
regularidad, interrupciones, caída de frecuencia cardíaca, estrés durante el
sueño, proporción REM y profunda y latencia. Las contribuciones se normalizan
con el mismo `peso_efectivo` de la fórmula; por ello suman el total visible. Si
falta un factor derivado, su fila explica la ausencia de datos y no muestra una
contribución ficticia.

La gráfica de tendencia ofrece los períodos 7 días, 30 días, 6 meses y todo el
período, además de un quinto segmento con icono de calendario para escoger dos
fechas inclusivas.
Los intervalos personalizados se muestran por días hasta 31 días, por semanas
hasta 183 días, por meses hasta 731 días y por años a partir de esa amplitud.
El filtrado se aplica tanto a los valores dibujados como a la regresión lineal.

La tarjeta de sueño de **Hoy** también usa el desglose recalculado con las
preferencias actuales, nunca el `qualityScore` que pudiera contener una entrada
cacheada. Al seleccionar un día histórico, la puntuación automática permanece
vacía hasta que termine su actualización de Apple Health; una puntuación
introducida manualmente sí se muestra de inmediato. La tarjeta presenta un
anillo para la calidad global y siete filas compactas con barras segmentadas
para duración, regularidad, interrupciones, caída de frecuencia cardíaca y
estrés durante el sueño, REM y profundo y latencia. Los factores derivados
muestran su medida y sus barras representan la puntuación normalizada.

En **Ajustes → Sueño → Calidad del sueño** se pueden modificar los siete
pesos. Al mover uno, los demás se reequilibran proporcionalmente para que el
total siga siendo 100.

## Persistencia, migración histórica y compatibilidad

El snapshot de Apple Health guarda `AppleHealthSleepDay` como `Codable`.
`heartRateDropPercentage`, `averageSleepStressScore` y `sleepLatencyMinutes`
son opcionales, por lo que los snapshots de versiones anteriores se decodifican
con el valor `nil`.
La siguiente sincronización invalida la caché de factores automáticos y
reconstruye hasta seis meses de estimaciones de estrés; las sincronizaciones
posteriores usan una ventana incremental de 35 días.

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

### Objetivos históricos de suplementos

Los factores automáticos de consumo diario y semanal comparan cada noche con
el objetivo que estaba vigente en el día en que comenzó la sesión. Los
objetivos de cada activo se almacenan como períodos inclusivos mediante
`effectiveFrom` y `effectiveThrough`; los días sin objetivo no se clasifican
como incumplimientos y quedan fuera del contraste estadístico.

La ficha del activo permite elegir **Aplicar desde** al guardar un objetivo.
También muestra el historial de períodos: al pulsar uno se cargan su cantidad,
unidad y fecha inicial para poder corregirlo. Guardar en la misma fecha modifica
ese período; escoger una fecha nueva inserta un cambio de objetivo y ajusta
automáticamente el final del período anterior. Esto permite asignar de forma
explícita un objetivo a consumos anteriores sin aplicar retrospectivamente, y
de manera silenciosa, el objetivo actual a todo el historial.

## Pruebas relevantes

`AppleHealthSyncTests` cubre al menos:

- cálculo de duración, regularidad e interrupciones;
- cálculo de la caída con mediana inicial y percentil bajo posterior;
- inversión lineal del estrés medio durante el sueño y ausencia de penalización
  cuando no puede estimarse;
- banda óptima, pendientes y cobertura mínima del porcentaje REM y profundo;
- derivación de latencia sólo con un intervalo `inBed` coincidente, curva de
  puntuación y ausencia de penalización cuando falta;
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
- migración de preferencias desde tres, cuatro, cinco y seis pesos;
- decodificación de cachés antiguas;
- presencia de todos los factores en el desglose de la interfaz.

Las pruebas de navegación verifican también que los controles de todos los pesos
se encuentran disponibles en Ajustes.
