# WFW Update-Assistent UI

## Resources and loading

- `Icons.xaml` contains 24-unit outline geometries shared with the browser preview.
- `Theme.xaml` contains colors, fonts, spacing and dimensions. Change `BrandColor` to change the brand color.
- `Styles.xaml` contains reusable WPF control styles.
- `../Oberflaeche.xaml` contains the window layout and named controls, without code-behind.
- `../Update-Assistent.ps1` loads icons, theme, styles and then the window. Resources are merged into the application before loading the layout because runtime `XamlReader` does not resolve relative pack URIs.

## Full-width task screens

The header keeps the original logo at 216 × 78 and the language selector. The application name remains in the native window title.

Each task uses the full workspace width. `StepIntro` supplies concise guidance, followed by the main actions, one status panel and manual confirmation when applicable. `Instructions` reveals the complete `StepText`; `Alternatives` holds secondary actions. Technical details and support are collapsed by default. Author/version information lives inside `Support`.

The footer contains Back, `StepOverview` and Next. Its progress area distinguishes the selected step (`SectionCounter`) from actual completion (`ProgressText` and `OverallProgress`). A popup contains the existing `Navigation` list and its per-step status labels. Opening the list or moving to another step does not mark any step complete.

On step changes, `ContentScroll` returns to the top and instructions, alternatives, technical details and the overview close. Results remain in the session arrays. Language changes and status refreshes preserve expanded instruction state. Background work closes and disables the step overview together with other navigation. Escape dismisses the overview.

## Editing steps and actions

1. Update German and English entries in `$script:StepsByLanguage` and the `StepIntro1` through `StepIntro8` UI labels.
2. Keep step order and action IDs identical across languages. Existing IDs route through `Invoke-StepAction`.
3. Keep essential restart and firmware precautions visible in the short introductions.
4. If changing the number of steps, update completion counters and progress maximums as well.

`Actions` holds the primary action; the program scan/install pair stays visible together. Other actions go into `AdditionalActions`. Both containers are disabled while workers run.

## Icons, logo and typography

`Get-ActionIconKey` selects action icons; `New-IconButtonContent` binds both icon and label colors to the owning button. Keep the preview's `actionIcons` map aligned when adding actions. The official WFW wordmark is preserved, with high-quality bitmap scaling in a borderless white area.

Step circles use the explicit `StepNumberText` style with Segoe UI. Symbol fonts must not be used for digits. The reusable `ChipText` style uses natural line measurement. `RadiusPill` is a WPF radius of 16 device-independent pixels, not CSS's 999px convention. Grid column width resources must be `GridLength`, not `Double`.

## Validation and preview

The Windows validation script parses the launcher and PowerShell files, loads the WPF resources/window without starting updates, and checks geometry types, badge sizing and the full-width layout at minimum/default sizes. Native interaction and visual checks still belong in the Windows test plan.

Run `python3 preview/build.py` from the repository root after changing text, colors or icon geometry. Update preview HTML/CSS separately when changing layout.
