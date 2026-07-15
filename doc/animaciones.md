# Animaciones de pantallas y selectores

## Objetivo

Este documento describe la implementación UIKit de las animaciones de Wellnario para poder reutilizarlas en otros proyectos iOS. Incluye:

- Disolución cruzada entre las pantallas principales de una barra de pestañas personalizada.
- Disolución cruzada al navegar mediante `UINavigationController`.
- Selectores nativos basados en `UISegmentedControl`.
- Cápsula personalizada de la barra inferior, con cambios de tamaño, posición y transparencia.
- Interrupciones, pulsaciones rápidas, respuesta háptica y accesibilidad.

La implementación actual está orientada a iOS 17 o posterior y utiliza UIKit.

## Lenguaje de movimiento

Las animaciones no desplazan las pantallas completas. La pantalla saliente permanece superpuesta a la entrante mientras la primera pierde opacidad y la segunda pasa de opacidad cero a uno. Esto reduce el ruido visual y evita que una navegación frecuente parezca pesada.

Los selectores sí utilizan una transformación espacial breve. La cápsula:

1. Se expande y se vuelve parcialmente transparente.
2. Se estira hasta abarcar el origen y el destino.
3. Se contrae alrededor del nuevo elemento.
4. Recupera su tamaño y opacidad definitivos.

### Parámetros

| Uso | Duración | Curva o muelle |
| --- | ---: | --- |
| Interacción rápida | 0,12 s | `easeInOut` |
| Animación estándar | 0,28 s | `easeInOut` |
| Animación enfatizada | 0,42 s | fotogramas clave cúbicos |
| Cambio de pantalla | 0,75 s | lineal |
| Cambio de pantalla con Reducir movimiento | 0,20 s | lineal |
| Muelle estándar | 0,28 s | amortiguación 0,82; velocidad inicial 0,35 |

La curva lineal de las pantallas es intencionada: mantiene constante la suma visual de ambas opacidades durante la disolución cruzada.

## Infraestructura común de movimiento

Conviene centralizar los tiempos y el tratamiento de Reducir movimiento:

```swift
import UIKit

enum AppMotion {
    static let quick: TimeInterval = 0.12
    static let standard: TimeInterval = 0.28
    static let emphasized: TimeInterval = 0.42
    static let screen: TimeInterval = 0.75

    @MainActor
    static var animationsEnabled: Bool {
        !UIAccessibility.isReduceMotionEnabled
    }

    @MainActor
    static var screenDuration: TimeInterval {
        animationsEnabled ? screen : 0.20
    }

    @MainActor
    static func animate(
        duration: TimeInterval = standard,
        delay: TimeInterval = 0,
        animations: @escaping () -> Void,
        completion: ((Bool) -> Void)? = nil
    ) {
        guard animationsEnabled else {
            UIView.performWithoutAnimation(animations)
            completion?(true)
            return
        }

        UIView.animate(
            withDuration: duration,
            delay: delay,
            options: [
                .curveEaseInOut,
                .allowUserInteraction,
                .beginFromCurrentState
            ],
            animations: animations,
            completion: completion
        )
    }

    @MainActor
    static func spring(
        duration: TimeInterval = standard,
        delay: TimeInterval = 0,
        animations: @escaping () -> Void,
        completion: ((Bool) -> Void)? = nil
    ) {
        guard animationsEnabled else {
            UIView.performWithoutAnimation(animations)
            completion?(true)
            return
        }

        UIView.animate(
            withDuration: duration,
            delay: delay,
            usingSpringWithDamping: 0.82,
            initialSpringVelocity: 0.35,
            options: [.allowUserInteraction, .beginFromCurrentState],
            animations: animations,
            completion: completion
        )
    }
}
```

Las animaciones decorativas y espaciales se eliminan con Reducir movimiento. La transición de pantalla conserva una disolución de 0,20 segundos porque no introduce movimiento espacial y proporciona continuidad visual.

## Transición entre pantallas principales

### Estructura de capas

Durante un cambio de pestaña existen tres capas:

1. La nueva pantalla, ya instalada por `UITabBarController`, comienza con `alpha = 0`.
2. Una captura congelada de la pantalla anterior se coloca sobre ella con `alpha = 1`.
3. La barra inferior personalizada permanece por encima de ambas y sigue respondiendo al tacto.

La captura debe añadirse a una vista estable. No debe añadirse a `outgoingView.superview`, porque `UITabBarController` puede eliminar ese contenedor interno al sustituir la pestaña.

### Motor reutilizable

```swift
import UIKit

@MainActor
enum ScreenTransition {
    static func changeTab(
        in stableContainer: UIView,
        outgoingView: UIView,
        changes: () -> Void,
        incomingView: () -> UIView?,
        completion: @escaping () -> Void
    ) -> UIViewPropertyAnimator? {
        // El marco se calcula antes de que UIKit retire la vista saliente.
        let snapshotFrame = outgoingView.convert(
            outgoingView.bounds,
            to: stableContainer
        )

        guard !snapshotFrame.isEmpty,
              let snapshot = outgoingView.snapshotView(
                  afterScreenUpdates: true
              ) else {
            changes()
            completion()
            return nil
        }

        // Instala de forma síncrona la nueva pestaña.
        changes()
        stableContainer.layoutIfNeeded()

        guard let incoming = incomingView() else {
            completion()
            return nil
        }

        snapshot.frame = snapshotFrame
        snapshot.isUserInteractionEnabled = false
        snapshot.isAccessibilityElement = false
        stableContainer.addSubview(snapshot)

        snapshot.alpha = 1
        snapshot.transform = .identity
        incoming.alpha = 0
        incoming.transform = .identity

        let animator = UIViewPropertyAnimator(
            duration: AppMotion.screenDuration,
            curve: .linear
        ) {
            snapshot.alpha = 0
            incoming.alpha = 1
        }

        animator.addCompletion { _ in
            incoming.alpha = 1
            snapshot.removeFromSuperview()
            completion()
        }

        animator.startAnimation()
        return animator
    }
}
```

`afterScreenUpdates: true` fuerza una captura válida incluso si la vista acaba de aparecer. Es importante realizar la captura antes de cambiar `selectedIndex`.

### Integración en un `UITabBarController`

```swift
@MainActor
final class RootTabController: UITabBarController {
    private let customTabBar = UIView()
    private var activeTransition: UIViewPropertyAnimator?

    func select(index: Int, animated: Bool = true) {
        guard let controllers = viewControllers,
              controllers.indices.contains(index),
              let stableRoot = view else { return }

        finishActiveTransition()

        guard selectedIndex != index else {
            return
        }

        let destination = controllers[index]
        guard let outgoing = selectedViewController?.view else {
            selectedIndex = index
            return
        }

        let changes = {
            self.selectedIndex = index
            self.view.layoutIfNeeded()
            // Reiniciar aquí, si procede, el scroll del destino.
            _ = destination.view
        }

        guard animated else {
            changes()
            return
        }

        activeTransition = ScreenTransition.changeTab(
            in: stableRoot,
            outgoingView: outgoing,
            changes: changes,
            incomingView: { self.selectedViewController?.view },
            completion: { [weak self] in
                self?.activeTransition = nil
            }
        )

        // La captura puede ocupar toda la pantalla; la barra debe quedar encima.
        stableRoot.bringSubviewToFront(customTabBar)
    }

    private func finishActiveTransition() {
        guard let animator = activeTransition else { return }

        if animator.state == .active {
            animator.stopAnimation(false)
            animator.finishAnimation(at: .end)
        }

        activeTransition = nil
    }
}
```

### Interrupciones y pulsaciones rápidas

- Nunca se desactiva `isUserInteractionEnabled` de la barra durante la transición.
- La captura sí es no interactiva, para no interceptar gestos.
- Una pulsación nueva finaliza la transición activa en su estado final y comienza inmediatamente otra.
- Antes de retirar la captura se normaliza `incoming.alpha = 1`.
- `.allowUserInteraction` no es necesario en `UIViewPropertyAnimator`; el bloqueo sólo aparece si la aplicación desactiva explícitamente controles o añade una capa interactiva encima.

Finalizar primero el animador evita acumular capturas, opacidades parciales o terminaciones antiguas.

## Navegación interna con `UINavigationController`

Las transiciones `push` y `pop` utilizan un animador delegado. No hay traslación lateral: ambas vistas ocupan el marco final y sólo cambia su opacidad.

```swift
@MainActor
final class FadeNavigationController:
    UINavigationController,
    UINavigationControllerDelegate {

    override func viewDidLoad() {
        super.viewDidLoad()
        delegate = self
    }

    func navigationController(
        _ navigationController: UINavigationController,
        animationControllerFor operation: UINavigationController.Operation,
        from fromVC: UIViewController,
        to toVC: UIViewController
    ) -> (any UIViewControllerAnimatedTransitioning)? {
        guard operation == .push || operation == .pop else { return nil }
        return FadeNavigationAnimator(operation: operation)
    }
}

@MainActor
private final class FadeNavigationAnimator:
    NSObject,
    UIViewControllerAnimatedTransitioning {

    private let operation: UINavigationController.Operation

    init(operation: UINavigationController.Operation) {
        self.operation = operation
    }

    func transitionDuration(
        using transitionContext: (any UIViewControllerContextTransitioning)?
    ) -> TimeInterval {
        AppMotion.screenDuration
    }

    func animateTransition(
        using transitionContext: any UIViewControllerContextTransitioning
    ) {
        guard let fromView = transitionContext.view(forKey: .from),
              let toView = transitionContext.view(forKey: .to),
              let toController = transitionContext.viewController(forKey: .to)
        else {
            transitionContext.completeTransition(false)
            return
        }

        let container = transitionContext.containerView
        toView.frame = transitionContext.finalFrame(for: toController)

        if operation == .push {
            container.addSubview(toView)
        } else {
            container.insertSubview(toView, belowSubview: fromView)
        }

        fromView.alpha = 1
        toView.alpha = 0
        fromView.transform = .identity
        toView.transform = .identity

        UIView.animate(
            withDuration: transitionDuration(using: transitionContext),
            delay: 0,
            options: [
                .curveLinear,
                .allowAnimatedContent,
                .allowUserInteraction,
                .beginFromCurrentState
            ],
            animations: {
                fromView.alpha = 0
                toView.alpha = 1
            },
            completion: { _ in
                let completed = !transitionContext.transitionWasCancelled
                fromView.alpha = 1
                toView.alpha = 1
                transitionContext.completeTransition(completed)
            }
        )
    }
}
```

Al finalizar se restauran ambas opacidades. Esto es imprescindible porque una vista saliente de un `push` puede volver a utilizarse durante un `pop` posterior.

## Reconstrucción completa de la interfaz

Cuando se sustituye el controlador raíz, por ejemplo al cambiar de idioma o apariencia, puede capturarse la ventana antes de reconstruirla:

```swift
let oldSnapshot = window.snapshotView(afterScreenUpdates: false)
window.rootViewController = newRootController
newRootController.view.layoutIfNeeded()

if let oldSnapshot, AppMotion.animationsEnabled {
    oldSnapshot.frame = window.bounds
    oldSnapshot.isUserInteractionEnabled = false
    window.addSubview(oldSnapshot)

    UIView.animate(
        withDuration: AppMotion.emphasized,
        delay: 0,
        options: [.curveEaseInOut, .beginFromCurrentState],
        animations: {
            oldSnapshot.alpha = 0
            oldSnapshot.transform = CGAffineTransform(
                scaleX: 1.015,
                y: 1.015
            )
        },
        completion: { _ in
            oldSnapshot.removeFromSuperview()
        }
    )
}
```

Este leve escalado sólo se utiliza al reconstruir toda la aplicación. Los cambios habituales de pestaña y las navegaciones internas no mueven ni escalan el contenido.

## Selectores nativos

Los selectores de Sueño y Suplementos son `UISegmentedControl`. UIKit proporciona el desplazamiento y la transformación de la cápsula seleccionada; la aplicación sólo define color, texto y estado.

```swift
func makeSegmentedControl(items: [String]) -> UISegmentedControl {
    let control = UISegmentedControl(items: items)
    control.selectedSegmentIndex = 0
    control.apportionsSegmentWidthsByContent = true
    control.selectedSegmentTintColor = UIColor.systemPink
    control.backgroundColor = UIColor.secondarySystemBackground

    control.setTitleTextAttributes([
        .font: UIFont.systemFont(ofSize: 13, weight: .semibold),
        .foregroundColor: UIColor.secondaryLabel
    ], for: .normal)

    control.setTitleTextAttributes([
        .font: UIFont.systemFont(ofSize: 13, weight: .semibold),
        .foregroundColor: UIColor.white
    ], for: .selected)

    control.addTarget(
        self,
        action: #selector(selectionChanged(_:)),
        for: .valueChanged
    )
    return control
}
```

Consideraciones:

- La animación interactiva es propiedad de UIKit y puede cambiar ligeramente entre versiones de iOS.
- Asignar `selectedSegmentIndex` mediante código no garantiza la misma animación que un toque del usuario.
- Para una animación idéntica en distintos controles o versiones debe utilizarse la cápsula personalizada descrita a continuación.
- Los textos largos necesitan `apportionsSegmentWidthsByContent = true` o un contenedor con desplazamiento horizontal.

## Cápsula personalizada de selección

### Jerarquía

La barra personalizada utiliza:

- Un `UIVisualEffectView` como superficie de cristal.
- Una `selectionPill` detrás de los botones.
- Un `UIStackView` horizontal con botones de igual anchura.
- Una cápsula fucsia no interactiva, con esquinas continuas y sombra suave.

```swift
selectionPill.backgroundColor = accentColor
selectionPill.isUserInteractionEnabled = false
selectionPill.layer.cornerCurve = .continuous
selectionPill.layer.shadowColor = accentColor.cgColor
selectionPill.layer.shadowOpacity = 0.24
selectionPill.layer.shadowRadius = 8
selectionPill.layer.shadowOffset = .zero
```

El `UIStackView` se coloca después de la cápsula para que títulos e iconos queden siempre encima.

### Estado necesario

```swift
private var selectedIndex = 0
private var selectionAnimationGeneration = 0
private var isSelectionAnimationInFlight = false
```

`selectionAnimationGeneration` identifica la animación más reciente. Una terminación antigua no puede corregir el marco de una selección más nueva.

### Cálculo del marco

```swift
private func pillFrame(for index: Int) -> CGRect {
    let button = buttons[index]
    var frame = button.convert(
        button.bounds,
        to: pillContainer
    ).insetBy(dx: 3, dy: 10)

    let title = titles[index] as NSString
    let titleWidth = ceil(title.size(withAttributes: [
        .font: tabFont
    ]).width)

    let requiredWidth = titleWidth + 16
    if requiredWidth > frame.width {
        let centerX = frame.midX
        frame.size.width = requiredWidth
        frame.origin.x = centerX - requiredWidth / 2
    }

    return constrainedPillFrame(frame)
}

private func constrainedPillFrame(_ frame: CGRect) -> CGRect {
    let limits = pillContainer.bounds.insetBy(dx: 4, dy: 4)
    var result = frame

    result.size.width = min(result.width, limits.width)
    result.size.height = min(result.height, limits.height)
    result.origin.x = min(
        max(result.minX, limits.minX),
        limits.maxX - result.width
    )
    result.origin.y = min(
        max(result.minY, limits.minY),
        limits.maxY - result.height
    )

    return result
}
```

Medir el título evita que textos como “Suplementos” salgan de la cápsula. La restricción final impide que una expansión transitoria sobrepase los límites de la barra.

### Animación de cuatro fases

| Fase | Intervalo relativo | Geometría | Opacidad |
| --- | --- | --- | ---: |
| Expansión inicial | 0–0,24 | origen ampliado 8 pt horizontal y 5 pt vertical | 0,44 |
| Puente | 0,24–0,52 | unión de origen y destino, ampliada 8/5 pt | 0,30 |
| Llegada expandida | 0,52–0,78 | destino ampliado 10/5 pt | 0,48 |
| Asentamiento | 0,78–1 | marco exacto de destino | 1,00 |

```swift
private func updatePillFrame(animated: Bool) {
    guard buttons.indices.contains(selectedIndex) else {
        selectionPill.frame = .zero
        return
    }

    let target = pillFrame(for: selectedIndex)
    let settle = {
        self.applyPillFrame(target, alpha: 1)
    }

    guard animated, AppMotion.animationsEnabled else {
        selectionAnimationGeneration += 1
        isSelectionAnimationInFlight = false
        settle()
        return
    }

    selectionAnimationGeneration += 1
    let generation = selectionAnimationGeneration
    isSelectionAnimationInFlight = true

    // Una selección puede comenzar antes de terminar la anterior. Se parte
    // del valor que el usuario ve, no del valor final del modelo.
    let visibleFrame = selectionPill.layer.presentation()?.frame
    let visibleAlpha = selectionPill.layer.presentation().map {
        CGFloat($0.opacity)
    }

    selectionPill.layer.removeAllAnimations()
    selectionPill.frame = visibleFrame ?? selectionPill.frame
    selectionPill.alpha = visibleAlpha ?? selectionPill.alpha

    let start = selectionPill.frame
    let startExpanded = constrainedPillFrame(
        start.insetBy(dx: -8, dy: -5)
    )
    let bridge = constrainedPillFrame(
        start.union(target).insetBy(dx: -8, dy: -5)
    )
    let targetExpanded = constrainedPillFrame(
        target.insetBy(dx: -10, dy: -5)
    )

    UIView.animateKeyframes(
        withDuration: AppMotion.emphasized,
        delay: 0,
        options: [
            .calculationModeCubic,
            .allowUserInteraction,
            .beginFromCurrentState
        ],
        animations: {
            UIView.addKeyframe(
                withRelativeStartTime: 0,
                relativeDuration: 0.24
            ) {
                self.applyPillFrame(startExpanded, alpha: 0.44)
            }

            UIView.addKeyframe(
                withRelativeStartTime: 0.24,
                relativeDuration: 0.28
            ) {
                self.applyPillFrame(bridge, alpha: 0.30)
            }

            UIView.addKeyframe(
                withRelativeStartTime: 0.52,
                relativeDuration: 0.26
            ) {
                self.applyPillFrame(targetExpanded, alpha: 0.48)
            }

            UIView.addKeyframe(
                withRelativeStartTime: 0.78,
                relativeDuration: 0.22
            ) {
                settle()
            }
        },
        completion: { [weak self] _ in
            guard let self else { return }

            Task { @MainActor [weak self] in
                guard let self,
                      self.selectionAnimationGeneration == generation
                else { return }

                self.isSelectionAnimationInFlight = false
                self.updatePillFrame(animated: false)
            }
        }
    )
}

private func applyPillFrame(_ frame: CGRect, alpha: CGFloat) {
    selectionPill.frame = frame
    selectionPill.layer.cornerRadius = frame.height / 2
    selectionPill.alpha = alpha
}
```

### Por qué se consulta la capa de presentación

Core Animation diferencia entre:

- Capa de modelo: contiene el destino final de la animación.
- Capa de presentación: contiene lo que se está mostrando en ese instante.

Si el usuario pulsa otra opción durante la animación y se usa directamente `selectionPill.frame`, la nueva animación comienza en el destino anterior y la cápsula da un salto. Leer `layer.presentation()` antes de eliminar las animaciones permite continuar desde el punto visible.

### Evitar que `layoutSubviews` interfiera

El layout sólo debe corregir el marco de la cápsula cuando no está animándose:

```swift
override func layoutSubviews() {
    super.layoutSubviews()

    stackView.layoutIfNeeded()
    if !isSelectionAnimationInFlight {
        updatePillFrame(animated: false)
    }
}
```

De lo contrario, cada pasada de Auto Layout puede llevar la cápsula directamente al destino y hacer que la animación parezca instantánea.

### Transición de iconos y títulos

El contenido de los botones se actualiza con una disolución más corta que el movimiento de la cápsula:

```swift
UIView.transition(
    with: button,
    duration: AppMotion.standard,
    options: [
        .transitionCrossDissolve,
        .allowAnimatedContent,
        .allowUserInteraction,
        .beginFromCurrentState
    ],
    animations: {
        var configuration = button.configuration
        configuration?.image = selectedImage
        configuration?.baseForegroundColor = isSelected
            ? .white
            : .secondaryLabel
        button.configuration = configuration
    }
)
```

La cápsula tarda 0,42 segundos; el icono y el texto, 0,28. El contenido se estabiliza antes y la cápsula termina el gesto visual.

## Respuesta háptica

La respuesta se genera una sola vez, después de aceptar una selección distinta:

```swift
@objc private func tabTapped(_ sender: UIButton) {
    guard sender.tag != selectedIndex else { return }

    selectedIndex = sender.tag
    UISelectionFeedbackGenerator().selectionChanged()
    onSelection?(selectedIndex)
}
```

No debe generarse háptica desde cada fotograma ni al volver a pulsar la opción ya seleccionada.

## Accesibilidad

- Con Reducir movimiento, la cápsula salta al estado final sin expansión ni desplazamiento.
- Las pantallas mantienen una disolución lineal de 0,20 segundos.
- Con Reducir transparencia, el desenfoque de la barra debe sustituirse por un color sólido.
- La cápsula decorativa no es un elemento de accesibilidad ni recibe eventos táctiles.
- Cada botón expone `.selected` cuando corresponde.
- Los botones deben conservar un área táctil mínima de 44 × 44 puntos.
- La barra permanece interactiva durante cualquier transición.

Ejemplo de rasgos:

```swift
button.accessibilityTraits = isSelected
    ? [.button, .selected]
    : [.button]
```

## Errores frecuentes

### La transición de pestañas no se ve

Causa habitual: la captura se añade a `outgoingView.superview`. UIKit retira ese contenedor durante el cambio y la animación continúa fuera de la jerarquía visible.

Solución: capturar el marco antes del cambio y añadir la captura a la vista raíz estable del controlador de pestañas.

### La barra no responde durante medio segundo

Causa habitual: se desactiva la interacción de la barra hasta la finalización de la animación o la captura intercepta los toques.

Solución: no desactivar la barra, usar una captura no interactiva y finalizar limpiamente el animador anterior cuando llega otra pulsación.

### La cápsula salta al pulsar rápidamente

Causa: la animación nueva parte de la capa de modelo.

Solución: copiar primero `presentation().frame` y `presentation().opacity`, eliminar las animaciones anteriores y comenzar desde esos valores visibles.

### Una animación antigua mueve la cápsula al destino equivocado

Causa: la clausura de finalización de una selección anterior se ejecuta después de una nueva.

Solución: utilizar un contador de generación y aceptar únicamente la terminación más reciente.

### La cápsula se mueve instantáneamente

Causa: `layoutSubviews` recalcula su marco mientras se ejecutan los fotogramas clave.

Solución: proteger el ajuste con `isSelectionAnimationInFlight`.

### El texto sale de la cápsula

Causa: la cápsula utiliza siempre la anchura uniforme del botón.

Solución: medir el título, añadir margen horizontal y restringir el resultado a los límites del contenedor.

## Pruebas recomendadas

### Transiciones de pantalla

- Comprobar que la captura de transición es hija directa del contenedor raíz estable.
- Verificar que la captura se elimina al terminar.
- Cambiar dos veces de pestaña antes de 0,75 segundos.
- Confirmar que la segunda selección se aplica inmediatamente.
- Confirmar que la barra sigue siendo interactiva.
- Probar con Reducir movimiento activado.
- Recorrer todas las pestañas mediante una prueba UI.

### Selectores

- Seleccionar elementos adyacentes y no adyacentes.
- Pulsar tres opciones rápidamente.
- Confirmar que el marco final coincide exactamente con el botón seleccionado.
- Probar títulos largos y tamaños de texto de accesibilidad.
- Cambiar idioma durante la ejecución.
- Verificar que una terminación antigua no altera la selección actual.
- Confirmar que Reducir movimiento elimina los fotogramas clave.

## Lista de adaptación a otro proyecto

1. Copiar o recrear los tokens de duración de `AppMotion`.
2. Usar un color semántico para el acento; no fijar el `CGColor` sin actualizarlo al cambiar la apariencia.
3. Instalar la transición de navegación mediante `UINavigationControllerDelegate`.
4. Colocar las capturas de pestañas en un contenedor raíz estable.
5. Mantener la barra personalizada por encima de las capturas.
6. No bloquear controles durante las animaciones.
7. Implementar lectura de la capa de presentación para animaciones interrumpibles.
8. Añadir contador de generación a las cápsulas con fotogramas clave.
9. Incorporar respuesta háptica sólo al cambiar realmente la selección.
10. Validar Reducir movimiento, Reducir transparencia, VoiceOver y Dynamic Type.

## Archivos de referencia en Wellnario

- `Wellnario/App/RootTabBarController.swift`: coordinación del cambio de pestaña, interrupciones y prioridad visual de la barra.
- `Wellnario/App/WellnarioNavigationController.swift`: transición de navegación y motor de disolución entre pestañas.
- `Wellnario/DesignSystem/FloatingTabBarView.swift`: cápsula personalizada, fotogramas clave, continuidad desde la capa de presentación y háptica.
- `Wellnario/DesignSystem/WellnarioTokens.swift`: duraciones y helpers que respetan Reducir movimiento.
- `Wellnario/Features/Wellness/SleepViewController.swift`: selectores nativos de métrica, período y línea de referencia.
- `Wellnario/Features/Supplements/SupplementsViewController.swift`: selector nativo principal de Suplementos.
- `Wellnario/App/AppCoordinator.swift`: transición al reconstruir completamente el controlador raíz.
