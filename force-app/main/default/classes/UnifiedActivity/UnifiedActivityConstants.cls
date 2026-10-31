public class UnifiedActivityConstants {
  public static final String TYPE_TASK = 'Task';
  public static final String TYPE_EVENT = 'Event';
  public static final String TYPE_EMAIL = 'EmailMessage';
  public static final String TYPE_FEED = 'FeedItem';

  public static final Map<String, String> EMAIL_STATUS_MAP = new Map<String, String>{
    '0' => 'New',
    '1' => 'Read',
    '2' => 'Replied',
    '3' => 'Sent',
    '4' => 'Forwarded',
    '5' => 'Draft'
  };

  public static final Integer DEFAULT_PAGE_SIZE = 20;
  public static final Integer MAX_AGGREGATE_ITEMS = 2000;
}
