public class UnifiedActivityUtils {
    private static final Integer DEFAULT_PAGE_SIZE = 20;

    public static String iconNameFor(String type) {
        switch on type {
            when 'Task' { return 'standard:task'; }
            when 'Event' { return 'standard:event'; }
            when 'EmailMessage' { return 'standard:email'; }
            when 'FeedItem' { return 'standard:feed'; }
            when else { return 'standard:default'; }
        }
    }

    public static String formattedTypeFor(String type) {
        switch on type {
            when 'Task' { return 'Task'; }
            when 'Event' { return 'Event'; }
            when 'EmailMessage' { return 'Email'; }
            when 'FeedItem' { return 'Chatter'; }
            when else { return type; }
        }
    }

    public static UnifiedActivityModels.SortDirection parseSortDirection(String value) {
        if (String.isBlank(value)) {
            return UnifiedActivityModels.SortDirection.DESCENDING;
        }
        String v = value.toUpperCase();
        if (v == 'ASC' || v == 'ASCENDING') {
            return UnifiedActivityModels.SortDirection.ASCENDING;
        }
        return UnifiedActivityModels.SortDirection.DESCENDING;
    }

    public static Integer normalizePageSize(Integer pageSize) {
        if (pageSize == null || pageSize < 1) {
            return DEFAULT_PAGE_SIZE;
        }
        return pageSize;
    }

    public static void sortItems(List<UnifiedActivityModels.ActivityItem> items, UnifiedActivityModels.SortDirection direction) {
        items.sort(new UnifiedActivityModels.ActivityItemComparator(direction));
    }

    public static List<UnifiedActivityModels.ActivityItem> applyFilters(
        List<UnifiedActivityModels.ActivityItem> items,
        String activityType,
        String searchTerm
    ) {
        String typeFilter = String.isBlank(activityType) || activityType == 'All' ? null : activityType;
        String term = String.isBlank(searchTerm) ? null : searchTerm.trim().toLowerCase();
        if (typeFilter == null && term == null) {
            return items;
        }

        List<UnifiedActivityModels.ActivityItem> filteredItems = new List<UnifiedActivityModels.ActivityItem>();
        for (UnifiedActivityModels.ActivityItem item : items) {
            if (typeFilter != null && item.type != typeFilter) {
                continue;
            }
            if (term != null && !matchesSearch(item, term)) {
                continue;
            }
            filteredItems.add(item);
        }
        return filteredItems;
    }

    private static Boolean matchesSearch(UnifiedActivityModels.ActivityItem item, String term) {
        return (item.title != null && item.title.toLowerCase().contains(term))
            || (item.description != null && item.description.toLowerCase().contains(term))
            || (item.createdByName != null && item.createdByName.toLowerCase().contains(term))
            || (item.sourceLabel != null && item.sourceLabel.toLowerCase().contains(term));
    }

    public static UnifiedActivityModels.ActivityPageResult paginate(List<UnifiedActivityModels.ActivityItem> items, Integer pageSize, Integer offset) {
        UnifiedActivityModels.ActivityPageResult result = new UnifiedActivityModels.ActivityPageResult();
        result.totalCount = items.size();
        result.items = new List<UnifiedActivityModels.ActivityItem>();

        if (offset >= items.size()) {
            result.hasMore = false;
            result.nextOffset = offset;
            return result;
        }

        Integer endIndex = Math.min(offset + pageSize, items.size());
        for (Integer index = offset; index < endIndex; index++) {
            result.items.add(items[index]);
        }

        result.hasMore = endIndex < items.size();
        result.nextOffset = endIndex;
        return result;
    }

    public static String formatFieldLabel(String fieldName) {
        if (fieldName.endsWith('__c')) {
            return fieldName.removeEnd('__c').replace('_', ' ');
        }
        if (fieldName.endsWith('Id')) {
            return fieldName.removeEnd('Id');
        }
        return fieldName;
    }

    public static String formatFieldApiName(String fieldName) {
        if (String.isBlank(fieldName)) {
            return fieldName;
        }
        String label = fieldName.endsWith('__c')
            ? fieldName.substring(0, fieldName.length() - 3)
            : fieldName;
        return label.replace('_', ' ');
    }

    public static String escapeHtml(String text) {
        if (text == null) {
            return '';
        }
        return text.replace('&', '&amp;')
            .replace('<', '&lt;')
            .replace('>', '&gt;')
            .replace('"', '&quot;')
            .replace('\'', '&#39;');
    }

    public static String unescapeHtmlAttribute(String value) {
        if (String.isBlank(value)) {
            return value;
        }
        String amp = String.fromCharArray(new List<Integer>{ 38 });
        value = value.replace(amp + 'amp;', amp);
        value = value.replace(amp + 'quot;', '"');
        value = value.replace(amp + '#39;', String.fromCharArray(new List<Integer>{ 39 }));
        value = value.replace(amp + 'lt;', '<');
        value = value.replace(amp + 'gt;', '>');
        return value;
    }

    public static String stripHtmlToPlainText(String htmlFragment) {
        if (String.isBlank(htmlFragment)) {
            return '';
        }

        String text = htmlFragment.replaceAll('<br\\s*/?>', '\n');
        text = text.replaceAll('</p\\s*>', '\n');
        text = text.replaceAll('<[^>]+>', '');
        text = unescapeHtmlAttribute(text);
        text = text.replace('\u00a0', ' ').trim();
        return text;
    }

    public static Boolean isBlankRichText(String body) {
        if (String.isBlank(body)) {
            return true;
        }
        String stripped = body.replaceAll('<[^>]+>', '');
        stripped = stripped.replace('&nbsp;', ' ').trim();
        return String.isBlank(stripped);
    }

    public static Boolean isRichTextBody(String body) {
        return String.isNotBlank(body) && body.contains('<') && body.contains('>');
    }

    public static Boolean containsInlineImageReference(String body) {
        if (String.isBlank(body)) {
            return false;
        }
        if (body.toLowerCase().contains('<img')) {
            return true;
        }
        Pattern uuidPattern = Pattern.compile(
            '[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}'
        );
        return uuidPattern.matcher(body).find();
    }

    public static Boolean containsInlineHtmlImage(String body) {
        return String.isNotBlank(body) && body.toLowerCase().contains('<img');
    }

    public static String buildPlainTextFromParts(List<UnifiedActivityModels.ActivityContentPart> parts, String fallback) {
        if (parts == null || parts.isEmpty()) {
            return fallback;
        }
        List<String> values = new List<String>();
        for (UnifiedActivityModels.ActivityContentPart part : parts) {
            if (part.partType == 'text' && String.isNotBlank(part.text)) {
                values.add(part.text);
            } else if (part.partType == 'image' && String.isNotBlank(part.altText)) {
                values.add(part.altText);
            }
        }
        return values.isEmpty() ? fallback : String.join(values, ' ');
    }

    public static String resolveSourceLabel(Id primaryId, Id secondaryId, Map<Id, String> recordLabels) {
        if (primaryId != null && recordLabels.containsKey(primaryId)) {
            return recordLabels.get(primaryId);
        }
        if (secondaryId != null && recordLabels.containsKey(secondaryId)) {
            return recordLabels.get(secondaryId);
        }
        return null;
    }
}
