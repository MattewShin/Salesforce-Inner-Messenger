/**
 * ===========================================================================================
 * @description       : Scheduler class to run chat message archive batch job daily
 * @author            : CNXK
 * @last modified on  : 2025-03-13
 * @last modified by  : CNXK
 * ===========================================================================================
 * Modification Log
 * Ver   Date         Author              Description
 * 1.0   2025-03-13   CNXK                Initial version - Schedule batch job to archive messages older than 3 months
 */
public class ChatMessageArchiveScheduler implements Schedulable {
    
    public void execute(SchedulableContext ctx) {
        // Run batch job to archive messages older than 3 months
        ChatMessageArchiveBatch batch = new ChatMessageArchiveBatch();
        Database.executeBatch(batch, 200); // Process 200 records at a time
    }
    
    /**
     * Schedule the archive job to run daily at 3 AM
     * Call this method from Anonymous Apex or Setup:
     * String cronExpression = '0 0 3 * * ?'; // Daily at 3 AM
     * System.schedule('Chat Message Archive', cronExpression, new ChatMessageArchiveScheduler());
     */
    public static String scheduleDailyArchive() {
        String jobName = 'Chat Message Archive - Daily';
        String cronExpression = '0 0 3 * * ?'; // Daily at 3:00 AM
        
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
        ChatMessageArchiveScheduler scheduler = new ChatMessageArchiveScheduler();
        String jobId = System.schedule(jobName, cronExpression, scheduler);
        
        return jobId;
    }
}
