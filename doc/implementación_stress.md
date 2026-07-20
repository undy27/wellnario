# Implementación técnica de la puntuación de estrés

Este documento describe la implementación actual de la puntuación de estrés
(`StressScore`) de Wellnario. La especificación matemática de referencia está
en [`propuesta_stress.md`](propuesta_stress.md); aquí se documentan además el
flujo de datos, las decisiones de integración con Apple Health, la persistencia
y la presentación en la interfaz.

## Alcance

La puntuación es un índice fisiológico personal de 0 a 100. Se calibra contra
el historial reciente de la propia persona, por lo que no es una medición
clínica ni debe interpretarse como diagnóstico. Un valor alto significa mayor
estrés relativo a la línea base personal.

La implementación principal está en:

- `Wellnario/Services/AppleHealth/AppleHealthSyncService.swift`: modelos,
  consultas HealthKit, cálculo y construcción del snapshot.
- `Wellnario/Features/Today/TodayViewController.swift`: tarjeta de estrés y
  pantalla de desglose (`StressDetailsViewController`).
- `Wellnario/Features/Wellness/SleepFactorModels.swift`: definición del factor
  automático `automatic.preSleepStress`.
- `WellnarioTests/AppleHealthSyncTests.swift`: pruebas del cálculo y de la
  alineación temporal de las muestras.

## Flujo de datos

1. Al sincronizar Apple Health, `AppleHealthSyncService` solicita las lecturas
   autorizadas y obtiene las sesiones de sueño desde el primer día necesario
   para construir el historial.
2. `fetchAutomaticSleepFactorHistory` consulta las muestras fisiológicas y los
   entrenamientos, y las entrega a `AppleHealthAutomaticSleepFactorBuilder`.
3. El builder crea una observación por sesión de sueño, usando como instante
   de referencia la hora de inicio de la sesión.
4. `AppleHealthStressScoreCalculator.details` calcula el desglose completo y
   el score. `scores` es sólo una vista reducida que devuelve las puntuaciones
   existentes.
5. El resultado se guarda en `AppleHealthSnapshot.automaticSleepFactors` y se
   serializa en la caché local del snapshot de Apple Health.
6. La tarjeta **Estrés** de Hoy muestra el último score disponible. Al pulsarla
   se abre `StressDetailsViewController`, que presenta los valores de entrada,
   referencias estadísticas, contribuciones y el índice compuesto.

## Fuentes y unidades

| Factor | Fuente | Unidad interna | Selección temporal |
|---|---|---:|---|
| Variabilidad de la frecuencia cardíaca (HRV/SDNN) | `heartRateVariabilitySDNN` | ms | última muestra cuyo fin es anterior al inicio del sueño |
| Frecuencia cardíaca en reposo (RHR) | `restingHeartRate` | latidos/min | misma regla |
| Frecuencia respiratoria | `respiratoryRate` | respiraciones/min | misma regla |
| Calidad del sueño | tendencia de sueño de Wellnario | puntuación 0–100 | calidad de la última sesión completada |
| Actividad previa | entrenamientos de HealthKit | booleano | cualquier entrenamiento que se solape con las 2 h previas |

Para HRV, RHR y respiración se usa `latestQuantity`: la muestra más reciente
que termina antes de acostarse y que no tiene más de 36 horas. No se fabrica un
valor cuando falta una lectura. La calidad no usa la sesión que acaba de
comenzar: se asocia la calidad de la sesión anterior ya terminada. Esa calidad
puede proceder de Apple Health o de una sobreescritura manual de sueño en
Wellnario.

Las autorizaciones se declaran en `authorizationReadTypes`, incluyendo HRV,
frecuencia cardíaca en reposo, frecuencia respiratoria, sueño y entrenamientos.
El filtro de fuentes de Apple Health se aplica antes de construir estas
observaciones, por lo que las fuentes deshabilitadas no entran en el cálculo.

## Ventanas y fechas

- Cada observación está indexada por `session.startDate` para que los datos
  fisiológicos correspondan al momento previo a acostarse.
- La fecha del factor de sueño es el día de finalización de la sesión. El
  objeto de desglose conserva además la fecha de inicio (`details.date`), que
  es el instante usado para asociar las medidas fisiológicas.
- La línea base de una observación contiene los días desde `t - 28 días` hasta
  el comienzo del día de `t`, excluyendo siempre el día actual. Se calcula con
  el calendario y la zona horaria recibidos por el builder.
- Cada biomarcador debe contener al menos 7 muestras históricas para obtener un
  `z-score` estable (`minimumHistoricalSamples = 7`). Las muestras con el
  biomarcador ausente no se sustituyen y no cuentan para ese biomarcador.

## Ajuste por actividad y normalización robusta

### Ajuste de HRV

Si existe un entrenamiento en las dos horas anteriores al inicio de la sesión,
la HRV observada se sustituye únicamente para este cálculo por la **media de
las HRV disponibles en la ventana previa de 28 días**. El valor original se
conserva en el desglose y se muestra el valor ajustado cuando ambos difieren.

Esto evita que una bajada transitoria de HRV inmediatamente después del
ejercicio se interprete como estrés. No se modifica el dato guardado en Apple
Health.

### `z-score` robusto por biomarcador

Para cada variable `X` se calcula:

```text
mediana = mediana(historial de X)
MAD     = mediana(|X_i - mediana|)
escala  = 1.4826 * MAD
z       = (X_actual - mediana) / escala
```

El `z` se limita al intervalo `[-3, 3]`. Si no hay mediana, hay menos de 7
muestras históricas o la escala es prácticamente cero (`<= 0.000001`), el
`z-score` y la contribución de ese factor quedan sin valor.

El factor `1.4826` hace comparable el MAD con la desviación típica bajo una
distribución aproximadamente normal, pero conserva la robustez frente a
valores extremos.

## Índice compuesto y score final

Cuando están disponibles las cuatro contribuciones se calcula el índice
fisiológico:

```text
S = -0.45 * z_HRV
  + 0.30 * z_RHR
  + 0.10 * z_Resp
  - 0.15 * z_Sleep
```

Los signos reflejan la interpretación fisiológica del modelo:

- HRV más baja de lo habitual aumenta el estrés.
- RHR y frecuencia respiratoria más altas de lo habitual aumentan el estrés.
- Una calidad de sueño más baja aumenta el estrés.

El propio índice `S` se normaliza contra los índices compuestos anteriores que
caen en su ventana de 28 días, usando la misma mediana/MAD. El resultado
normalizado `S*` se convierte a la escala de usuario mediante:

```text
StressScore = 100 / (1 + exp(-1.4 * S*))
```

El resultado se limita finalmente a `0...100`. Si falta cualquiera de los
cuatro factores, no se presenta una puntuación parcial; sí se conserva el
desglose para explicar qué dato o qué historial falta.

## Niveles mostrados al usuario

`levelLocalizationKey(for:)` clasifica la puntuación así:

| Intervalo | Nivel |
|---:|---|
| 0–24 | Muy bajo |
| 25–39 | Bajo |
| 40–59 | Normal |
| 60–74 | Elevado |
| 75–89 | Alto |
| 90–100 | Muy alto |

Los textos se localizan mediante las claves `apple_health.stress.level.*`.

## Persistencia y compatibilidad

`AppleHealthAutomaticSleepFactors` conserva:

- `preSleepStressScore`: valor 0–100, si se pudo calcular.
- `preSleepStressDetails`: desglose completo de la sesión.

El desglose es opcional y tiene valor predeterminado `nil`. Esto permite
decodificar snapshots creados por versiones anteriores, que sólo guardaban el
score. En ese caso, la tarjeta puede mostrar el valor histórico, pero la
pantalla de detalle informa de que hay que volver a sincronizar para obtener el
desglose.

`AppleHealthStressCalculationDetails` guarda la fecha, los cuatro objetos
`AppleHealthStressMetricDetails`, el indicador de actividad, el índice
compuesto, sus estadísticas de referencia, su `z-score` y el score final.
Cada métrica conserva el valor original, el valor ajustado, mediana, MAD,
número de muestras, peso, `z-score` y contribución.

## Pantalla de desglose

La pantalla se identifica como `today.stress.details` y se compone de tres
tarjetas:

1. **Estado actual**: score, nivel y fecha.
2. **Entradas**: HRV, RHR, respiración y calidad; muestra unidades, valor
   ajustado por actividad cuando procede, mediana/MAD, muestras históricas,
   `z-score`, contribución y peso.
3. **Método**: ventana de 28 días, mínimo de 7 muestras, fórmula, índice
   compuesto, referencia del índice, `z-score` compuesto y ajuste por
   actividad.

Cuando no hay score se muestra `—` y el motivo (datos ausentes o historial
insuficiente). La pantalla no intenta rellenar valores ni recalcular datos
históricos en el dispositivo: el cálculo se rehace durante la siguiente
sincronización.

## Casos límite y mantenimiento

- Una fuente HealthKit deshabilitada puede dejar una métrica sin muestras; el
  score queda deliberadamente sin calcular hasta que exista información
  suficiente.
- Un MAD igual a cero no se fuerza a un valor artificial; evita divisiones
  inestables y deja el factor fuera de la puntuación.
- El historial puede obtener lecturas fisiológicas fuera de la hora previa a
  acostarse: se usa la última muestra retrospectiva dentro de 36 horas, sin
  inventar una lectura.
- Si se cambian pesos, ventanas, umbrales o la constante logística, hay que
  actualizar el texto de fórmula de la pantalla, esta documentación y las
  pruebas del calculador.
- Las pruebas relevantes son
  `testStressScoreUsesRobustBaselinesAndActivityAdjustedHRV` y
  `testStressScoreUsesRetrospectiveHealthSamplesOutsideThePreBedHour`, además
  de las pruebas del builder que verifican la asociación con la noche
  siguiente.
