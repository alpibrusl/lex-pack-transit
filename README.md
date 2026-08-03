# lex-pack-transit

Scheduled-service (transit) domain pack — GTFS-style frequency-based trips, timetable expansion, and GTFS-RT-style adherence.

Extracted from [`lex-ev-fleet`](https://github.com/alpibrusl/lex-ev-fleet) (see [issue #238](https://github.com/alpibrusl/lex-ev-fleet/issues/238)). No cross-pack dependency, and no custody chain or settlement trail — a trip's "evidence" is a GTFS-RT-style position update assessed against the timetable.

## Routes

```
POST /transit/trips { trip_id, route, headsign, first_min, headway_min, last_min }
GET  /transit/trips
GET  /transit/trips/:id/departures      — expand the timetable
POST /transit/adherence { scheduled_min, actual_min, early_tol?, late_tol? }
```

## Usage

```lex
import "lex-pack-transit/transit_http" as transit_http

# in your router-wiring code:
let r := transit_http.mount(router.new(), db)
```

`transit_http.manifest()` returns the `pos.PackManifest` describing this pack's parties/pattern for the `lex-soft/src/positions` catalogue. The pure schedule math (`headway_departures`, `adherence`) lives in `transit.lex` and unit-tests directly.

## Layering

Part of the lex-soft pack family: `lex-soft` (engine, primitives) → this pack (`mount()` for the HTTP routes, `manifest()` for the `lex-soft/src/positions` catalogue) → [`lex-soft-node`](https://github.com/alpibrusl/lex-soft-node) (mounts a configured set of packs into a running deployment).

## License

Matches the rest of the lex ecosystem.
