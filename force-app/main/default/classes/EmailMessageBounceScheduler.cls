global class EmailMessageBounceScheduler implements Schedulable {

    global void execute(SchedulableContext sc) {
        System.debug('=== EmailMessageBounceScheduler START ===');
        EmailMessageBounceJob.process();
        System.debug('=== EmailMessageBounceScheduler END ===');
    }
}