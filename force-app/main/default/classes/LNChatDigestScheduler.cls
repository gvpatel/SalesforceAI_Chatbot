public class LNChatDigestScheduler implements Schedulable {
    public void execute(SchedulableContext sc) {
        Database.executeBatch(new LNChatDigestBatch(), 1);
    }
}
