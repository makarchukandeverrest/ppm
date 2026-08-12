public with sharing class SObjectFieldConverter {
    public class ConversionException extends Exception {
    }

    private static final Set<Schema.DisplayType> TEXT_TYPES = new Set<Schema.DisplayType>{
        Schema.DisplayType.String,
        Schema.DisplayType.TextArea,
        Schema.DisplayType.Email,
        Schema.DisplayType.Phone,
        Schema.DisplayType.URL,
        Schema.DisplayType.EncryptedString,
        Schema.DisplayType.Picklist,
        Schema.DisplayType.MultiPicklist,
        Schema.DisplayType.ComboBox
    };

    public static Object convert(Object value, Schema.DescribeFieldResult describe) {
        if (value == null || describe == null) {
            return null;
        }

        Schema.DisplayType fieldType = describe.getType();
        Boolean isBlankText = value instanceof String && String.isBlank((String) value);

        if (isBlankText && !TEXT_TYPES.contains(fieldType)) {
            return null;
        }

        try {
            return convertByType(value, fieldType);
        } catch (ConversionException ex) {
            throw ex;
        } catch (Exception ex) {
            throw new ConversionException(
                describe.getLabel() + ': "' + String.valueOf(value) + '" is not a valid ' + fieldType.name() + ' value.'
            );
        }
    }

    private static Object convertByType(Object value, Schema.DisplayType fieldType) {
        if (fieldType == Schema.DisplayType.Date) {
            return value instanceof Date ? value : Date.valueOf(String.valueOf(value));
        }

        if (fieldType == Schema.DisplayType.DateTime) {
            if (value instanceof Datetime) {
                return value;
            }
            return (Datetime) JSON.deserialize('"' + String.valueOf(value) + '"', Datetime.class);
        }

        if (fieldType == Schema.DisplayType.Time) {
            return parseTime(value);
        }

        if (fieldType == Schema.DisplayType.Boolean) {
            return value instanceof Boolean ? value : Boolean.valueOf(String.valueOf(value));
        }

        if (
            fieldType == Schema.DisplayType.Double ||
            fieldType == Schema.DisplayType.Currency ||
            fieldType == Schema.DisplayType.Percent
        ) {
            return value instanceof Decimal ? value : Decimal.valueOf(String.valueOf(value));
        }

        if (fieldType == Schema.DisplayType.Integer) {
            return value instanceof Integer ? value : Integer.valueOf(String.valueOf(value));
        }

        if (fieldType == Schema.DisplayType.Long) {
            return value instanceof Long ? value : Long.valueOf(String.valueOf(value));
        }

        if (fieldType == Schema.DisplayType.Reference || fieldType == Schema.DisplayType.Id) {
            return Id.valueOf(String.valueOf(value).trim());
        }

        if (TEXT_TYPES.contains(fieldType)) {
            return String.valueOf(value);
        }

        return value;
    }

    public static Time parseTime(Object value) {
        if (value == null) {
            return null;
        }

        if (value instanceof Time) {
            return (Time) value;
        }

        if (value instanceof Integer || value instanceof Long || value instanceof Decimal) {
            return timeFromMilliseconds(Long.valueOf(String.valueOf(value)));
        }

        String timeValue = String.valueOf(value).trim();
        if (String.isBlank(timeValue)) {
            return null;
        }

        return parseTimeString(timeValue);
    }

    private static Time timeFromMilliseconds(Long totalMilliseconds) {
        Long totalSeconds = totalMilliseconds / 1000;
        return Time.newInstance(
            (Integer) (totalSeconds / 3600),
            (Integer) Math.mod(totalSeconds / 60, 60),
            (Integer) Math.mod(totalSeconds, 60),
            (Integer) Math.mod(totalMilliseconds, 1000)
        );
    }

    private static Time parseTimeString(String timeValue) {
        String normalized = timeValue.endsWith('Z')
            ? timeValue.substring(0, timeValue.length() - 1)
            : timeValue;

        Integer timeSeparatorIndex = normalized.indexOf('T');
        if (timeSeparatorIndex >= 0) {
            normalized = normalized.substring(timeSeparatorIndex + 1);
        }

        List<String> parts = normalized.split(':');
        if (parts.size() < 2) {
            throw new ConversionException('"' + timeValue + '" is not a valid time value.');
        }

        Integer hour = Integer.valueOf(parts[0]);
        Integer minute = Integer.valueOf(parts[1]);
        Integer second = 0;
        Integer millisecond = 0;

        if (parts.size() >= 3) {
            String secondPart = parts[2];
            if (secondPart.contains('.')) {
                List<String> secondParts = secondPart.split('\\.');
                second = Integer.valueOf(secondParts[0]);
                millisecond = Integer.valueOf(padMilliseconds(secondParts[1]));
            } else {
                second = Integer.valueOf(secondPart);
            }
        }

        return Time.newInstance(hour, minute, second, millisecond);
    }

    private static String padMilliseconds(String millisecondPart) {
        String padded = millisecondPart.length() > 3
            ? millisecondPart.substring(0, 3)
            : millisecondPart;

        return padded.rightPad(3, '0');
    }
}
