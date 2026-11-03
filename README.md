# CarXplore 🚗☁️

Kortet starter dækket af tåge. Når du kører rundt i din bil, forsvinder tågen
stille og roligt, og du låser verden op. Kør forbi seværdigheder som
**Næstved Rådhus**, **Kronborg** eller **Grenen** for at få trofæer, og dyst
mod dine venner om, hvem der har udforsket mest.

## Udseende

Mørkt "neon over skyerne"-tema: kortet er mørkt og dækket af skyer, ruten
lyser neonblå, og kortene ligner frostet glas. Der er fire faner:

- **Kort**: din bil ("Mig"), venner som avatarer, søgning efter venner,
  niveau, hvor stor en del af dit lokalområde du har låst op, km kørt og
  START TUR.
- **Garage**: din bil, niveau og statistik (km, ture, natkørsel …).
- **Fremskridt**: trofæer (fx Tågebryder, Globetrotter, Natuglen,
  Kort-sluger), seværdigheder og en rangliste mod dine venner.
- **Profil**: navn, bil, positionsdeling, vennekode, venner og tilladelser.

## Funktioner

- **Tågekort**: MapKit-kort med tåge-overlay. En stribe på ca. 150 m omkring
  bilen bliver afsløret, mens en tur er i gang. Kortet er delt op i felter på
  0,001° (ca. 110 × 64 m i Danmark). Huller i GPS-sporet på op til 3 km bliver
  udfyldt.
- **Ture i baggrunden**: Lokationen er sat op til bilkørsel og fortsætter, når
  skærmen slukkes.
- **Trofæer**: 16 danske seværdigheder fordelt på fire sjældenheder
  (almindelig, sjælden, episk, legendarisk) med point, banner, haptik og
  notifikation, når én låses op.
- **Venner og leaderboard**: Vennekode, tilføj eller fjern venner, se hvor de
  er og om de kører lige nu, og en rangliste efter point. Backenden er
  [Supabase](https://supabase.com) (se nedenfor). Uden server kører appen i
  demo-tilstand med testvenner.
- **Privatliv**: Positionen deles kun under en tur og kun hvis "Del min
  position" er slået til. Slås det fra, slettes den gemte position på serveren.
- **Point og niveauer**: 10 point pr. udforsket km² plus trofæpoint. Point
  giver niveauer fra *Søndagskører* til *Legende*.
- **Trofæer for mål**: fx 10 % / 50 % af lokalområdet (10 km omkring der,
  hvor du kørte første gang), 1.000 km i alt, 50 km om natten, 25 ture og
  din første ven.
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

## Venne-backend (Supabase)

Al logik ligger i Postgres: tabeller, Row Level Security og RPC-funktioner i
[`supabase/migrations`](supabase/migrations). Appen kalder funktionerne via
`supabase-swift`.

| Funktion | Hvad den gør |
|---|---|
| `my_profile()` | Min profil inkl. vennekode (oprettes automatisk ved første login) |
| `update_profile(navn, bil, del_position)` | Ret profil. Slås deling fra, slettes positionen |
| `update_status(km², trofæer, point, kører, lat, lon)` | Send fremskridt (hvert 15.–60. sekund) |
| `add_friend(kode)` | Bliv venner (begge veje) med ejeren af koden |
| `remove_friend(id)` | Fjern venskab (begge veje) |
| `get_friends()` | Mine venner. Position kun hvis de deler den |

Brugere kan kun læse deres egen række direkte. Venners data går gennem
`get_friends()`, og der er ingen direkte skriveadgang til tabellerne.

**Opsætning:**

1. Opret et gratis projekt på [supabase.com](https://supabase.com).
2. Kør migrationen: indsæt `supabase/migrations/*.sql` i *SQL Editor*, eller
   brug `supabase link` efterfulgt af `supabase db push`.
3. Slå *Authentication → Sign In / Providers → Allow anonymous sign-ins* til.
   Appen logger ind anonymt første gang.
4. Opret `Secrets.xcconfig` i roden (ignoreres af git) med værdier fra
   *Project Settings → API*:
   ```
   SUPABASE_URL = https:/$()/DIT-PROJEKT.supabase.co
   SUPABASE_ANON_KEY = din-anon-public-key
   ```
5. Kør `xcodegen generate` igen og byg appen.

**Test af databasen** (kræver bare en Postgres 16):

```bash
PGHOST=localhost PGUSER=postgres supabase/tests/run.sh
```

CI kører de samme tests ved hvert push.

## Struktur

```
CarXplore/
  App/        App-indgang og faner
  Models/     CellID/Geo (gitter), Landmark + katalog, GameStore, Friend
  Services/   LocationService, FriendsService (+ mock), SupabaseFriendsService, Notifier
  Map/        FogOverlay/FogRenderer (tågen) og ExploreMapView (MKMapView)
  UI/         Tema: farver, glaskort, logo, knapper
  Views/      Kort, Garage, Fremskridt, Profil
CarXploreTests/
supabase/
  migrations/ Databaseskema, RLS og RPC-funktioner
  tests/      SQL-tests + en lille Supabase-stub til almindelig Postgres
```

## Næste skridt

1. **Sign in with Apple**: Kobl den anonyme konto til et Apple-login
   (`linkIdentity`), så fremskridtet overlever et telefonskifte, og
   synkronisér selve tågen (felterne) til serveren.
2. **Live-opdateringer**: Brug Supabase Realtime i stedet for polling, så
   venner flytter sig på kortet med det samme.
3. **Privatliv**: Skjul positionen automatisk nær hjemmet (privatzoner).
4. **Seværdigheder fra serveren**: Hent katalog og koordinater fra serveren
   (de nuværende koordinater er omtrentlige). Eventuelt automatisk fra
   OpenStreetMap/Wikidata for hele verden.
5. **Snydebeskyttelse**: Afvis urealistiske hastigheder og kræv, at man
   faktisk kører (CMMotionActivity `automotive`).
6. **Mere konkurrence**: Ugentlige ligaer, kommune-/regionsprocenter
   ("Du har udforsket 12 % af Næstved Kommune") og badges.
7. **Ydelse**: Skift til tile-baseret lagring eller SQLite, når antallet af
   udforskede felter bliver meget stort.
