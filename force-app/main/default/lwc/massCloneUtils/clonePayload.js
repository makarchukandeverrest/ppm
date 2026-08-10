import { getCloneRule } from './cloneRules';
import { formatValue } from './fieldFormat';

export function parsePayload(clonePayloadJson) {
    if (!clonePayloadJson) {
        return [];
    }

    try {
        const payloads = JSON.parse(clonePayloadJson);
        return Array.isArray(payloads) ? payloads : [];
    } catch (error) {
        return [];
    }
}

export function buildReviewRows(clonePayloadJson, objectApiName) {
    const payloads = parsePayload(clonePayloadJson);
    const previewFields = getCloneRule(objectApiName).previewFields;

    return payloads.map((payload, index) => {
        const fields = payload.fields || {};
        const previewValues = previewFields
            .filter((fieldName) => Object.prototype.hasOwnProperty.call(fields, fieldName))
            .map((fieldName) => ({
                key: `${index}-${fieldName}`,
                label: fieldName,
                value: formatValue(fields[fieldName])
            }));

        return {
            id: payload.sourceId || `row-${index}`,
            rowNumber: index + 1,
            sourceName: payload.sourceName || payload.sourceId || `Record ${index + 1}`,
            newName: fields.Name || '—',
            fieldCount: Object.keys(fields).length,
            previewValues,
            hasPreviewValues: previewValues.length > 0
        };
    });
}

export function buildReviewSummary(rowCount) {
    return `${rowCount} record(s) ready to create.`;
}
