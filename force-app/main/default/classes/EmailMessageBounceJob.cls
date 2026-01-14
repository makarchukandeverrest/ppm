public with sharing class EmailMessageBounceJob {

    // ⏱️ Скільки хвилин назад дивимось
    private static final Integer LOOKBACK_MINUTES = 5;

    public static void process() {
        System.debug('=== EmailMessageBounceJob.process START ===');

        Datetime sinceTime = System.now().addMinutes(-LOOKBACK_MINUTES);
        System.debug('Looking for bounced emails since: ' + sinceTime);

        List<EmailMessage> bouncedEmails = [
            SELECT Id, IsBounced, RelatedToId, CreatedDate
            FROM EmailMessage
            WHERE IsBounced = true
            AND CreatedDate >= :sinceTime
        ];

        System.debug('Bounced EmailMessages found: ' + bouncedEmails.size());

        if (bouncedEmails.isEmpty()) {
            System.debug('No bounced emails to process');
            return;
        }

        // 👉 Викликаємо той самий handler, що і з trigger
        BounceEmailFromEmailMessageHandler.handle(bouncedEmails);

        System.debug('=== EmailMessageBounceJob.process END ===');
    }
}