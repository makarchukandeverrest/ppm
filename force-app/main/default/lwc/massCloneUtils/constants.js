export const SYSTEM_FIELDS = new Set([
    'CreatedById',
    'CreatedDate',
    'LastModifiedById',
    'LastModifiedDate',
    'SystemModstamp',
    'IsDeleted'
]);

export const TEMPLATE_RECORD_ID = '__bulk_template__';

export const BULK_APPLY_EXCLUDED_FIELDS = new Set(['Name']);

export const MAX_FIELDS_PER_LOAD = 60;

export const STEP_EDIT = 'edit';
export const STEP_REVIEW = 'review';
