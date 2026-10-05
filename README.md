# WFW Update Assistant

A Windows PowerShell/WPF assistant that guides users through eight update and maintenance steps. A separate browser preview lets you review the interface on macOS without running Windows operations.

## Start here

- **macOS UI testing:** double-click [START-MACOS.command](START-MACOS.command), or open [preview/index.html](preview/index.html) in a browser.
- **Windows application:** use [UPDATE-ASSISTENT-STARTEN.cmd](WFW_Update_Assistent%203/UPDATE-ASSISTENT-STARTEN.cmd). See [START-HIER.txt](WFW_Update_Assistent%203/START-HIER.txt) for user instructions.

## Code map

| File | Responsibility |
| --- | --- |
| [Update-Assistent.ps1](WFW_Update_Assistent%203/Programm/Update-Assistent.ps1) | Entry point, localized step data, session state, WPF rendering, action routing, worker polling and restart handling. Section comments follow this execution flow. |
| [Updates.psm1](WFW_Update_Assistent%203/Programm/Module/Updates.psm1) | Background worker dispatcher for Windows Update, Defender, winget and Lenovo tool installation. Writes a log and structured result for the UI. |
| [WindowsUpdate.psm1](WFW_Update_Assistent%203/Programm/Module/WindowsUpdate.psm1) | Device-management checks, update configuration, Windows Update Agent search/download/install cycle and reboot results. |
| [LenovoTools.psm1](WFW_Update_Assistent%203/Programm/Module/LenovoTools.psm1) | Detects and installs Lenovo tools. Device and firmware updates are handled in those tools. |
| [Oberflaeche.xaml](WFW_Update_Assistent%203/Programm/Oberflaeche.xaml) | Window layout and named controls. |
| [Theme.xaml](WFW_Update_Assistent%203/Programm/Oberflaeche/Theme.xaml) | Shared colors, typography, spacing and dimensions. |
| [Styles.xaml](WFW_Update_Assistent%203/Programm/Oberflaeche/Styles.xaml) | Reusable WPF control styles and interaction states. |
| [Validieren.ps1](WFW_Update_Assistent%203/IT/Validieren.ps1) | PowerShell syntax, main XAML and package-presence checks; does not run updates. |
| [preview/index.html](preview/index.html) | Browser preview structure and static controls. |
| [preview/style.css](preview/style.css) | Preview layout, control styling and responsive rules. |
| [preview/app.js](preview/app.js) | In-memory preview state, rendering, simulated actions and event bindings. |
| [preview/build.py](preview/build.py) | Reads literal Windows display data and theme colors; generates preview assets without executing PowerShell. |
| [preview/data.js](preview/data.js), [preview/theme.css](preview/theme.css) | Generated assets. Edit the Windows sources and regenerate instead of editing these directly. |

## How the Windows pieces connect

1. The launcher starts PowerShell in STA mode, which WPF requires.
2. The main script loads theme resources, styles and layout, then binds named controls.
3. Step action IDs route either to an external Windows window or to a separate worker process.
4. The worker writes `details.txt` and `result.json` into its run folder. The UI timer reads them and updates the current step.
5. Manual confirmations and automatic results feed the session summary. Restart handling saves state for the next sign-in.

The macOS preview follows its own simulated state flow. It does not invoke these workers or validate native WPF rendering.

## Making changes

- **Text or step labels:** edit the German/English dictionaries in the main PowerShell script. Keep action IDs and step order aligned across languages.
- **Windows appearance:** edit the XAML layout, theme or styles. Keep named controls aligned with the main script. More detail is in [README-UI.md](WFW_Update_Assistent%203/Programm/Oberflaeche/README-UI.md).
- **Preview text/colors:** run `python3 preview/build.py` from the repository root after changing the Windows sources. The parser supports these literal dictionaries, not arbitrary PowerShell expressions.
- **Preview layout:** update HTML/CSS separately when the Windows layout changes.
- **Validation:** run the IT validation script on Windows, then follow [IT-Testplan.md](WFW_Update_Assistent%203/IT/IT-Testplan.md) for native functionality checks.

Keep comments focused on responsibilities, state transitions and platform constraints. Preserve UTF-8 BOM encoding for PowerShell files containing German text, so Windows PowerShell 5.1 reads them correctly.
