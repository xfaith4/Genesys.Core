/**
 * Accent palettes.
 *
 * A brand colour is rarely usable as-is for text. Each accent therefore ships three values,
 * following the split this repository already applies to its other surfaces: a graphical shade
 * for fills and borders (needs 3:1 per SC 1.4.11), and text-safe shades for each theme
 * (need 4.5:1 per SC 1.4.3).
 *
 * The shades are not hand-picked. Each was solved by darkening or blending the base toward the
 * relevant ink colour until it cleared 4.5:1 against the surface it is used on, then verified
 * with axe-core against the rendered application.
 */

export interface AccentPalette {
  label: string;
  /** Fills, borders, focus rings, chart marks. Never text on a light surface. */
  base: string;
  /** Filled surfaces that carry white text: primary buttons, active pills, the avatar. */
  strong: string;
  /** Accent-coloured text on a light surface. */
  textOnLight: string;
  /** Accent-coloured text on a dark surface. */
  textOnDark: string;
}

export const ACCENTS: AccentPalette[] = [
  { label: 'Ember', base: '#ff4f1f', strong: '#cf4019', textOnLight: '#bb4122', textOnDark: '#fa6f4a' },
  { label: 'Azure', base: '#2f7df6', strong: '#2a6fdb', textOnLight: '#2968c7', textOnDark: '#609bf5' },
  { label: 'Jade', base: '#19a37f', strong: '#148266', textOnLight: '#187763', textOnDark: '#33ac8e' },
  { label: 'Violet', base: '#8b5cf6', strong: '#8156e5', textOnLight: '#7651d1', textOnDark: '#a788f5' },
  { label: 'Rose', base: '#d81e5b', strong: '#d81e5b', textOnLight: '#cc1e58', textOnDark: '#df7b9f' },
];

/** The Genesys skin is fixed to the product's own orange regardless of user preference. */
export const GENESYS_ACCENT = ACCENTS[0] as AccentPalette;

export const accentFor = (base: string): AccentPalette =>
  ACCENTS.find((accent) => accent.base === base) ?? GENESYS_ACCENT;
