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

### Frecuencia cardíaca en reposo

$begin:math:display$
z\_\{RHR\}\(t\)\=
\\frac\{
RHR\_t\-\\operatorname\{mediana\}\(RHR\)
\}\{
1\.4826\\cdot MAD\(RHR\)
\}
$end:math:display$

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

Como una HRV elevada y una buena calidad del sueño indican menor estrés, sus contribuciones se restan.

$begin:math:display$
S\_t\=
\-0\.45z\_\{HRV\}\(t\)
\+0\.30z\_\{RHR\}\(t\)
\+0\.10z\_\{Resp\}\(t\)
\-0\.15z\_\{Sleep\}\(t\)
$end:math:display$

Los pesos utilizados son:

| Biomarcador | Peso |
|-------------|------|
| HRV | 45% |
| RHR | 30% |
| Respiración | 10% |
| Sueño | 15% |

La suma de los pesos es:

$begin:math:display$
0\.45\+0\.30\+0\.10\+0\.15\=1
$end:math:display$

Interpretación:

- HRV inferior a la habitual → aumenta el estrés.
- RHR superior a la habitual → aumenta el estrés.
- Respiración superior a la habitual → aumenta el estrés.
- Sueño peor de lo habitual → aumenta el estrés.

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
\+0\.30z\_\{RHR\}\(t\)
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
