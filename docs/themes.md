# Server themes

Chameleon reads themes from your Jellyfin server's **Custom CSS** (Dashboard › General ›
Custom CSS code). Every Chameleon app signed in to the server finds them there, so you set them
up once, and a theme is just a block of text you can copy, share (in a GitHub gist, say) and
paste into your own server's CSS.

The web client ignores these blocks: they're CSS custom properties on selectors nothing in the
page uses, so they sit happily next to any web theme (ElegantFin, Ultrachromic, ...) in the same
box.

There are two kinds of block:

- **Defaults**: one per server. Your server's logo, genre pictures, and which theme people start
  on.
- **Themes**: as many as you like. Each one has colors, and can have its own logo and genre
  pictures too.

## Defaults

```css
/* chameleon-defaults
   version: 1 */
.chameleon-defaults {
  --theme: "House";
  --logo: url("https://raw.githubusercontent.com/you/themes/main/logo.png");
  --genre-action: url("https://raw.githubusercontent.com/you/themes/main/action.jpg");
  --genre-science-fiction: url("https://raw.githubusercontent.com/you/themes/main/sci-fi.jpg");
}
```

| Property | What it is |
|---|---|
| `--theme` | The theme people start on, by name. Anyone can pick another (each person keeps their own). If it isn't the name of a theme below, people start on Chameleon's own look, and the theme picker says so. |
| `--logo` | Shown in place of the "chameleon" wordmark: in the top bar, the menu and on the sign-in pages. |
| `--genre-<name>` | A genre's picture, for genre cards set to **Theme pictures** (Settings › Appearance › Genre cards). |

| `--<setting>` | Any setting in [assets/defaults.json](defaults.md), by its name there in kebab-case: `headingFont` is `--heading-font`, `autoplayNext` is `--autoplay-next`. These take precedence over the app's own defaults; anyone who changes the setting in Settings keeps their choice. |

Defaults have no colors: put your house colors in a theme, and name it in `--theme` (which can
also name one of Chameleon's own, such as `"Ruby"`).

Settings, as an example:

```css
.chameleon-defaults {
  --heading-font: "Outfit";
  --body-font: "Plus Jakarta Sans";
  --icons: fluent;
  --genre-cards: theme;
  --bottom-bar: home, search, downloads, settings;
  --home: carousel, myMedia, continueWatching, nextUp, genres;
  --autoplay-next: false;
  --skip-intro: auto;           /* skip-intro, skip-recap, skip-credits, skip-preview */
  --subtitle-background: outline;
}
```

Values are written as in defaults.json, without its quotes and brackets: `true` / `false`,
numbers, a name, or a list separated by commas.

## Themes

```css
/* chameleon-theme: House
   author: you
   version: 1 */
.chameleon-theme[data-name="House"] {
  --seed: 270-280-8-1;
  --primary: #7c4dff;
  --background: #0b0d16;
  --genre-horror: url("https://raw.githubusercontent.com/you/themes/main/horror.jpg");
}
```

The name is in `data-name="..."`. The comment above it is optional; Chameleon shows its
`author` in the theme picker.

| Property | What it is |
|---|---|
| `--seed` | A starting point for every color, as the custom theme editor's seed code (`270-280-8-1`, or `27028081`: base hue, accent hue, vibrance, depth). Without it, a theme starts from Chameleon's Default theme. |
| `--brightness` | `dark` or `light`. |
| `--background`, `--foreground`, `--primary`, `--primary-foreground`, `--secondary`, `--secondary-foreground`, `--muted`, `--muted-foreground`, `--card`, `--border`, `--barrier`, `--destructive`, `--destructive-foreground`, `--error`, `--error-foreground` | Colors, as `#RRGGBB`, `#AARRGGBB` or `hsl(...)`. Anything you leave out comes from the seed. `--accent` is another name for `--primary`. |
| `--logo` | This theme's logo, in place of the defaults' one. |
| `--genre-<name>` | This theme's picture for a genre, in place of the defaults' one. |

A quick way to get the colors: build a theme in the app (Settings › Appearance › Theme ›
Custom), and copy its seed code or colors.

## Genre names

`--genre-` followed by the genre's name in lower case, with anything that isn't a letter or a
digit as `-`: Action is `--genre-action`, Science Fiction is `--genre-science-fiction`,
Talk-Show is `--genre-talk-show`.

## Pictures

PNG, JPEG, WebP, GIF or SVG (an SVG is turned into a picture when it's saved; one with features Chameleon can't draw, like embedded fonts, is reported as broken). `url(...)` addresses are used exactly as written:

- `https://...` anywhere, such as a GitHub repository (use the `raw.githubusercontent.com`
  address of the file).
- `http://192.168.1.10/...` on your own network: works on devices on that network.
- `file:///...` a file on the device itself: works only on a device that has that file.

Each picture is looked up in turn: the theme's, then the defaults', then Chameleon's own (the
"chameleon" wordmark, or the genre's icon card). A link that doesn't work drops to the next one.

Chameleon saves the pictures it uses on the device (at most 1000 pixels wide), so everything keeps working offline: the
defaults' and your theme's when it connects to the server, and a theme's when you pick it. A
saved picture is used even if its link later stops working.

## Broken links

When you open the theme picker, Chameleon checks every theme's links. A theme with links that
don't work is marked, with which pictures and the addresses that failed, so whoever wrote it
knows what to fix.

## The rest of your server's branding

Chameleon also uses the other branding settings on the same page (Dashboard › General):

- **Login disclaimer**: shown under the sign-in form, as Jellyfin's own sign-in page shows it.
- **Splash screen** (when it's turned on): shown behind the sign-in pages and "Who's watching?",
  dimmed, as Jellyfin's own sign-in page shows it. It's saved on the device when Chameleon
  connects, so it shows offline too; turn it off and Chameleon forgets it.
