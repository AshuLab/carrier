// ponytail: these lists are a copy of src/chat/words.ts (ADR 0014), so a repository that is not on this Mac gets a name before it is
// cloned; the host still refuses a name that turns out taken. Ask the host for one instead if the lists ever drift.
private let adjectives = [
    "psionic", "cloaked", "burrowed", "sieged", "nuclear", "plasma", "ionic", "adaptive", "stimmed", "hallucinated",
    "irradiated", "parasitic", "spawning", "vespene", "hardened", "infested", "mutated", "consumed", "ensnared", "plagued",
    "charged", "cybernetic", "khaydarin", "twilight", "dark", "void", "shielded", "armored", "swift", "tactical",
    "orbital", "enslaved", "recalled", "warped", "cerebrate",
]
private let units = [
    "marine", "firebat", "medic", "ghost", "vulture", "goliath", "wraith", "valkyrie", "battlecruiser", "dropship",
    "zealot", "dragoon", "archon", "reaver", "corsair", "scout", "carrier", "arbiter", "observer", "shuttle",
    "probe", "scv", "zergling", "hydralisk", "mutalisk", "ultralisk", "lurker", "defiler", "guardian", "devourer",
    "overlord", "queen", "drone", "scourge", "templar", "interceptor", "tank", "broodling",
]
private let places = [
    "bunker", "barracks", "factory", "starport", "nexus", "pylon", "gateway", "forge", "cannon", "assimilator",
    "hatchery", "lair", "hive", "spire", "extractor", "refinery", "academy", "armory", "depot", "turret",
    "comsat", "nydus", "citadel", "stargate", "beacon", "observatory", "tribunal", "aiur", "char", "korhal",
    "tarsonis", "shakuras", "zerus", "braxis", "bhekar",
]

/// `<adjective>-<unit>-<place>`, the shape of the names the host generates.
func generatedWorktreeName() -> String {
    "\(adjectives.randomElement()!)-\(units.randomElement()!)-\(places.randomElement()!)"
}
