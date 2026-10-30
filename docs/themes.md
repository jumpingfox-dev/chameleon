# Server themes

Chameleon reads themes from your Jellyfin server's **Custom CSS** (Dashboard › General ›
Custom CSS code). Every Chameleon app signed in to the server finds them there, so you set them
up once, and a theme is just a block of text you can copy, share (in a GitHub gist, say) and
paste into your own server's CSS.

The web client ignores these blocks: they're CSS custom properties on selectors nothing in the
page uses, so they sit happily next to any web theme (ElegantFin, Ultrachromic, ...) in the same
box.

There are two kinds of block:

- **Defaults**: one per server, for everyone on it whatever their theme. Your server's logo,
  genre pictures, which theme people start on, and every setting's starting value: Home's
  sections, playback, subtitles, the screensaver, the sign-in pages...
- **Themes**: as many as you like, each one a look: colors, fonts, icons, and its own logo and
  genre pictures.

## Defaults

```css
/* chameleon-defaults
   version: 1 */
.chameleon-defaults {
  --theme: "House";
  --logo: url("https://raw.githubusercontent.com/you/themes/main/logo.png");
  --genre-action: url("https://raw.githubusercontent.com/you/themes/main/action.jpg");
  --genre-science-fiction: url("https://raw.githubusercontent.com/you/themes/main/sci-fi.jpg");
  --genre-folder: url("https://raw.githubusercontent.com/you/themes/main/genres/");
}
```

| Property | What it is |
|---|---|
| `--theme` | The theme people start on, by name. Anyone can pick another (each person keeps their own). If it isn't the name of a theme below, people start on Chameleon's own look, and the theme picker says so. |
| `--logo` | Shown in place of the "chameleon" wordmark: in the top bar, the menu and on the sign-in pages, for any theme without a logo of its own (see [Logos](#logos)). |
| `--genre-<name>` | A genre's picture, for genre cards set to **Theme pictures** (Settings › Appearance › Genre cards). |
| `--genre-folder` | A folder of genre pictures, each named after its genre (see [Genre folders](#genre-folders)). A `--genre-<name>` takes precedence over the folder's picture for that genre. |
| `--server-backdrop` | `false` hides your Jellyfin splash screen behind the sign-in pages and "Who's watching?". |
| `--login-disclaimer` | `false` hides your Jellyfin login disclaimer under the sign-in form. |
| `--<setting>` | Any setting in [assets/defaults.json](defaults.md), by its name there in kebab-case: `autoplayNext` is `--autoplay-next`, `subtitleSize` is `--subtitle-size`. These take precedence over the app's own defaults; anyone who changes the setting in Settings keeps their choice. |
| `--section-<section>-<option>` | A Home section's default (see [sections](defaults.md#sections)), in kebab-case: `--section-continue-watching-limit: 30`, `--section-carousel-seconds: 10`, `--section-genres-genre-count: 6`, `--section-favorites-kinds: Movie, Series`. A favorite kind's name: `--section-favorites-names-season: false`. `--section-collection-…` and `--section-genre-…` set every Collection and Genre row's. |

`--server-backdrop` and `--login-disclaimer` are what each device starts with: anyone can turn
either back on or off on their own device in Settings › Appearance › Sign-in.

Settings, as an example:

```css
.chameleon-defaults {
  --bottom-bar: home, search, downloads, settings;
  --home: carousel, myMedia, continueWatching, nextUp, genres;
  --section-carousel-seconds: 10;
  --section-continue-watching-limit: 30;
  --autoplay-next: false;
  --skip-intro: auto;           /* skip-intro, skip-recap, skip-credits, skip-preview */
  --subtitle-size: large;
  --subtitle-background: outline;
  --style-on-tv: posters;
  --server-backdrop: false;
}
```

Values are written as in defaults.json, without its quotes and brackets: `true` / `false`,
numbers, a name, or a list separated by commas.

Defaults have no colors, fonts or icons: those are a theme's. Put your house look in a theme,
and name it in `--theme` (which can also name one of Chameleon's own, such as `"Ruby"`). Fonts,
icons and genre cards can still go in the defaults, for whoever's on one of Chameleon's own
themes, or a theme that doesn't set them.

## Themes

```css
/* chameleon-theme: House
   author: you
   version: 1 */
.chameleon-theme[data-name="House"] {
  --seed: 270-280-8-1;
  --primary: #7c4dff;
  --background: #0b0d16;
  --heading-font: "Bebas Neue";
  --icons: lucide;
  --genre-horror: url("https://raw.githubusercontent.com/you/themes/main/horror.jpg");
}
```

The name is in `data-name="..."`. The comment above it is optional; Chameleon shows its
`author` in the list of server themes (Settings › Appearance › Theme › Custom › Server Themes).

A theme is how the app looks, and nothing else:

| Property | What it is |
|---|---|
| `--seed` | A starting point for every color, as the custom theme editor's seed code (`270-280-8-1`, or `27028081`: base hue, accent hue, vibrance, depth). Without it, a theme starts from Chameleon's Default theme. |
| `--brightness` | `dark` or `light`. |
| `--background`, `--foreground`, `--primary`, `--primary-foreground`, `--secondary`, `--secondary-foreground`, `--muted`, `--muted-foreground`, `--card`, `--border`, `--barrier`, `--destructive`, `--destructive-foreground`, `--error`, `--error-foreground` | Colors, as `#RRGGBB`, `#AARRGGBB` or `hsl(...)`. Anything you leave out comes from the seed. `--accent` is another name for `--primary`. |
| `--heading-font`, `--body-font` | Fonts, by their Google Fonts name. |
| `--icons` | `materialSymbols`, `phosphor`, `lucide`, `cupertino` or `fluent`. |
| `--genre-cards` | `icons`, `pictures` or `theme`. |
| `--logo` | This theme's logo (see [Logos](#logos)). |
| `--genre-<name>` | This theme's picture for a genre, in place of the defaults' one. |
| `--genre-folder` | This theme's folder of genre pictures. A genre's picture comes from, in order: the theme's `--genre-<name>`, the theme's folder, the defaults' `--genre-<name>`, the defaults' folder. |

Any other setting (playback, subtitles, Home's sections, ...) belongs in the defaults: in a
theme it's ignored, and the theme picker points it out.

Picking a theme makes its fonts, icons and genre cards yours. If you'd chosen any of those
yourself, Chameleon says which it's about to replace, and what with, and asks first.

A quick way to get the colors: build a theme in the app (Settings › Appearance › Theme ›
Custom), and copy its seed code or colors.

## Logos

The logo comes from, in order:

1. The theme's `--logo`
2. The defaults' `--logo`
3. Chameleon's own "chameleon" wordmark

So a theme without a logo shows the server's, and with neither, Chameleon's own. On the sign-in
pages (nobody's picked a theme yet), the theme is the one named in `--theme`.

## Genre names

`--genre-` followed by the genre's name in lower case, with anything that isn't a letter or a
digit as `-`: Action is `--genre-action`, Science Fiction is `--genre-science-fiction`,
Talk-Show is `--genre-talk-show`.

## Genre folders

Rather than a `--genre-<name>` line for every genre, point `--genre-folder` at a folder and name
each picture after its genre. For each of your server's genres, Chameleon tries, in order:

1. Its name as in `--genre-<name>`: `science-fiction.png`, `science-fiction.jpg`, `.jpeg`, `.webp`, `.gif`, `.svg`
2. Its name as Jellyfin has it: `Science Fiction.png`, and so on

and uses the first one there. Genres with no picture in the folder get their icon card, as usual.

A folder can't be listed over the web, so Chameleon asks for each name in turn: it looks through the
folder when it connects (and again a day later), and saves what it found, so the pictures also work
offline. With many genres and few pictures, the first look can take a few seconds; the cards show
their icons until it's done.

For a GitHub repository, use the `raw.githubusercontent.com` address of the folder, ending in `/`:
`https://raw.githubusercontent.com/you/themes/main/genres/`. Anything served over the web works the
same way, such as a folder on your own web server. The theme picker warns if none of your genres
has a picture in the folder (a misspelled address, usually).

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

Either can be hidden for everyone (`--login-disclaimer: false` and `--server-backdrop: false` in
the defaults), and anyone can hide or show them on their own device in Settings › Appearance ›
Sign-in.
