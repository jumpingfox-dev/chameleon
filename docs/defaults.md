# Default settings

`assets/defaults.json` holds what every setting starts as, for anyone who hasn't changed it in
Settings. Edit it and rebuild; a setting someone has already changed on a device keeps their
choice. Anything left out of the file falls back to the app's built-in value, and if the file
can't be read the app uses its built-in values for everything.

## appearance

| Key | Values |
| --- | --- |
| `theme` | `default`, `ruby`, `amber`, `citrine`, `emerald`, `sapphire`, `tanzanite`, `amethyst` |
| `headingFont`, `bodyFont` | Any Google Fonts family name, e.g. `"Space Grotesk"` |
| `icons` | `materialSymbols`, `phosphor`, `lucide`, `cupertino`, `fluent` |
| `bottomBar` | Up to 4 of `home`, `search`, `downloads`, `favorites`, `genres`, `settings`, or a library kind: `movies`, `tvshows`, `music`, `boxsets`, ... (the first library of that kind). `downloads` becomes `favorites` on devices without downloads. |
| `menuPinned` | `true` keeps the menu open beside the page on wide screens |

## home

The Home sections, in order: `carousel`, `myMedia`, `continueWatching`, `nextUp`, `favorites`,
`recentlyAdded`, `recentlyAddedMovies`, `recentlyAddedSeries`, `suggested`, `becauseYouWatched`.
(Collection and genre sections need a choice, so they're added in the app.)

## playback

| Key | Values |
| --- | --- |
| `skip` | For each of `intro`, `recap`, `credits`, `preview`: `ask`, `auto` or `ignore` |
| `autoplayNext` | `true` / `false` |
| `countdownSeconds` | Seconds before the next episode starts |
| `stillWatchingAfter` | Episodes in a row before "Still watching?" (`0` never asks) |
| `wifiBitrate`, `mobileBitrate` | Bits per second; `0` is the original quality |
| `streamMode` | `auto`, `direct`, `transcode` |
| `seekStep` | Seconds per skip forward or back |
| `seekAccelerates` | `true` / `false` |
| `resume` | `resume`, `ask`, `startOver` |
| `subtitleFont` | Any Google Fonts family name |
| `subtitleSize` | `small`, `medium`, `large`, `extraLarge` |
| `subtitleHeight` | Percent of the screen's height, up from the bottom |
| `subtitleColor` | `white`, `yellow`, `cyan`, `green` |
| `subtitleBackground` | `shadow`, `outline`, `box` |
| `liftSubtitles`, `passthrough`, `downmix`, `nightMode`, `showRating`, `trickplay`, `previews` | `true` / `false` |
| `aspect` | `fit`, `fill` |
| `engine` | `auto`, `mpv`, `exo` |
| `previewDelay` | Seconds on a card before its stills start |

## screensaver

| Key | Values |
| --- | --- |
| `styleOnTv`, `styleElsewhere` | `off`, `backdrops`, `posters`, `clock`, `logo` |
| `startAfter`, `dimAfter`, `awakeFor` | Minutes (`dimAfter` `0` never dims) |
| `turnOff` | `true` / `false` |
| `dim` | `0`, `10`, `20`, `30`, `40`, `50`, `60` (percent) |
| `backdropContent`, `posterContent` | `all`, `movies`, `shows` |
| `backdropSeconds` | Seconds per picture |
| `backdropMotion`, `backdropDetails`, `backdropClock`, `posterClock`, `clockDate`, `clockArtwork` | `true` / `false` |
| `posterRows` | `2` to `5` |
| `posterSpeed`, `logoSpeed` | `slow`, `medium`, `fast` |
| `clockFormat` | `device`, `twelve`, `twentyFour` |
| `clockSize`, `logoSize` | `small`, `medium`, `large` |
| `clockColor`, `logoColor` | `theme`, `white`, `changing` |
