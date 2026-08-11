public with sharing class MassClonePayload {
    public class ParseException extends Exception {
    }

    public class Item {
        public String sourceId;
        public String sourceName;
        public Map<String, Object> fields;

        public Boolean hasFields() {
            return fields != null && !fields.isEmpty();
        }

        public String getLabel(Integer index) {
            if (String.isNotBlank(sourceName)) {
                return sourceName;
            }
            if (String.isNotBlank(sourceId)) {
                return sourceId;
            }
            return 'Record ' + (index + 1);
        }
    }

    public static List<Item> parse(String clonePayloadJson) {
        if (String.isBlank(clonePayloadJson)) {
            throw new ParseException('Clone payload JSON is required.');
        }

        List<Object> rawItems;
        try {
            rawItems = (List<Object>) JSON.deserializeUntyped(clonePayloadJson);
        } catch (Exception ex) {
            throw new ParseException('Invalid clone payload JSON: ' + ex.getMessage());
        }

        List<Item> items = new List<Item>();
        if (rawItems == null) {
            return items;
        }

        for (Integer index = 0; index < rawItems.size(); index++) {
            items.add(toItem(rawItems[index], index));
        }

        return items;
    }

    private static Item toItem(Object rawItem, Integer index) {
        if (!(rawItem instanceof Map<String, Object>)) {
            throw new ParseException('Invalid clone payload JSON: entry ' + (index + 1) + ' is not an object.');
        }

        Map<String, Object> raw = (Map<String, Object>) rawItem;
        Object rawFields = raw.get('fields');

        Item item = new Item();
        item.sourceId = toStringValue(raw.get('sourceId'));
        item.sourceName = toStringValue(raw.get('sourceName'));
        item.fields = rawFields instanceof Map<String, Object> ? (Map<String, Object>) rawFields : null;

        return item;
    }

    private static String toStringValue(Object value) {
        return value == null ? null : String.valueOf(value);
    }
}
