# Why the catalog looks like this

Notes from November 2026, written while deciding what Driftwall should ship.

## What people actually use

The Steam Workshop for Wallpaper Engine is the biggest public record of which live wallpapers people keep, because every item shows its subscriber count. I pulled the top five pages of video wallpapers for three rankings and left out anything tagged Mature or Questionable.

| Ranking | Items | Anime | Game | Landscape / nature | Sci-fi, cyberpunk, retro | Cartoon / fantasy | Memes |
| --- | --- | --- | --- | --- | --- | --- | --- |
| All time | 88 | 45% | 10% | 11% | 14% | 5% | 6% |
| Trending, 90 days | 142 | 68% | 8% | 4% | 1% | 4% | 3% |
| Trending, 7 days | 116 | 47% | 26% | 1% | 2% | 4% | 1% |

Items can carry more than one tag, so rows don't add up to 100%.

The all-time top includes a VISUALDON retro space scene (3.1M subscribers), a WLOP illustration (2.9M), a Gargantua-style black hole (2.4M), an *Ori* game scene (1.6M), a 4K snowy forest (1.4M), an aerial of New York (1.25M) and a cosy cyberpunk apartment by Skeor (1.1M). The anime-focused wallpaper sites and the other Mac wallpaper apps lean the same way: anime and games first, then space, cyberpunk and landscapes.

Two things stood out. Ordinary stock footage barely shows up at all, and the scenic entries that do rank are cinematic renders rather than filmed b-roll. What people pick is a mood: a strong palette, slow motion, a loop that doesn't jump, and usually a place or a character at the centre.

## What can be redistributed

Most of that demand is someone else's property. Anime and game characters belong to their studios, and the best independent artists sell their loops under licences that rule out redistribution.

Free stock sites turned out to be closed as well. Pexels' rules say wallpaper apps may not distribute Pexels content as wallpapers. Pixabay's licence forbids distributing content on a standalone basis. Mixkit's terms forbid collecting items and offering them "on a stock or inventory basis" and using them to build a similar product. A wallpaper app built on any of the three would be breaking the terms it relies on.

That leaves sources whose licences allow redistribution, and a few of them happen to match what people want:

| Source | Licence | Resolution | Matches |
| --- | --- | --- | --- |
| NASA Scientific Visualization Studio | Public domain (NASA media guidelines) | 3840×2160 | the black hole and space wallpapers people already rank highly |
| ESA/Webb and ESA/Hubble videos | CC BY 4.0 | 3840×2160 | space; the pans are slow and detailed |
| Blender open movies (*Charge*, *Sintel*, *Tears of Steel*, *Big Buck Bunny*) | CC BY 3.0 / 4.0 | 4K scope masters, 16:9 crops of 1608 to 1744 px tall | cinematic fantasy and sci-fi scenes |
| Driftwall Originals | MIT | renders at display resolution | abstract and art styles |

## Where that leaves anime

The public catalog can't carry fan art of studio characters. People who want it can still bring their own: drag a video onto the window, import past Wallspace downloads, or let Driftwall watch the Downloads folder. Anime-style work from independent artists could join the catalog later if the artists opt in.

## Sources

- Steam Workshop, Wallpaper Engine: https://steamcommunity.com/app/431960/workshop/
- Pexels usage rules: https://help.pexels.com/hc/en-us/articles/360042332714
- Pixabay licence summary: https://pixabay.com/service/license-summary/
- Mixkit terms: https://mixkit.co/terms/
- NASA SVS, black hole visualization: https://svs.gsfc.nasa.gov/14619
- ESA/Webb copyright: https://esawebb.org/copyright
- Blender Studio films: https://studio.blender.org/films/
