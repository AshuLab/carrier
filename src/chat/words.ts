// The words a worktree's generated name is made of: `<adjective>-<unit>-<place>`. Lowercase single words from
// StarCraft's units, structures and tech, never a character's full name (ADR 0014).

export const adjectives = [
  'psionic', 'cloaked', 'burrowed', 'sieged', 'nuclear', 'plasma', 'ionic', 'adaptive', 'stimmed', 'hallucinated',
  'irradiated', 'parasitic', 'spawning', 'vespene', 'hardened', 'infested', 'mutated', 'consumed', 'ensnared', 'plagued',
  'charged', 'cybernetic', 'khaydarin', 'twilight', 'dark', 'void', 'shielded', 'armored', 'swift', 'tactical',
  'orbital', 'enslaved', 'recalled', 'warped', 'cerebrate',
];

export const units = [
  'marine', 'firebat', 'medic', 'ghost', 'vulture', 'goliath', 'wraith', 'valkyrie', 'battlecruiser', 'dropship',
  'zealot', 'dragoon', 'archon', 'reaver', 'corsair', 'scout', 'carrier', 'arbiter', 'observer', 'shuttle',
  'probe', 'scv', 'zergling', 'hydralisk', 'mutalisk', 'ultralisk', 'lurker', 'defiler', 'guardian', 'devourer',
  'overlord', 'queen', 'drone', 'scourge', 'templar', 'interceptor', 'tank', 'broodling',
];

export const places = [
  'bunker', 'barracks', 'factory', 'starport', 'nexus', 'pylon', 'gateway', 'forge', 'cannon', 'assimilator',
  'hatchery', 'lair', 'hive', 'spire', 'extractor', 'refinery', 'academy', 'armory', 'depot', 'turret',
  'comsat', 'nydus', 'citadel', 'stargate', 'beacon', 'observatory', 'tribunal', 'aiur', 'char', 'korhal',
  'tarsonis', 'shakuras', 'zerus', 'braxis', 'bhekar',
];
