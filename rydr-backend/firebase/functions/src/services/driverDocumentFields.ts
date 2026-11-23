export type DriverProofKind = "driverLicense" | "insurance" | "registration";

export type ExtractedFields = {
  documentType?: string;
  name?: string;
  dateOfBirth?: string;
  licenseNumber?: string;
  state?: string;
  licenseClass?: string;
  issuanceDate?: string;
  expirationDate?: string;
  effectiveDate?: string;
  insurancePolicyNumber?: string;
  policyholderFirstName?: string;
  policyholderLastName?: string;
  vin?: string;
  plateNumber?: string;
  vehicleMake?: string;
  vehicleModel?: string;
  vehicleYear?: string;
};

const states = Object.entries({
  AL: "Alabama", AK: "Alaska", AZ: "Arizona", AR: "Arkansas", CA: "California", CO: "Colorado",
  CT: "Connecticut", DE: "Delaware", DC: "District of Columbia", FL: "Florida", GA: "Georgia",
  HI: "Hawaii", ID: "Idaho", IL: "Illinois", IN: "Indiana", IA: "Iowa", KS: "Kansas", KY: "Kentucky",
  LA: "Louisiana", ME: "Maine", MD: "Maryland", MA: "Massachusetts", MI: "Michigan", MN: "Minnesota",
  MS: "Mississippi", MO: "Missouri", MT: "Montana", NE: "Nebraska", NV: "Nevada", NH: "New Hampshire",
  NJ: "New Jersey", NM: "New Mexico", NY: "New York", NC: "North Carolina", ND: "North Dakota",
  OH: "Ohio", OK: "Oklahoma", OR: "Oregon", PA: "Pennsylvania", RI: "Rhode Island",
  SC: "South Carolina", SD: "South Dakota", TN: "Tennessee", TX: "Texas", UT: "Utah", VT: "Vermont",
  VA: "Virginia", WA: "Washington", WV: "West Virginia", WI: "Wisconsin", WY: "Wyoming"
});

const licenseTitle = /\b(?:commercial\s+)?driver(?:['’]s|s)?\s+licen[cs]e\b/i;
const dateValue = /\d{4}[-/.]\d{1,2}[-/.]\d{1,2}|\d{1,2}[-/.]\d{1,2}[-/.](?:\d{4}|\d{2})|[A-Z]{3,9}\s+\d{1,2},?\s+\d{4}/;
const personValue = /[\p{L}][\p{L}.'’\-]*(?:[ \t]+[\p{L}][\p{L}.'’\-]*)*(?:,[ \t]*[\p{L}][\p{L}.'’\-]*(?:[ \t]+[\p{L}][\p{L}.'’\-]*)*)?/u;

function escapeRegex(value: string): string {
  return value.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

function unique(values: string[]): string | undefined {
  return new Set(values.map(value => value.toUpperCase())).size === 1 ? values[0] : undefined;
}

// Accept a value next to its label or on the following OCR line. The value
// must end at a token boundary, and an unrelated field can't supply its value.
function labeled(text: string, label: string, value: RegExp, valid = (_value: string) => true): string | undefined {
  const pattern = new RegExp(
    `(?<![\\p{L}\\p{N}])(?:${label})(?![\\p{L}\\p{N}])[ \\t]*[:#.]?[ \\t]*(?:\\n[ \\t]*)?(${value.source})(?![\\p{L}\\p{N}/-])`,
    "gimu"
  );
  return unique(Array.from(text.matchAll(pattern), match => match[1].trim()).filter(valid));
}

export function parseProofDate(raw: string | undefined): string | undefined {
  if (!raw) return undefined;
  const value = raw.trim();
  const iso = value.match(/^(\d{4})[-/.](\d{1,2})[-/.](\d{1,2})$/);
  const numeric = value.match(/^(\d{1,2})[-/.](\d{1,2})[-/.](\d{2}|\d{4})$/);
  const named = value.match(/^([A-Z]{3,9})\s+(\d{1,2}),?\s+(\d{4})$/i);
  const months = "january february march april may june july august september october november december".split(" ");
  const month = iso ? Number(iso[2]) : numeric ? Number(numeric[1]) : named
    ? months.findIndex(name => [name, name.slice(0, 3)].includes(named[1].toLowerCase())) + 1
    : 0;
  const day = Number(iso?.[3] ?? numeric?.[2] ?? named?.[2]);
  const yearText = iso?.[1] ?? numeric?.[3] ?? named?.[3];
  if (!yearText || !month || !day) return undefined;
  const yearValue = Number(yearText);
  const year = yearText.length === 2 ? (yearValue >= 70 ? 1900 : 2000) + yearValue : yearValue;
  const date = new Date(Date.UTC(year, month - 1, day));
  if (date.getUTCFullYear() !== year || date.getUTCMonth() + 1 !== month || date.getUTCDate() !== day) return undefined;
  return date.toISOString().slice(0, 10);
}

function labeledDate(text: string, label: string): string | undefined {
  return parseProofDate(labeled(text, label, dateValue, value => Boolean(parseProofDate(value))));
}

function issuingState(text: string): string | undefined {
  const title = licenseTitle.exec(text);
  if (!title) return undefined;
  const context = text.slice(0, title.index + title[0].length).split("\n").slice(-3).join(" ");
  const beforeTitle = context.slice(0, context.search(licenseTitle)).trim();
  const stateNames = states.filter(([, name]) => new RegExp(`(?:^|[^A-Z])${escapeRegex(name)}(?=$|[^A-Z])`, "i").test(beforeTitle));
  if (stateNames.length === 1) return stateNames[0][0];
  const codes = states.map(([code]) => code).join("|");
  const headerCode = text.slice(0, title.index).trimEnd().split("\n").at(-1)
    ?.match(new RegExp(`^[ \\t]*(?:state of +)?(${codes})[ .|:-]*$`, "i"))?.[1];
  const labeledIssuer = labeled(text, "issuing[ \\t]+(?:state|jurisdiction)|state[ \\t]+of[ \\t]+issuance", new RegExp(states.map(([, name]) => escapeRegex(name)).concat(codes.split("|")).join("|")));
  const issuer = headerCode ?? labeledIssuer;
  return states.find(([code, name]) => [code, name.toUpperCase()].includes(issuer?.toUpperCase() ?? ""))?.[0];
}

function identifiedPerson(value: string): boolean {
  return !/\b(?:effective|expiration|policy|coverage|insurance|vehicle|date|class|address|information)\b/i.test(value);
}

function policyholder(text: string): Pick<ExtractedFields, "policyholderFirstName" | "policyholderLastName"> {
  const first = labeled(text, "(?:policyholder|insured)[ \\t]+first[ \\t]+name", /[\p{L}][\p{L}.'’\-]*/u, identifiedPerson);
  const last = labeled(text, "(?:policyholder|insured)[ \\t]+last[ \\t]+name", /[\p{L}][\p{L}.'’\-]*/u, identifiedPerson);
  if (first || last) return { policyholderFirstName: first, policyholderLastName: last };
  const label = "(?:named[ \\t]+insured(?:\\(s\\))?|name[ \\t]+of[ \\t]+insured|insured(?:[ \\t]+name)?|policy[ \\t]*holder(?:[ \\t]+name)?)";
  const name = labeled(text, label, personValue, identifiedPerson)
    ?? labeled(text, `${label}[: \\t]*\\n[ \\t]*effective[ \\t]+date[: \\t]*\\n[ \\t]*(?:${dateValue.source})`, personValue, identifiedPerson);
  if (!name) return {};
  const reversed = name.split(",").map(part => part.trim());
  const names = name.trim().split(/\s+/);
  return reversed.length === 2
    ? { policyholderFirstName: reversed[1].split(/\s+/)[0], policyholderLastName: reversed[0] }
    : names.length >= 2 ? { policyholderFirstName: names[0], policyholderLastName: names.at(-1) } : {};
}

const makeAliases: Record<string, string> = {
  CHEV: "CHEVROLET", CHEVY: "CHEVROLET", CHRY: "CHRYSLER", HOND: "HONDA",
  HYUN: "HYUNDAI", MBEN: "MERCEDESBENZ", MERCEDES: "MERCEDESBENZ", NISS: "NISSAN",
  SUBA: "SUBARU", TOYT: "TOYOTA", VOLK: "VOLKSWAGEN", VW: "VOLKSWAGEN"
};

export function vehicleToken(value: string | undefined | null): string {
  return (value ?? "").toUpperCase().replace(/[^A-Z0-9]/g, "");
}

export function vehicleMakeToken(value: string | undefined | null): string {
  const token = vehicleToken(value);
  return makeAliases[token] ?? token;
}

function vehicleFields(text: string, expectedVehicle?: { make?: string | null; model?: string | null; year?: string | null }) {
  const vin = unique(text.match(/\b[A-HJ-NPR-Z0-9]{17}\b/gi)?.filter(value => /\d/.test(value)) ?? []);
  // Adjacent year/make/model tables can be flattened by OCR. In that case
  // corroborate the profile values in the same printed vehicle row.
  const expectedYear = expectedVehicle?.year;
  const vehicleRow = expectedYear && expectedVehicle?.make && expectedVehicle?.model
    ? text.split("\n").find(line => new RegExp(`\\b${escapeRegex(expectedYear)}\\b`).test(line)
      && lineMatchesVehicle(line, expectedVehicle.make!, expectedVehicle.model!))
    : undefined;
  return {
    vin: vin?.toUpperCase(),
    vehicleMake: labeled(text, "(?:vehicle[ \\t]+)?(?:make|mfr)", /[A-Z][A-Z-]*(?:[ \t]+(?:BENZ|ROVER|MARTIN|ROMEO))?/i, value => !/^(?:model|year|vehicle|date)$/i.test(value))
      ?? (vehicleRow ? expectedVehicle?.make ?? undefined : undefined),
    vehicleModel: labeled(text, "(?:vehicle[ \\t]+)?model(?![ \\t]+year)", /[A-Z0-9][A-Z0-9-]*(?:[ \t]+[A-Z0-9][A-Z0-9-]*)*/i, value => !/\b(?:year|make|vin|date|color|fuel)\b/i.test(value))
      ?? (vehicleRow ? expectedVehicle?.model ?? undefined : undefined),
    vehicleYear: labeled(text, "(?:vehicle[ \\t]+year|model[ \\t]+year|year|yr)", /(?:19|20)\d{2}/)
      ?? (vehicleRow ? expectedYear ?? undefined : undefined)
  };
}

function lineMatchesVehicle(line: string, make: string, model: string): boolean {
  const canonicalMake = vehicleMakeToken(make);
  const names = [make, ...Object.keys(makeAliases).filter(alias => makeAliases[alias] === canonicalMake)];
  return names.some(name => new RegExp(`\\b${escapeRegex(name)}\\b`, "i").test(line))
    && new RegExp(`\\b${escapeRegex(model)}\\b`, "i").test(line);
}

export function extractDriverProofFields(
  kind: DriverProofKind,
  rawText: string,
  expectedVehicle?: { make?: string | null; model?: string | null; year?: string | null }
): ExtractedFields {
  const text = rawText.replace(/\r\n?/g, "\n").replace(/\u00a0/g, " ");
  const expiry = "expiration(?:\\s+date)?|expires(?:[ \\t]+on)?|exp(?:[. \\t]+date)?|valid[ \\t]+(?:until|through)";
  let fields: ExtractedFields;
  if (kind === "driverLicense") {
    const first = labeled(text, "first[ \\t]+name|given[ \\t]+names?|^[ \\t]*2(?=[ \\t])", personValue, identifiedPerson);
    const last = labeled(text, "last[ \\t]+name|surname|^[ \\t]*1(?=[ \\t])", personValue, identifiedPerson);
    fields = {
      documentType: licenseTitle.test(text) ? kind : undefined,
      name: first && last ? `${first} ${last}` : labeled(text, "^[ \\t]*(?:full[ \\t]+)?name", personValue, identifiedPerson),
      dateOfBirth: labeledDate(text, "date[ \\t]+of[ \\t]+birth|dob|birth[ \\t]+date"),
      licenseNumber: labeled(text, "(?:driver(?:['’]s|s)?[ \\t]+)?license[ \\t]+(?:number|no\\.?)|lic[ \\t]+(?:no\\.?|#)|d[.]?l[.]?[ \\t]*(?:no\\.?|number|#)|^[ \\t]*4d[ \\t]+(?:dl[ \\t]*)?", /[A-Z0-9][A-Z0-9-]{4,24}/i, value => /\d/.test(value)),
      state: issuingState(text),
      licenseClass: labeled(text, "(?:license[ \\t]+)?class", /[A-Z][0-9]?/i)?.toUpperCase(),
      issuanceDate: labeledDate(text, "issu(?:ance|e)[ \\t]+date|issued(?:[ \\t]+on)?|iss|4a")
        ?? labeledDate(text, "4a[ \\t]+[I1(]SS[ \\t]*\\n[ \\t]*NONE"),
      expirationDate: labeledDate(text, `${expiry}|4b`)
    };
  } else if (kind === "insurance") {
    const period = text.match(new RegExp(`(?:policy|coverage)[ \\t]+(?:period|term)[: \\t]*\\s*(${dateValue.source})\\s*(?:to|through|[–—-])\\s*(${dateValue.source})`, "i"));
    fields = {
      documentType: /\b(?:insurance\s+(?:identification|id|card|policy)|proof\s+of\s+insurance|(?:auto(?:mobile)?|vehicle|liability)\s+insurance|policy\s+(?:number|no\.?|#))\b/i.test(text)
        && !/\b(?:motor\s+vehicle\s+registration|certificate\s+of\s+registration)\b/i.test(text) ? kind : undefined,
      insurancePolicyNumber: labeled(text, "(?:insurance[ \\t]+)?policy\\s*(?:number|no\\.?|#)|^[ \\t]*policy", /[A-Z0-9][A-Z0-9-]{4,29}/i, value => /\d/.test(value)),
      effectiveDate: labeledDate(text, "(?:(?:policy|coverage)[ \\t]+)?(?:effective(?:\\s+date)?|start[ \\t]+date|begins|original[ \\t]+issue[ \\t]+date)") ?? parseProofDate(period?.[1]),
      expirationDate: labeledDate(text, `${expiry}|end[ \\t]+date|policy[ \\t]+ends`) ?? parseProofDate(period?.[2]),
      ...policyholder(text),
      ...vehicleFields(text, expectedVehicle)
    };
  } else {
    fields = {
      documentType: /\b(?:vehicle\s+registration|registration\s+(?:card|certificate|receipt)|certificate\s+of\s+registration)\b/i.test(text) ? kind : undefined,
      expirationDate: labeledDate(text, `${expiry}|registration[ \\t]+(?:end[ \\t]+date|valid[ \\t]+through)`),
      ...vehicleFields(text, expectedVehicle)
    };
  }
  return Object.fromEntries(Object.entries(fields).filter(([, value]) => value !== undefined));
}
