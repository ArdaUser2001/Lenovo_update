# WFW Update-Assistent UI

## File overview

- `Theme.xaml` contains all visual tokens: colors, brushes, fonts, spacing, corner radii, type sizes, and layout constants. Change the brand color by editing the single `BrandColor` line.
- `Styles.xaml` contains reusable WPF styles for cards, chips, buttons, check boxes, navigation items, expanders, progress bars, text boxes, and the language selector.
- `../Oberflaeche.xaml` contains layout only. It has no code-behind, no `x:Class`, and no event handlers.
- `../Update-Assistent.ps1` loads `Icons.xaml`, then `Theme.xaml`, then `Styles.xaml`, then `Oberflaeche.xaml` with `XamlReader`. The dictionaries are added to `Application.Current.Resources` before loading the window because runtime `XamlReader` does not resolve relative pack URIs.

## Change colors, fonts, or spacing

- Colors: edit `Theme.xaml`. Keep hard-coded color values there only.
- Brand color: edit `BrandColor` in `Theme.xaml`.
- Fonts: edit `AppFontFamily`, `DisplayFontFamily`, or `IconFontFamily` in `Theme.xaml`.
- Spacing, corner radius, or type scale: edit the named resources in `Theme.xaml`.

## Add a step

1. Add the German and English step objects in the `$script:StepsByLanguage` data structure in `Update-Assistent.ps1`.
2. Keep the same action `Id` values if the existing logic should run.
3. Add any new action `Id` to `Invoke-StepAction`.
4. Update progress maximums and copy that currently mention 8 steps.
5. No XAML layout change is required.

## Add a button style

1. Add the visual tokens you need to `Theme.xaml`.
2. Add a named style to `Styles.xaml`, based on `ButtonBase` when possible.
3. Apply it from PowerShell with `$script:Window.FindResource('NewStyleName')`.

## XAML names

The script depends on these existing names: `Logo`, `Navigation`, `ProgressText`, `OverallProgress`, `SectionCounter`, `StepTitle`, `StepMode`, `StepText`, `Actions`, `Status`, `BusyBar`, `CancelRestart`, `Confirm`, `Details`, `DetailText`, `Back`, `Next`, `Report`, and `Guide`.

The redesign adds these names: `AppTitle`, `AppSubtitle`, `LanguageLabel`, `LanguageSwitch`, `ProgressLabel`, `CurrentStatusLabel`, `NextActionLabel`, `StatusIcon`, `ConfirmText`, `HelpText`, and `FooterText`.

## Guided wizard layout

The active step starts with `StepIntro`, a concise instruction from `StepIntro1` through `StepIntro8` in the language dictionaries. `Instructions` reveals the original full `StepText`. Keep restart and firmware precautions in the introduction as well as the detailed copy.

`Actions` holds the primary action. `AdditionalActions`, inside `Alternatives`, holds secondary actions; the program scan/install pair stays visible together. Both action containers are disabled during worker activity. Step changes collapse instructions, alternatives and logs; status refreshes and language changes preserve their expansion state.

The footer contains only Back and Next. `Support` groups the PDF guide, usage help, IT report and window-switching guidance. Continuing leaves an unconfirmed step open; the existing completion and update logic remains unchanged.

The macOS preview mirrors this layout. Run `python3 preview/build.py` from the repository root after editing the wizard introductions or shared copy.

## Icons and wordmark

`Icons.xaml` contains 24-unit outline geometries shared by WPF and the browser preview. `Get-ActionIconKey` maps stable action IDs to icons; `New-IconButtonContent` binds icon and label colors to the button foreground. Update the corresponding `actionIcons` map in the preview when adding action IDs. The original WFW logo is preserved and displayed in a larger, white, borderless area with high-quality bitmap scaling.

The Windows validation script parses the launcher preflight and loads all three resource dictionaries, checking icon and navigation-width types without running updates.

## Windows badge rendering

Step circles always show their number in the explicit `StepNumberText` style (Segoe UI); status remains in the adjacent caption. Do not use the symbol font for digits. Mode/platform labels use `ChipText`, with natural line measurement and wrapping. `RadiusPill` is a WPF radius of 16 device-independent pixels, not the CSS convention of 999px.

## Compact window bars

The header keeps the logo at 216 × 78 while reducing vertical padding to 6. The title is 22 px, and the language label sits beside the 32 px selector. The Windows edition badge is removed. Footer padding is 8 px vertically; Back/Next keep 44 px targets and the credits use a compact second line. Main action buttons retain their existing sizes.
