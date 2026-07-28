# Cálculo del StressScore

La fórmula propuesta utiliza una **normalización robusta individual por biomarcador** y una **segunda normalización robusta del índice compuesto**, antes de transformarlo a una escala de 0 a 100 mediante una función logística.

---

# 1. Ajuste de la HRV por actividad física

Sea $begin:math:text$A\_t$end:math:text$ una variable que indica si existe actividad física registrada durante las dos horas anteriores al cálculo.

$begin:math:display$
A\_t\=
\\begin\{cases\}
1\, \& \\text\{si hubo actividad física en \}\[t\-2h\,t\] \\\\
0\, \& \\text\{en caso contrario\}
\\end\{cases\}
$end:math:display$

La HRV utilizada será:

$begin:math:display$
HRV\_t\^\*\=
\\begin\{cases\}
\\overline\{HRV\}\_\{28d\}\, \& A\_t\=1\\\\
HRV\_t\, \& A\_t\=0
\\end\{cases\}
$end:math:display$

donde:

$begin:math:display$
\\overline\{HRV\}\_\{28d\}
\=
\\frac1N\\sum\_\{i\=1\}\^\{N\}HRV\_i
$end:math:display$

es la media de la HRV de los últimos 28 días (excluyendo el día actual).

---

# 2. Normalización robusta de cada biomarcador

Para cada variable $begin:math:text$X$end:math:text$:

$begin:math:display$
z\_X\(t\)\=
\\frac\{
X\_t\-\\operatorname\{mediana\}\(X\)
\}\{
1\.4826\\cdot MAD\(X\)
\}
$end:math:display$

donde

$begin:math:display$
MAD\(X\)\=
\\operatorname\{mediana\}
\\left\(
\|X\_i\-\\operatorname\{mediana\}\(X\)\|
\\right\)
$end:math:display$

El factor **1.4826** hace que el MAD sea aproximadamente equivalente a la desviación típica cuando los datos siguen una distribución normal.

Se calculan los siguientes valores:

### HRV

$begin:math:display$
z\_\{HRV\}\(t\)\=
\\frac\{
HRV\_t\^\*\-\\operatorname\{mediana\}\(HRV\)
\}\{
1\.4826\\cdot MAD\(HRV\)
\}
$end:math:display$

### Frecuencia cardíaca

La frecuencia cardíaca instantánea y la frecuencia cardíaca en reposo no se
mezclan en una misma línea base. Si hay una FC suficientemente reciente, se
normaliza contra el historial de FC equivalentes:

$begin:math:display$
z\_\{FC\}\(t\)\=
\\frac\{
FC\_t\-\\operatorname\{mediana\}\(FC\)
\}\{
1\.4826\\cdot MAD\(FC\)
\}
$end:math:display$

Cuando no hay una FC reciente se usa el RHR, normalizado únicamente contra el
historial de RHR con la misma fórmula.

### Frecuencia respiratoria

$begin:math:display$
z\_\{Resp\}\(t\)\=
\\frac\{
Resp\_t\-\\operatorname\{mediana\}\(Resp\)
\}\{
1\.4826\\cdot MAD\(Resp\)
\}
$end:math:display$

### Calidad del sueño

$begin:math:display$
z\_\{Sleep\}\(t\)\=
\\frac\{
Sleep\_t\-\\operatorname\{mediana\}\(Sleep\)
\}\{
1\.4826\\cdot MAD\(Sleep\)
\}
$end:math:display$

> Se asume que **Sleep** es una puntuación donde valores mayores representan un mejor descanso.

---

# 3. Índice fisiológico de estrés

El núcleo obligatorio del estrés está compuesto por la HRV y una señal
cardíaca: FC reciente o, en su ausencia, RHR. Cada señal se normaliza
exclusivamente contra su propio historial. La respiración y el sueño actúan
como **factores opcionales**:

$begin:math:display$
S\_t = -0.45 z_{\{HRV\}}(t) + 0.30 z_{\{FC/RHR\}}(t) + 0.10 z_{\{Resp\}}(t)^* - 0.15 z_{\{Sleep\}}(t)^*
$end:math:display$

*(donde los términos marcados con * se suman únicamente si están disponibles en la lectura).*

Los pesos utilizados son:

| Biomarcador | Peso | Carácter |
|-------------|------|----------|
| HRV | 45% | Obligatorio |
| FC reciente o RHR | 30% | Obligatorio |
| Respiración | 10% | Opcional |
| Sueño | 15% | Opcional |

Interpretación:

- HRV inferior a la habitual → aumenta el estrés.
- FC o RHR superior a su propia línea base → aumenta el estrés.
- Respiración superior a la habitual → aumenta el estrés.
- Sueño peor de lo habitual → aumenta el estrés.

## Contexto durante el sueño

Una observación dentro del sueño no debe compararse con la línea base previa a
acostarse. Para una lectura tomada en la fracción \(p\) de la sesión actual se
construye un historial con lecturas tomadas en la misma fracción \(p\) de las
sesiones anteriores:

$begin:math:display$
t_{i,p} = inicio_i + p \cdot (fin_i - inicio_i)
$end:math:display$

Los biomarcadores y los índices compuestos nocturnos se normalizan únicamente
contra esas observaciones equivalentes. Cuando la noche ya ha finalizado, se
utiliza su propia calidad de sueño; durante una sesión todavía abierta, ese
factor permanece ausente hasta que pueda calcularse.

Como \(S_t\) ya combina biomarcadores estandarizados en el mismo contexto
nocturno, durante el sueño no se aplica la segunda normalización del apartado
siguiente. Esa segunda capa magnifica diferencias pequeñas entre noches. El
índice nocturno se transforma directamente con un intercepto contextual:

$begin:math:display$
StressScore_{sueño} =
\frac{100}{
1 + \exp\left(-\left[\ln(20/80) + 1.4S_t\right]\right)
}
$end:math:display$

Así, una observación típica de sueño (\(S_t = 0\)) equivale a 20 puntos. Una
combinación de HRV baja, FC alta y mala calidad sigue elevando el resultado
hacia la parte alta de la escala.

---

# 4. Normalización robusta del índice compuesto

El índice compuesto también se normaliza respecto a su propio historial:

$begin:math:display$
S\_t\^\*\=
\\frac\{
S\_t\-\\operatorname\{mediana\}\(S\)
\}\{
1\.4826\\cdot MAD\(S\)
\}
$end:math:display$

De esta forma, el resultado se adapta automáticamente a cada usuario.

---

# 5. Conversión a StressScore

Finalmente se aplica una función logística:

$begin:math:display$
StressScore\_t\=
\\frac\{
100
\}\{
1\+\\exp\(\-1\.4S\_t\^\*\)
\}
$end:math:display$

Sustituyendo $begin:math:text$S\_t\^\*$end:math:text$:

$begin:math:display$
StressScore\_t\=
\\frac\{
100
\}\{
1\+
\\exp
\\left\(
\-1\.4
\\frac\{
S\_t\-\\operatorname\{mediana\}\(S\)
\}\{
1\.4826\\cdot MAD\(S\)
\}
\\right\)
\}
$end:math:display$

---

# Fórmula completa

$begin:math:display$
\\boxed\{
StressScore\_t\=
\\frac\{
100
\}\{
1\+
\\exp
\\left\(
\-1\.4
\\frac\{
\\left\[
\-0\.45z\_\{HRV\}\(t\)
\+0\.30z\_\{FC/RHR\}\(t\)
\+0\.10z\_\{Resp\}\(t\)
\-0\.15z\_\{Sleep\}\(t\)
\\right\]
\-\\operatorname\{mediana\}\(S\)
\}\{
1\.4826\\cdot MAD\(S\)
\}
\\right\)
\}
\}
$end:math:display$

donde

$begin:math:display$
z\_X\(t\)\=
\\frac\{
X\_t\-\\operatorname\{mediana\}\(X\)
\}\{
1\.4826\\cdot MAD\(X\)
\}
$end:math:display$

y

$begin:math:display$
HRV\_t\^\*\=
\\begin\{cases\}
\\overline\{HRV\}\_\{28d\}\, \& \\text\{si hubo actividad física en las últimas 2 horas\}\\\\
HRV\_t\, \& \\text\{en caso contrario\}
\\end\{cases\}
$end:math:display$

---

# Interpretación

| Índice normalizado $begin:math:text$S\_t\^\*$end:math:text$ | StressScore |
|------------------------------:|------------:|
| -2 | 8 |
| -1 | 23 |
| 0 | 50 |
| 1 | 77 |
| 2 | 92 |

---

# Clasificación sugerida

| StressScore | Nivel |
|-------------|-------|
| 0–24 | Muy bajo |
| 25–39 | Bajo |
| 40–59 | Normal |
| 60–74 | Elevado |
| 75–89 | Alto |
| 90–100 | Muy alto |

---

# Protección frente a valores atípicos

Para evitar que un error puntual del wearable produzca un resultado extremo, es recomendable limitar cada z-score al intervalo:

$begin:math:display$
\[\-3\,\\\;3\]
$end:math:display$

es decir,

$begin:math:display$
z\_X\^\{clip\}
\=
\\max\(\-3\,\\min\(3\,z\_X\)\)
$end:math:display$

Este valor truncado sería el utilizado posteriormente para calcular el índice $begin:math:text$S\_t$end:math:text$.

Si `MAD(X)` es cero, un valor igual a la mediana se considera neutral. Si
difiere, no se calcula el `z-score`: sin dispersión histórica no hay una escala
válida y no debe saturarse automáticamente a `±3`.
