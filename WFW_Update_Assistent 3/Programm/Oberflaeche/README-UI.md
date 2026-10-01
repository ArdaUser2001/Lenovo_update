# WFW Update-Assistent UI

## File overview

- `Theme.xaml` contains all visual tokens: colors, brushes, fonts, spacing, corner radii, type sizes, and layout constants. Change the brand color by editing the single `BrandColor` line.
- `Styles.xaml` contains reusable WPF styles for cards, chips, buttons, check boxes, navigation items, expanders, progress bars, text boxes, and the language selector.
- `../Oberflaeche.xaml` contains layout only. It has no code-behind, no `x:Class`, and no event handlers.
- `../Update-Assistent.ps1` loads `Theme.xaml`, then `Styles.xaml`, then `Oberflaeche.xaml` with `XamlReader`. The dictionaries are added to `Application.Current.Resources` before loading the window because runtime `XamlReader` does not resolve relative pack URIs.

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

The redesign adds these names: `AppTitle`, `AppSubtitle`, `LanguageLabel`, `LanguageSwitch`, `SystemChip`, `ProgressLabel`, `CurrentStatusLabel`, `NextActionLabel`, `StatusIcon`, `ConfirmText`, `HelpText`, and `FooterText`.
