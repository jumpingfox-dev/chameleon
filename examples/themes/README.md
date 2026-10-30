# Example server themes

Made-up brands for trying out [server themes](../../docs/themes.md): five with a logo of their own,
three without.

| Theme | Logo | Look |
|---|---|---|
| Nightowl Cinema | [nightowl.svg](nightowl.svg) | Midnight navy, amber |
| Popcorn Palace | [popcorn.svg](popcorn.svg) | Dark cherry, cream |
| Driftwood Media | [driftwood.svg](driftwood.svg) | Deep sea, teal |
| Neon Arcade | [neon.svg](neon.svg) | Purple night, hot pink and cyan |
| Paper Lantern | [lantern.svg](lantern.svg) | Light: parchment, red |
| Velvet Curtain | None | Plum, gold |
| Glacier | None | Light: ice blue |
| Graphite | None | Charcoal, green |

Paste all of [themes.css](themes.css) into Jellyfin's **Dashboard › General › Custom CSS code**.
Everyone starts on Nightowl Cinema. Pick another in Settings › Appearance › Theme › Custom ›
Server Themes.

The themes are only looks: colors, fonts, icons, and a logo. Everything else is in the
`.chameleon-defaults` block, for everyone on the server whatever their theme: Home's sections,
playback, subtitles, the screensaver, and the sign-in pages (no splash screen behind them).

The logoless themes show the defaults' logo if it has one, else Chameleon's own. The defaults'
`--logo` line is commented out, so they show Chameleon's; uncomment it to see them use Nightowl's.

The logos load from this repository on GitHub, so they work once it's pushed.
