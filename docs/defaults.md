# Default settings

`assets/defaults.json` holds what every setting starts as, for anyone who hasn't changed it in
Settings. Edit it and rebuild; a setting someone has already changed on a device keeps their
choice. A server can set its own defaults in its Custom CSS, which take
precedence over this file's (see [themes.md](themes.md#defaults)). Anything left out of the file falls back to the app's built-in value, and if the file
can't be read the app uses its built-in values for everything.

The file is laid out like Settings: a section for each part of it, and inside, a group for each
item (Appearance › Fonts, Playback › Subtitles, ...). Settings kept on your Jellyfin account
rather than the device (audio and subtitle languages, Parental Controls) aren't in it.

## appearance

| Key | Values |
| --- | --- |
| `fonts.headingFont`, `fonts.bodyFont` | Any Google Fonts family name, e.g. `"Space Grotesk"` |
| `theme` | `default`, `ruby`, `amber`, `citrine`, `emerald`, `sapphire`, `tanzanite`, `amethyst` |
| `icons` | `materialSymbols`, `phosphor`, `lucide`, `cupertino`, `fluent` |
| `genreCards` | `icons`, `pictures` (the pictures Jellyfin has for each genre), `theme` (the server theme's: see [themes.md](themes.md)) |
| `bottomBar` | Up to 4 of `home`, `search`, `downloads`, `favorites`, `genres`, `settings`, or a library kind: `movies`, `tvshows`, `music`, `boxsets`, ... (the first library of that kind). `downloads` becomes `favorites` on devices without downloads. |
| `menuPinned` | `true` keeps the menu open beside the page on wide screens |
| `signIn.serverBackdrop` | `false` hides the server's splash screen behind its sign-in pages and "Who's watching?" (Settings › Appearance › Sign-in). Kept for the device, not per person: it shows before anyone's signed in. |
| `signIn.loginDisclaimer` | `false` hides the server's login disclaimer under the sign-in form. Also kept for the device. |

### appearance.screensaver

| Key | Values |
| --- | --- |
| `styleOnTv`, `styleElsewhere` | `off`, `backdrops`, `posters`, `clock`, `logo` |
| `startAfter`, `dimAfter` | Minutes (`dimAfter` `0` never dims) |
| `dim` | `0`, `10`, `20`, `30`, `40`, `50`, `60` (percent) |
| `backdrops.backdropContent`, `posterWall.posterContent` | `all`, `movies`, `shows` |
| `backdrops.backdropSeconds` | Seconds per picture |
| `backdrops.backdropMotion`, `backdrops.backdropDetails`, `backdrops.backdropClock`, `posterWall.posterClock`, `clock.clockDate`, `clock.clockArtwork` | `true` / `false` |
| `posterWall.posterRows` | `2` to `5` |
| `posterWall.posterSpeed`, `floatingLogo.logoSpeed` | `slow`, `medium`, `fast` |
| `clock.clockFormat` | `device`, `twelve`, `twentyFour` |
| `clock.clockSize`, `floatingLogo.logoSize` | `small`, `medium`, `large` |
| `clock.clockColor`, `floatingLogo.logoColor` | `theme`, `white`, `changing` |

## home

The Home sections, in order: `carousel`, `myMedia`, `genres`, `continueWatching`, `nextUp`, `favorites`,
`recentlyAdded`, `recentlyAddedMovies`, `recentlyAddedSeries`, `suggested`, `becauseYouWatched`.
(Collection and genre sections need a choice, so they're added in the app.)

## sections

How each Home section starts out (what its cog in Edit home sets), by section, as in `home`.
`collection` and `genre` are the defaults for every Collection and Genre row.

| Key | Sections | Values |
| --- | --- | --- |
| `showTitle` | All | `true` / `false`: the section's title above it |
| `limit` | All but `myMedia` and `genres` | How many it shows: `carousel` `1` to `10`; the rest `10`, `20`, `30`, `50` or `100` |
| `kinds` | `carousel` | `all`, `movies`, `shows`, `collections` |
| `seconds` | `carousel` | Seconds per slide: `5`, `8`, `10`, `15`, `20` |
| `look` | `myMedia` | `pictures` (Jellyfin's), `icons` |
| `cardNames` | `myMedia`, `genres` | `true` / `false`: each card's name under it |
| `genreCount` | `genres` | `"all"`, or how many |
| `pick` | `genres` | `random`, `chosen` (when not showing them all) |
| `chosen` | `genres` | The genres to show, by name, for `pick: chosen` |
| `episodeTitles` | `continueWatching`, `nextUp` | `true` / `false`: the show and episode under each card |
| `episodeTitleStyle` | `continueWatching`, `nextUp` | `both` (S1:E5 · name), `code` (S1:E5), `name` |
| `movieTitles` | `continueWatching` | `true` / `false` |
| `cutoffDays` | `continueWatching` | Leave out what hasn't been touched in: `"never"`, `30`, `90`, `180` (days) |
| `cutoff` | `nextUp` | Leave out shows not watched in: `"server"` (as set in Jellyfin), `"never"`, `30`, `90`, `180`, `365` (days) |
| `rewatching` | `nextUp` | Shows you've watched through, again: `"server"`, `"on"`, `"off"` |
| `kinds` | `favorites` | Any of `Movie`, `Series`, `BoxSet`, `Season`, `Episode` |
| `names` | `favorites` | For each of those kinds, `true` / `false`: its name under its card |
| `sort` | `favorites` | `random`, `name`, `added`, `released` |
| `basis` | `becauseYouWatched` | `last` (the last thing watched), `random` (one of the last few) |

## playback

| Key | Values |
| --- | --- |
| `episodes.skip` | For each of `intro`, `recap`, `credits`, `preview`: `ask`, `auto` or `ignore` |
| `episodes.autoplayNext` | `true` / `false` |
| `episodes.countdownSeconds` | Seconds before the next episode starts |
| `episodes.stillWatchingAfter` | Episodes in a row before "Still watching?" (`0` never asks) |
| `streamingQuality.wifiBitrate`, `streamingQuality.mobileBitrate` | Bits per second; `0` is the original quality |
| `streamingQuality.streamMode` | `auto`, `direct`, `transcode` |
| `seekingAndResuming.seekStep` | Seconds per skip forward or back |
| `seekingAndResuming.seekAccelerates` | `true` / `false` |
| `seekingAndResuming.resume` | `resume`, `ask`, `startOver` |
| `subtitles.subtitleFont` | Any Google Fonts family name |
| `subtitles.subtitleSize` | `small`, `medium`, `large`, `extraLarge` |
| `subtitles.subtitleHeight` | Percent of the screen's height, up from the bottom |
| `subtitles.subtitleColor` | `white`, `yellow`, `cyan`, `green` |
| `subtitles.subtitleBackground` | `shadow`, `outline`, `box` |
| `subtitles.liftSubtitles`, `audio.passthrough`, `audio.downmix`, `audio.nightMode`, `video.showRating`, `video.trickplay`, `previews.previews` | `true` / `false` |
| `video.aspect` | `fit`, `fill` |
| `video.engine` | `auto`, `mpv`, `exo` |
| `previews.previewDelay` | Seconds on a card before its stills start |
