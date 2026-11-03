# CarXplore 🚗☁️

Kortet starter dækket af tåge. Når du kører rundt i din bil, forsvinder tågen
stille og roligt, og du låser verden op. Kør forbi seværdigheder som
**Næstved Rådhus**, **Kronborg** eller **Grenen** for at få trofæer, og dyst
mod dine venner om, hvem der har udforsket mest.

## Funktioner (v0.1)

- **Tågekort**: MapKit-kort med tåge-overlay. En stribe på ca. 150 m omkring
  bilen bliver afsløret, mens en tur er i gang. Kortet er delt op i felter på
  0,001° (ca. 110 × 64 m i Danmark). Huller i GPS-sporet på op til 3 km bliver
  udfyldt.
- **Ture i baggrunden**: Lokationen er sat op til bilkørsel og fortsætter, når
  skærmen slukkes.
- **Trofæer**: 16 danske seværdigheder fordelt på fire sjældenheder
  (almindelig, sjælden, episk, legendarisk) med point, banner, haptik og
  notifikation, når én låses op.
- **Venner og leaderboard**: Vennekode, tilføj venner, se hvor de er og om de
  kører lige nu, og en rangliste efter point. *Venner er testdata indtil
  videre*, se nedenfor.
- **Point**: 10 point pr. udforsket km² plus trofæpoint.
- Fremskridt gemmes lokalt på telefonen.

## Kom i gang (kræver en Mac)

```bash
brew install xcodegen
```

```bash
xcodegen generate
```

```bash
open CarXplore.xcodeproj
```

Vælg dit Apple-udviklerteam under *Signing & Capabilities* og kør på din
iPhone. Tågen kan også testes i simulatoren: vælg *Features → Location →
Freeway Drive* og tryk **Start tur**.

GitHub Actions (`.github/workflows/ios.yml`) bygger appen og kører
unit-testene på en macOS-maskine ved hvert push.

## Struktur

```
CarXplore/
  App/        App-indgang og faner
  Models/     CellID/Geo (gitter), Landmark + katalog, GameStore, Friend
  Services/   LocationService, FriendsService (+ mock), Notifier
  Map/        FogOverlay/FogRenderer (tågen) og ExploreMapView (MKMapView)
  Views/      Kort, Trofæer, Venner, Profil
CarXploreTests/
```

## Næste skridt

1. **Backend til venner**: Erstat `MockFriendsService` med en rigtig
   implementering (fx Firebase/Supabase eller CloudKit) med login (Sign in
   with Apple), vennekoder, synkronisering af fremskridt og live-position.
2. **Privatliv**: Lad brugeren vælge, hvem der kan se deres live-position,
   og skjul den fx nær hjemmet.
3. **Seværdigheder fra serveren**: Hent katalog og koordinater fra serveren
   (de nuværende koordinater er omtrentlige). Eventuelt automatisk fra
   OpenStreetMap/Wikidata for hele verden.
4. **Snydebeskyttelse**: Afvis urealistiske hastigheder og kræv, at man
   faktisk kører (CMMotionActivity `automotive`).
5. **Mere konkurrence**: Ugentlige ligaer, kommune-/regionsprocenter
   ("Du har udforsket 12 % af Næstved Kommune") og badges.
6. **Ydelse**: Skift til tile-baseret lagring eller SQLite, når antallet af
   udforskede felter bliver meget stort.
