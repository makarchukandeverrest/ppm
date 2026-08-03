const YEAR_RANGE_COMPACT = /[0-9]{4}-[0-9]{4}$/;
const YEAR_RANGE_SPACED = /[0-9]{4} - [0-9]{4}$/;

export const CONTRACT_BID_OBJECT = 'Contract_Bid__c';

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

/**
 * Mirrors Contract_Bid_Regional_Manager_Fill_on_Creation Worksheet_Integration_Key_Formula
 * for clone Name prefill on Contract Bid mass clone.
 */
export function buildContractBidCloneName(name, contractYear) {
    if (!contractYear) {
        return name;
    }

    const baseName = stripTrailingContractYearFromName(name);
    const formattedYear = formatContractYearForName(contractYear);

    return `${baseName} ${formattedYear}`.trim();
}
