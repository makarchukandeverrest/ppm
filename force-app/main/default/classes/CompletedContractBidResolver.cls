public with sharing class CompletedContractBidResolver {
    private static final Schema.SObjectType BID_SOBJECT_TYPE = Contract_Bid__c.SObjectType;
    private static final Schema.SObjectType PROPOSAL_SOBJECT_TYPE = Opportunity.SObjectType;

    public static Map<Id, Id> resolveBidIdsByContentDocument(List<ContentVersion> versions) {
        return resolveLinkedRecordIdsByContentDocument(versions, BID_SOBJECT_TYPE);
    }

    public static Set<Id> collectBidIds(List<ContentVersion> versions, Map<Id, Id> contentDocumentToBidId) {
        return collectLinkedRecordIds(versions, contentDocumentToBidId, BID_SOBJECT_TYPE);
    }

    public static Id resolveBidIdForVersion(ContentVersion version, Map<Id, Id> contentDocumentToBidId) {
        return resolveLinkedRecordIdForVersion(version, contentDocumentToBidId, BID_SOBJECT_TYPE);
    }

    public static Map<Id, Id> resolveProposalIdsByContentDocument(List<ContentVersion> versions) {
        return resolveLinkedRecordIdsByContentDocument(versions, PROPOSAL_SOBJECT_TYPE);
    }

    public static Set<Id> collectProposalIds(List<ContentVersion> versions, Map<Id, Id> contentDocumentToProposalId) {
        return collectLinkedRecordIds(versions, contentDocumentToProposalId, PROPOSAL_SOBJECT_TYPE);
    }

    public static Id resolveProposalIdForVersion(ContentVersion version, Map<Id, Id> contentDocumentToProposalId) {
        return resolveLinkedRecordIdForVersion(version, contentDocumentToProposalId, PROPOSAL_SOBJECT_TYPE);
    }

    private static Map<Id, Id> resolveLinkedRecordIdsByContentDocument(
        List<ContentVersion> versions,
        Schema.SObjectType targetType
    ) {
        Map<Id, Id> contentDocumentToRecordId = new Map<Id, Id>();
        Set<Id> contentDocumentIds = new Set<Id>();

        for (ContentVersion version : versions) {
            if (recordIdFromPublishLocation(version, targetType) == null && version.ContentDocumentId != null) {
                contentDocumentIds.add(version.ContentDocumentId);
            }
        }

        if (contentDocumentIds.isEmpty()) {
            return contentDocumentToRecordId;
        }

        for (ContentDocumentLink link : [
            SELECT ContentDocumentId, LinkedEntityId
            FROM ContentDocumentLink
            WHERE ContentDocumentId IN :contentDocumentIds
        ]) {
            if (
                link.LinkedEntityId != null &&
                link.LinkedEntityId.getSObjectType() == targetType
            ) {
                contentDocumentToRecordId.put(link.ContentDocumentId, link.LinkedEntityId);
            }
        }
        return contentDocumentToRecordId;
    }

    private static Set<Id> collectLinkedRecordIds(
        List<ContentVersion> versions,
        Map<Id, Id> contentDocumentToRecordId,
        Schema.SObjectType targetType
    ) {
        Set<Id> recordIds = new Set<Id>();
        for (ContentVersion version : versions) {
            Id recordId = resolveLinkedRecordIdForVersion(version, contentDocumentToRecordId, targetType);
            if (recordId != null) {
                recordIds.add(recordId);
            }
        }
        return recordIds;
    }

    private static Id resolveLinkedRecordIdForVersion(
        ContentVersion version,
        Map<Id, Id> contentDocumentToRecordId,
        Schema.SObjectType targetType
    ) {
        Id recordId = recordIdFromPublishLocation(version, targetType);
        if (recordId == null && version.ContentDocumentId != null) {
            recordId = contentDocumentToRecordId.get(version.ContentDocumentId);
        }
        return recordId;
    }

    private static Id recordIdFromPublishLocation(ContentVersion version, Schema.SObjectType targetType) {
        if (version.FirstPublishLocationId == null) {
            return null;
        }
        if (version.FirstPublishLocationId.getSObjectType() != targetType) {
            return null;
        }
        return version.FirstPublishLocationId;
    }
}
