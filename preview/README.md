# macOS UI preview

Double-click [START-MACOS.command](../START-MACOS.command) in Finder, or open [index.html](index.html) directly in Safari, Chrome, or Firefox. No installation, PowerShell, or server is needed.

This browser recreation uses the Windows application's logo, theme colors, German/English text, and eight-step layout. Navigate steps, switch languages, try simulated actions, confirm manual checks, expand details, and view a session summary. The PDF button opens the supplied guide. Use Reset draft or reload to reset the preview.

All update actions are simulated. No Windows tools, installations, or restarts run. The preview is for reviewing layout and copy; macOS fonts and browser controls differ from native WPF. Native Windows rendering and functionality still require Windows. This draft previews the Windows version 1.3 flow without executing its workers.

After changing Windows text or theme colors, run `python3 preview/build.py` from the repository root. Generated [data.js](data.js) and [theme.css](theme.css) are checked in so opening the preview needs no build. Layout changes to the XAML must also be reflected in the preview HTML/CSS.

## Guided wizard

Each step presents a short introduction and its primary action. Expand **Step-by-step instructions** for the full guidance, **More options** for alternatives, and **Help & documentation** for support links. The scan/install sequence stays visible together. Back and Continue remain in the footer; continuing does not complete an open step.

The current layout uses full-width task screens. Click the bottom progress area to open the step overview; Escape or clicking outside closes it. Position and completed-step count are separate. Switching steps resets the content scroll position and closes task disclosures while preserving results. The original logo remains at the top, and version information is inside Help.

## Version 1.3 combined-run draft

The first screen now matches the Windows combined-run screen: start once, confirm,
and watch simulated Defender, application, Windows and driver tasks. Optional
drivers have a checkbox. Results remain separate, including failed tasks.

Use the controls above the app to choose a successful run, a required restart,
or an application failure. The restart example uses a six-second preview countdown
instead of the Windows app's 120 seconds. Postpone it and use **Simulate restart
and continue** to try resuming. The Mac is never restarted. **Reset draft** cancels
pending simulation timers and clears the results.

The draft runs offline with the checked-in assets. Keep the entire downloaded
folder together so the logo and PDF links work. If Finder will not open the
command file, you can open [index.html](index.html) directly in your browser.

## Development checks

Run `node preview/test.cjs` from the repository root to check the simulated flow
and generated bilingual copy. `node --check preview/app.js` checks JavaScript
syntax. The preview has also been exercised in a headless browser for confirmation
cancellation, successful and failed runs, optional drivers, postponed restart,
continuation, reset during work, language switching and narrow-screen layout.
