/**
 * ===========================================================================================
 * @description       : Scheduler class to run chat message cleanup batch job daily
 * @author            : CNXK
 * @last modified on  : 2025-03-06
 * @last modified by  : CNXK
 * ===========================================================================================
 * Modification Log
 * Ver   Date         Author              Description
 * 1.0   2025-03-06   CNXK                Initial version - Schedule batch job to delete messages older than 1 year
 */
public class ChatMessageCleanupScheduler implements Schedulable {
    
    public void execute(SchedulableContext ctx) {
        // Run batch job to delete messages older than 1 year
        ChatMessageCleanupBatch batch = new ChatMessageCleanupBatch();
        Database.executeBatch(batch, 200); // Process 200 records at a time
    }
    
    /**
     * Schedule the cleanup job to run daily at 2 AM
     * Call this method from Anonymous Apex or Setup:
     * String cronExpression = '0 0 2 * * ?'; // Daily at 2 AM
     * System.schedule('Chat Message Cleanup', cronExpression, new ChatMessageCleanupScheduler());
     */
    public static String scheduleDailyCleanup() {
        String jobName = 'Chat Message Cleanup - Daily';
        String cronExpression = '0 0 2 * * ?'; // Daily at 2:00 AM
        
        // Remove existing job if any
        try {
            List<CronTrigger> existingJobs = [
                SELECT Id, CronJobDetail.Name
                FROM CronTrigger
                WHERE CronJobDetail.Name = :jobName
            ];
            if (!existingJobs.isEmpty()) {
                System.abortJob(existingJobs[0].Id);
            }
        } catch (Exception e) {
            System.debug('No existing job to remove: ' + e.getMessage());
        }
        
        // Schedule new job
        ChatMessageCleanupScheduler scheduler = new ChatMessageCleanupScheduler();
        String jobId = System.schedule(jobName, cronExpression, scheduler);
        
        return jobId;
    }
}
