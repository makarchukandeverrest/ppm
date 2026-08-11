import { buildContractBidCloneName } from './contractBidCloneUtils';

const DEFAULT_RULE = {
    previewFields: ['Name'],
    requiredFields: ['Name'],
    fieldsToLoad: [],
    specialFields: [],
    deriveName: (draft, sourceValues) => draft?.Name || sourceValues?.Name || null
};

const RULES = new Map();

export function registerCloneRule(objectApiName, rule) {
    RULES.set(objectApiName, {
        ...DEFAULT_RULE,
        ...rule,
        previewFields: mergeArrays(DEFAULT_RULE.previewFields, rule.previewFields),
        requiredFields: mergeArrays(DEFAULT_RULE.requiredFields, rule.requiredFields),
        fieldsToLoad: mergeArrays(DEFAULT_RULE.fieldsToLoad, rule.fieldsToLoad),
        specialFields: mergeArrays(DEFAULT_RULE.specialFields, rule.specialFields)
    });
}

export function getCloneRule(objectApiName) {
    return RULES.get(objectApiName) || DEFAULT_RULE;
}

function mergeArrays(defaults, overrides) {
    if (!overrides || !overrides.length) {
        return [...defaults];
    }
    return [...new Set([...defaults, ...overrides])];
}

registerCloneRule('Contract_Bid__c', {
    previewFields: ['Customer__c', 'Contract_Year__c', 'Stage__c', 'Due_Date__c'],
    requiredFields: ['Customer__c', 'Contract_Year__c', 'Stage__c'],
    fieldsToLoad: ['Contract_Year__c'],
    specialFields: ['Contract_Year__c'],
    deriveName: (draft, sourceValues) => {
        const rawName = sourceValues?.Name || draft?.__sourceName;
        const contractYear = draft?.Contract_Year__c || sourceValues?.Contract_Year__c;
        return buildContractBidCloneName(rawName, contractYear);
    }
});
