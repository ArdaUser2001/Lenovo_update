# macOS UI preview

Double-click [START-MACOS.command](../START-MACOS.command) in Finder, or open [index.html](index.html) directly in Safari, Chrome, or Firefox. No installation, PowerShell, or server is needed.

This browser recreation uses the Windows application's logo, theme colors, German/English text, and eight-step layout. Navigate steps, switch languages, try simulated actions, confirm manual checks, expand details, and view a session summary. The PDF button opens the supplied guide. Reload to reset the preview.

All update actions are simulated. No Windows tools, installations, or restarts run. The preview is for reviewing layout and copy; macOS fonts and browser controls differ from native WPF. Native Windows rendering and functionality still require Windows. The Windows application is unchanged.

After changing Windows text or theme colors, run `python3 preview/build.py` from the repository root. Generated [data.js](data.js) and [theme.css](theme.css) are checked in so opening the preview needs no build. Layout changes to the XAML must also be reflected in the preview HTML/CSS.

## Guided wizard

Each step presents a short introduction and its primary action. Expand **Step-by-step instructions** for the full guidance, **More options** for alternatives, and **Help & documentation** for support links. The scan/install sequence stays visible together. Back and Continue remain in the footer; continuing does not complete an open step.

The current layout uses full-width task screens. Click the bottom progress area to open the step overview; Escape or clicking outside closes it. Position and completed-step count are separate. Switching steps resets the content scroll position and closes task disclosures while preserving results. The original logo remains at the top, and version information is inside Help.
