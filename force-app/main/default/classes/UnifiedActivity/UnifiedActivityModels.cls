public class UnifiedActivityModels {
    public enum SortDirection { ASCENDING, DESCENDING }

    public class ActivityContentPart {
        @AuraEnabled public String partType;
        @AuraEnabled public String text;
        @AuraEnabled public String imageUrl;
        @AuraEnabled public Id contentDocumentId;
        @AuraEnabled public String altText;
    }

    public class ActivityPageResult {
        @AuraEnabled public List<ActivityItem> items;
        @AuraEnabled public Integer totalCount;
        @AuraEnabled public Boolean hasMore;
        @AuraEnabled public Integer nextOffset;
    }

    public class ActivityItem {
        @AuraEnabled public Id id;
        @AuraEnabled public String type;
        @AuraEnabled public String title;
        @AuraEnabled public String description;
        @AuraEnabled public List<ActivityContentPart> contentParts;
        @AuraEnabled public Datetime createdDate;
        @AuraEnabled public String createdById;
        @AuraEnabled public String createdByName;
        @AuraEnabled public String status;
        @AuraEnabled public String iconName;
        @AuraEnabled public String formattedType;
        @AuraEnabled public String sourceLabel;
        @AuraEnabled public Integer attachmentCount;

        public ActivityItem(
            Id id,
            String type,
            String title,
            String description,
            Datetime createdDate,
            Id createdById,
            String createdByName,
            String status
        ) {
            this(id, type, title, description, createdDate, createdById, createdByName, status, null, null);
        }

        public ActivityItem(
            Id id,
            String type,
            String title,
            String description,
            Datetime createdDate,
            Id createdById,
            String createdByName,
            String status,
            List<ActivityContentPart> contentParts
        ) {
            this(id, type, title, description, createdDate, createdById, createdByName, status, contentParts, null);
        }

        public ActivityItem(
            Id id,
            String type,
            String title,
            String description,
            Datetime createdDate,
            Id createdById,
            String createdByName,
            String status,
            List<ActivityContentPart> contentParts,
            String sourceLabel
        ) {
            this.id = id;
            this.type = type;
            this.title = title;
            this.description = description;
            this.contentParts = contentParts != null ? contentParts : new List<ActivityContentPart>();
            this.createdDate = createdDate;
            this.createdById = createdById;
            this.createdByName = createdByName;
            this.status = status;
            this.sourceLabel = sourceLabel;
            this.attachmentCount = 0;
            this.iconName = UnifiedActivityUtils.iconNameFor(type);
            this.formattedType = UnifiedActivityUtils.formattedTypeFor(type);
        }
    }

    public class ActivityItemComparator implements Comparator<ActivityItem> {
        private final SortDirection direction;

        public ActivityItemComparator(SortDirection direction) {
            this.direction = direction;
        }

        public Integer compare(ActivityItem a, ActivityItem b) {
            if (a.createdDate == null && b.createdDate == null) {
                return 0;
            }
            if (a.createdDate == null) {
                return 1;
            }
            if (b.createdDate == null) {
                return -1;
            }
            Integer multiplier = (direction == SortDirection.ASCENDING) ? 1 : -1;
            return multiplier * (a.createdDate > b.createdDate ? 1 : (a.createdDate < b.createdDate ? -1 : 0));
        }
    }
}
