# Algoritmo de Recuperación (Recovery Score)

Este documento detalla la propuesta técnica para calcular un **Recovery Score** (Puntuación de Recuperación) del 0 al 100, utilizando los datos disponibles en Apple Health. El modelo se inspira en el funcionamiento de algoritmos consolidados como los de Oura Ring, Whoop y Bevel.

## 1. Origen de Datos (Apple HealthKit)

El algoritmo se alimentará principalmente de biomarcadores recogidos durante el **período de sueño nocturno**. Leer datos diurnos contaminaría la métrica con el estrés de la actividad diaria.

1. **HRV (Variabilidad de la Frecuencia Cardíaca)**: `HKQuantityTypeIdentifier.heartRateVariabilitySDNN`.
   - *Nota:* Apple Watch usa SDNN por defecto. Se deben promediar (o calcular la media cuadrática) de las lecturas tomadas exclusivamente mientras el usuario dormía.
2. **RHR (Frecuencia Cardíaca en Reposo)**: `HKQuantityTypeIdentifier.restingHeartRate`.
   - Apple Health calcula automáticamente el RHR diario. Es un indicador vital de la carga cardiovascular y la recuperación del sistema nervioso simpático.
3. **Frecuencia Respiratoria**: `HKQuantityTypeIdentifier.respiratoryRate`.
   - Métrica muy estable. Las desviaciones bruscas suelen indicar enfermedad o sobreesfuerzo agudo.
4. **Calidad/Duración del Sueño**:
   - Cantidad de sueño de la noche anterior comparada con la necesidad basal de sueño (o utilizando nuestro actual motor de Calidad de Sueño).

## 2. Cálculo de la Línea Base (Baseline)

La "recuperación" es un valor relativo al estado normal de la persona. Un HRV de 40ms puede ser un estado de alta recuperación para una persona de 50 años, pero un estado de agotamiento para un atleta joven.

Para cada métrica (HRV y RHR), se calculará una línea base rodante de los **últimos 60 días**:
- **Media Móvil ($ \mu $)**: El promedio de los últimos 60 días.
- **Desviación Estándar ($ \sigma $)**: La variabilidad intrínseca del usuario durante ese período.

*(Para usuarios nuevos, se puede establecer un mínimo de 7 a 14 días para mostrar una recuperación precisa, o aplicar una línea base poblacional adaptada a la edad y género temporalmente).*

## 3. Obtención de Z-Scores Parciales

El *Z-Score* nos indica a cuántas desviaciones estándar está el dato de anoche respecto a lo que es "normal" para el usuario.

- **HRV Z-Score**: $Z_{HRV} = \frac{HRV_{anoche} - \mu_{HRV}}{\sigma_{HRV}}$
  - *(Mayor HRV = Mayor recuperación. Z > 0 es positivo).*
- **RHR Z-Score**: $Z_{RHR} = \frac{\mu_{RHR} - RHR_{anoche}}{\sigma_{RHR}}$
  - *(Menor RHR = Mayor recuperación. Por eso se invierte la resta).*

## 4. Agrupación y Ponderación

Para obtener el puntaje base, combinaremos los factores clave. Una ponderación típica de la industria sería:

- **HRV**: 45% (Es la ventana más directa al Sistema Nervioso Autónomo).
- **RHR**: 35% (Refleja el trabajo cardiovascular residual).
- **Sueño**: 20% (La duración y eficiencia del sueño de anoche).

$$ Z_{combinado} = (Z_{HRV} \times 0.45) + (Z_{RHR} \times 0.35) + (Z_{sueno} \times 0.20) $$

*(Nota: $Z_{sueno}$ se calcularía mapeando la duración del sueño a un z-score empírico, donde dormir las horas habituales = 0, y dormir mucho menos = -1 o -2).*

### Modificadores Absolutos (Penalizaciones)
La **Frecuencia Respiratoria** no se suele incluir en la media ponderada debido a que no varía diariamente de forma lineal. Sin embargo, si la Frecuencia Respiratoria de anoche supera en **+1 respiración/minuto** (o un umbral estadístico de 2 desviaciones estándar) la línea base, se aplicará una **penalización fija** de -15 a -20 puntos a la puntuación final, ya que esto correlaciona de forma casi unívoca con estar cayendo enfermo.

## 5. Conversión a la Escala de 0 a 100

Dado que $ Z_{combinado} $ típicamente caerá en el rango de -2.0 a +2.0, necesitamos mapearlo a un valor de 0 a 100 que sea intuitivo para el usuario. Un valor normal (Z = 0) suele asociarse con estar en el umbral entre "óptimo" y "aceptable" (alrededor de un 66%).

Se propone utilizar una función sigmoide (curva S) ajustada empíricamente:

$$ Puntuacion = \frac{100}{1 + e^{-1.5 \times Z_{combinado} - 0.7}} $$

**Niveles de Interpretación:**
- **Puntuación < 33 (Rojo):** Recuperación insuficiente. El cuerpo está bajo estrés o luchando contra un patógeno. (Equivale a $Z < -1.2$).
- **Puntuación 33 - 66 (Amarillo):** Recuperación moderada. Estado aceptable para actividades rutinarias pero no ideal para esfuerzos máximos. (Equivale a $Z$ entre $-1.2$ y $-0.1$).
- **Puntuación > 66 (Verde):** Óptima recuperación. El sistema nervioso está equilibrado (parasimpático dominante). (Equivale a $Z > -0.1$).

## 6. Consideraciones de Arquitectura para Wellnario

1. **Procesamiento Asíncrono / Caching:** Calcular 60 días de datos para 3 métricas de Apple Health puede ralentizar el inicio de la app. Deberíamos crear una entidad en base de datos (CoreData/SwiftData) llamada `RecoveryBaseline` que cachee la media y la desviación estándar hasta ayer. Así, hoy solo calculamos el dato de anoche y lo sumamos a la línea base cacheada.
2. **Contexto de HRV:** La métrica SDNN de Apple es sensible a las alteraciones arrítmicas (extrasístoles). Idealmente filtraremos los datos atípicos antes de promediar el SDNN de la noche.
