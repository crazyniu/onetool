# 1Tool design

Operate mode. Preserve the six-page settings layout and the compact status panel.

The user requests current macOS design, a selectable primary accent and light/dark/automatic themes. Use system typography, semantic window and control backgrounds, native controls and an opaque native navigation rail. Use Liquid Glass only on bounded primary controls on macOS 26+; macOS 14–25 use bordered prominent controls. Sidebars and reading surfaces remain opaque, with semantic text contrast. Respect system accessibility behavior.

Default accent: system blue. Offer system, blue, purple, pink, red, orange, yellow, green and graphite. Accent drives controls and selections; ordinary text retains semantic foreground contrast. Theme and accent update the main window and status panel and persist independently. General settings start with a language selector, followed by three selectable miniature window previews and a color row, matching macOS Settings conventions.

Brand: an original single white upright open-jaw wrench on a flat solid-blue rounded-square app icon. No gradients, gloss or drawn shadows. Tools/Icon.swift deterministically draws this original vector artwork; the menu bar and default logo use the same silhouette as a monochrome template. The reference project's icon gallery, name validation and sizing logic are retained, while its planet/brand artwork is excluded.

Minimum window 840×620; detail pages scroll. Status panel measures its content and adapts height to the number of displays, keyboard support, errors and timer state. It scrolls only when it exceeds the current screen’s available height. Keep its 365-point width stable and use an opaque semantic background so wallpaper does not reduce text contrast. Left click opens it; right click opens a native status/timer/settings/icon/quit menu.

Shared density: 24-point page inset, 16-point section gap, 14-point group padding, 10-point row gap, 24-point page titles. Section labels align with group content. Icon choices use compact 42–48-point adaptive cells, with tooltips and accessibility names instead of visible default-logo captions. Theme previews have a stable 100×58-point size.

The status surface uses a native nonactivating NSPanel with one opaque pointer-and-body shape, native shadow and semantic colors. Close on outside click or Escape; settings links dismiss it explicitly. No glass background under the panel text or whole sidebar. Timers are 30 minutes, 1/2/4/8 hours and ∞; all three entry points share these choices. Runtime duration selection follows the actual session, including ∞.

Final branding: center the 48-point app icon in the 208-point sidebar. Use the same blue app icon at 32 points in the quick panel. Both headers contain the icon alone. Hide the title-bar title and remove repeated wordmarks. Navigation uses consistently sized monochrome SF Symbols and a semantic selection tint. The application remains named 1Tool in macOS identity, command names and accessibility.

Localization: English development language; eight complete localizations in native String Catalogs. Follow System by default, or select a language by its native name. Apply changes to the settings root and separately hosted panel immediately, and publish the resolved code to Finder over existing configuration IPC. Keep user-defined names and system-provided app/input-source names intact. Preserve all existing configuration when migrating the legacy Chinese-only preference. Text wraps vertically, sidebar labels support two lines, and appearance labels use a 96-point column for longer translations.
