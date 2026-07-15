# Wellnario UIKit Design System

All components are programmatic UIKit and target iOS 17. They use semantic
colors, Dynamic Type and continuous corner curves. Feature controllers should
not duplicate literal colors, font sizes or spacing values.

## Tokens and layout

- `WellnarioPalette`: semantic surfaces, text, signature gradient and status
  colors.
- `WellnarioTypography.font(for:)` and `UILabel.applyWellnarioStyle`: scaled
  typography.
- `WellnarioSpacing`, `WellnarioRadius`, `WellnarioLayout`: shared geometry.
- `WellnarioMotion.animate` / `.spring`: animations that honor Reduce Motion.
- `UIView.addForAutoLayout`, `.pinEdges` and `.applyContinuousCorners`: layout
  helpers.

## Core components

```swift
let card = PremiumCardView()
card.isPressable = true
card.contentView.addForAutoLayout(content)
content.pinEdges(to: card.contentView, insets: .all(WellnarioSpacing.cardPadding))

let action = PrimaryButton(title: L10n.Today.logIntake)
let period = ChipButton(title: L10n.Trends.sevenDays)
period.isSelected = true

let field = FormFieldView()
field.configure(title: L10n.Form.activeAmount, keyboardType: .decimalPad)
field.unitTitle = "mg"
field.setError(nil)
```

- `PresentationArtworkView(kind:)` draws capsule, tablet, powder, liquid,
  gummy and sachet placeholders offline with Core Graphics.
- `MetricCardView` accepts any compact visualization through
  `setVisualization(_:)`; `SparklineView`, `TargetProgressView` and
  `SegmentedProgressView` cover the dashboard use cases.
- `EmptyStateView`, `SkeletonView`, `InlineLoadingView` and
  `FeedbackBannerView` cover empty, loading and feedback states.
- `FeedbackPresenter.show` returns the presented banner. Call
  `FeedbackPresenter.dismiss` when the feature's desired timeout or undo
  window ends.
- `FloatingTabBarView` defaults to Wellnario's five tabs and reports selection
  through `onSelection`. Its titles refresh after a runtime language change.

## Runtime localization

```swift
LocalizationManager.shared.setLanguage(.english)
let title = L10n.Supplements.title
let custom = L10n.text("today.progress.format", completed, total)
```

The choice is persisted. `LocalizationManager.didChangeNotification` is sent
on the main actor so feature controllers can update existing visible copy.
`LocalizedLabel` and `LocalizedButton` observe it automatically.
`WellnarioFormatters` supplies locale-aware dates, times, decimals, currency,
percentages and expiry descriptions.

## Accessibility contract

- Never encode a status with color alone; use a label and an icon.
- Keep controls at least 44×44 pt and allow labels to wrap.
- Metric cards should expose one concise VoiceOver summary; charts should also
  have a text/table alternative in their feature screen.
- Collapse two-column dashboard layouts into one column for accessibility text
  categories.
- Use `WellnarioMotion` rather than direct animations and keep glass effects
  behind components that provide an opaque Reduce Transparency fallback.
