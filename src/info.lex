# info.lex — the transit agent-domain manifest (pack.PackInfo).
#
# The DomainPack counterpart of this pack's REST pos.PackManifest: how a
# console should PRESENT the transit-ops persona — label, tagline, starter
# prompts. Served by the host under /platform/packs's agent_packs field.

import "lex-soft/src/pack" as pack

fn info() -> pack.PackInfo {
  { name: "transit", title: "Transit", tagline: "Frequency-based scheduled trips, expanded into departures and checked against adherence tolerances.", personas: [{ kind: "transit-ops", title: "Transit ops", tagline: "Declares trips, expands timetables, and checks schedule adherence.", suggested_prompts: ["Create a trip T1 on route 42 to Downtown, running from minute 360 to 1320 every 15 minutes.", "List every scheduled trip.", "What are the departures for trip T1?", "Check adherence: scheduled at minute 420, actual at minute 424."] }] }
}

