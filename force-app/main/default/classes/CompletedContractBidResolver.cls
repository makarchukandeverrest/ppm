public with sharing class CompletedContractBidResolver {
    public static Map<Id, Id> resolveBidIdsByContentDocument(List<ContentVersion> versions) {
        Map<Id, Id> contentDocumentToBidId = new Map<Id, Id>();
        Set<Id> contentDocumentIds = new Set<Id>();
        Boolean needsLinkLookup = false;

        for (ContentVersion version : versions) {
            if (bidIdFromPublishLocation(version) == null && version.ContentDocumentId != null) {
                needsLinkLookup = true;
                contentDocumentIds.add(version.ContentDocumentId);
            }
        }

        if (!needsLinkLookup || contentDocumentIds.isEmpty()) {
            return contentDocumentToBidId;
        }

        for (ContentDocumentLink link : [
            SELECT ContentDocumentId, LinkedEntityId
            FROM ContentDocumentLink
            WHERE ContentDocumentId IN :contentDocumentIds
        ]) {
            if (
                link.LinkedEntityId != null &&
                link.LinkedEntityId.getSObjectType() == Contract_Bid__c.SObjectType
            ) {
                contentDocumentToBidId.put(link.ContentDocumentId, link.LinkedEntityId);
            }
        }
        return contentDocumentToBidId;
    }

    public static Set<Id> collectBidIds(List<ContentVersion> versions, Map<Id, Id> contentDocumentToBidId) {
        Set<Id> bidIds = new Set<Id>();
        for (ContentVersion version : versions) {
            Id bidId = resolveBidIdForVersion(version, contentDocumentToBidId);
            if (bidId != null) {
                bidIds.add(bidId);
            }
        }
        return bidIds;
    }

    public static Id resolveBidIdForVersion(ContentVersion version, Map<Id, Id> contentDocumentToBidId) {
        Id bidId = bidIdFromPublishLocation(version);
        if (bidId == null && version.ContentDocumentId != null) {
            bidId = contentDocumentToBidId.get(version.ContentDocumentId);
        }
        return bidId;
    }

    private static Id bidIdFromPublishLocation(ContentVersion version) {
        if (version.FirstPublishLocationId == null) {
            return null;
        }
        if (version.FirstPublishLocationId.getSObjectType() != Contract_Bid__c.SObjectType) {
            return null;
        }
        return version.FirstPublishLocationId;
    }
}
