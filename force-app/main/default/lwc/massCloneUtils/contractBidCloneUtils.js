const YEAR_RANGE_COMPACT = /[0-9]{4}-[0-9]{4}$/;
const YEAR_RANGE_SPACED = /[0-9]{4} - [0-9]{4}$/;

export function stripTrailingContractYearFromName(name) {
    if (!name) {
        return name;
    }

    if (name.length >= 9 && YEAR_RANGE_COMPACT.test(name.slice(-9))) {
        return name.slice(0, name.length - 9).trim();
    }

    if (name.length >= 11 && YEAR_RANGE_SPACED.test(name.slice(-11))) {
        return name.slice(0, name.length - 11).trim();
    }

    return name.trim();
}

export function formatContractYearForName(contractYear) {
    if (!contractYear) {
        return '';
    }

    return String(contractYear).replace(/-/g, ' - ');
}

export function buildContractBidCloneName(name, contractYear) {
    if (!name) {
        return null;
    }

    if (!contractYear) {
        return name;
    }

    const baseName = stripTrailingContractYearFromName(name);
    const formattedYear = formatContractYearForName(contractYear);

    return `${baseName} ${formattedYear}`.trim();
}
