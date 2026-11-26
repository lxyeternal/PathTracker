# Changelog

What changed in each version of Waytrace: what's new, what was adjusted and what was fixed. Newest first.

[简体中文](CHANGELOG.md) · [Back to the README](README_en.md)

---

## 1.0.9 · In progress

**New**

- Import workout routes from Health: outdoor walks, runs, rides and other workouts that an Apple Watch or another app saved to Health come in as tracks with their routes, filling in the distance from before you installed Waytrace. Distance, travel modes, Every Road and the year in review all count them. Find it in Settings › Data. Time that is already recorded is skipped, so it is safe to run again.

## 1.0.8 · In review

**Changed**

- The immersive globe shows three levels by distance: lights and flags from far out; closer, city names and the routes you travelled, with a tap on a city flying into it; closer still, the places one by one, with a photo where there is one, each opening its page.
- Countries on the immersive globe are outlined in white, clear on desert and dry land too; close in the outlines step aside instead of cutting across the coast.
- The globe at the top of Places is smaller, so the figures and your countries are on the first screen.

**Fixed**

- A walk that paused for a few minutes showed as two separate walks on the timeline. Everything between two visits is now one journey, and its time counts only the time moving.
- Dragging the map down in the immersive globe closed the whole page.
- Places abroad imported from photos showed as “Unknown place” on the timeline and the map when the lookup had no name for them. They now show the nearby well-known city, or else the country.

## 1.0.7 · 2026-11-26

**New**

- Countries can be searched when adding a visa or choosing a nationality: by Chinese or English name, pinyin, pinyin initials or country code.
- A new setting, “Only photos with a location”. When on, downloaded or saved pictures no longer appear in the timeline, places and trips. ([#8](https://github.com/lxyeternal/PathTracker/issues/8))
- The travel blind box has more to draw from for a day out: it searches the map in three rings (in town, nearby, farther out) for sights, museums, old towns, parks and trails, not only the must-see lists.
- An immersive globe: pull down at the top of Places, or tap the globe, for the Earth at night full screen. Countries you've visited are outlined and flagged; tap a flag to fly there, and zoom in to see every road you've travelled.
- Sights in Places can be filtered by the must-see lists or by country.

**Changed**

- With location set to “Always”, all-day recording no longer keeps the location icon in the Dynamic Island; recording in the background is unchanged. ([#6](https://github.com/lxyeternal/PathTracker/issues/6))
- Moving about within one place (from one campus building to another) shows as a single visit on the timeline.
- A photo taken somewhere else (it has a location more than 2 km from the place) no longer counts as that place's photo.
- Places is redesigned: the page is a night sky with the globe at the top and your countries, cities, sights and days written beneath it; countries are shown by their flags and cities as satellite views; the passport and stamps, the visa wallet, the must-see lists and the blind box each have a row, and the must-see lists show China and the world apart, each out of 100.
- Timeline cards are two lines, and the city appears only when it changes; times, dots, the line and the cards no longer crowd each other.
- The whole app is now dark, to match the night sky of Places. The blind box page is black and warm gold too, the same light as the globe.
- The album in Places only holds what you've posted, and no longer shows as an empty section when there's nothing yet.

**Fixed**

- “Import GPX file” in Settings couldn't select .gpx files. ([#5](https://github.com/lxyeternal/PathTracker/issues/5))
- Importing from photos in mainland China found no country for places abroad, so the count of countries didn't grow. When the lookup has no answer, the country now comes from the borders the app carries. ([#7](https://github.com/lxyeternal/PathTracker/issues/7))

## 1.0.6 · 2026-11-22

**Fixed**

- People who had shared Parallel Footprints with a friend before saw an error when tapping Invite a Friend, and the invitation wasn't sent.

## 1.0.5 · 2026-11-22

**New**

- The countries in the passport are a map: each one you've visited is outlined and flagged, continents can be switched, and visited cities light up.
- Must-see places can be lit by hand, with your photos and the date.
- A place can be marked as a mall or a restaurant.
- Parallel Footprints invitations open in the app from wherever the link is tapped.

**Changed**

- The travel blind box is redrawn as a brown-paper parcel, under the same night as the must-see lists.
- A trip's photos are in one section instead of appearing twice.

## 1.0.4 · 2026-11-17

**New**

- Places of your own can be added to the must-see lists.

**Changed**

- The weekend blind box only draws places near you.
- The timeline shows the latest place first.
- Places just recorded are named before those waiting from a photo import.
- Cities abroad are shown by their name in the app's language.

## 1.0.3 · 2026-11-13

**Fixed**

- The app closed on launch on early iOS 27.2 betas.

**Changed**

- The diagnostics log records how the app last closed.

## 1.0.2 · 2026-11-11

**New**

- Every Road can be viewed for today, this week, this month or this year.
- Recording can be paused until you resume it yourself.
- Firsts count places only, and come with pictures.

**Changed**

- The travel blind box was redesigned.
- Tidying places in the background uses less battery.

## 1.0.1 · 2026-11-07

**New**

- The travel blind box: draw a boarding pass to somewhere you haven't been.
- Several photos at one place fold on the timeline.

**Changed**

- A virtual journey says that it is virtual.

## 1.0 · 2026-11-06

- Waytrace arrives on the App Store: all-day automatic recording, trips, the footprint map, the passport and stamps, the visa wallet, Parallel Footprints, the must-see lists and the Apple Watch app.
