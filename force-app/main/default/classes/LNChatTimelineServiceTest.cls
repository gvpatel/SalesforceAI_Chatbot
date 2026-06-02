@isTest
private class LNChatTimelineServiceTest {
  @isTest
  static void testTasksAndEventsAreReturned() {
    Account acc = new Account(Name = 'Timeline Co');
    insert acc;

    List<Task> tasks = new List<Task>{
      new Task(
        WhatId = acc.Id,
        Subject = 'Intro call',
        Type = 'Call',
        ActivityDate = Date.today().addDays(-30)
      ),
      new Task(
        WhatId = acc.Id,
        Subject = 'Follow-up email',
        Type = 'Email',
        ActivityDate = Date.today().addDays(-10)
      ),
      new Task(
        WhatId = acc.Id,
        Subject = 'Generic todo',
        Type = 'Other',
        ActivityDate = Date.today().addDays(-5)
      )
    };
    insert tasks;

    Event ev = new Event(
      WhatId = acc.Id,
      Subject = 'Discovery meeting',
      ActivityDateTime = Datetime.now().addDays(-20),
      DurationInMinutes = 30
    );
    insert ev;

    Test.startTest();
    Map<String, Object> result = new LNChatTimelineService()
      .getActivityTimeline(acc.Id);
    Test.stopTest();

    System.assertEquals(true, result.get('available'), 'Should be available');
    System.assertEquals(
      false,
      result.get('truncated'),
      'Small data set should not be truncated'
    );
    List<Object> activities = (List<Object>) result.get('activities');
    System.assertEquals(4, activities.size(), '3 tasks + 1 event expected');

    Map<String, Integer> typeCounts = new Map<String, Integer>();
    Set<String> sources = new Set<String>();
    for (Object o : activities) {
      Map<String, Object> a = (Map<String, Object>) o;
      String type = (String) a.get('type');
      typeCounts.put(
        type,
        (typeCounts.containsKey(type) ? typeCounts.get(type) : 0) + 1
      );
      sources.add((String) a.get('source'));
      System.assertNotEquals(
        null,
        a.get('dateMs'),
        'Each activity should have a dateMs'
      );
    }
    System.assertEquals(1, typeCounts.get('call'));
    System.assertEquals(1, typeCounts.get('email'));
    System.assertEquals(1, typeCounts.get('other'));
    System.assertEquals(1, typeCounts.get('meeting'));
    // GPRLM1 has no Gong/SalesLoft packages → everything is Salesforce
    System.assert(
      sources.contains('Salesforce'),
      'Default source should be Salesforce'
    );
  }

  @isTest
  static void testBlankRecordId() {
    Map<String, Object> result = new LNChatTimelineService()
      .getActivityTimeline('');
    System.assertEquals(false, result.get('available'));
    System.assertEquals(0, ((List<Object>) result.get('activities')).size());
  }

  @isTest
  static void testAccountWithNoActivities() {
    Account acc = new Account(Name = 'Empty Co');
    insert acc;

    Test.startTest();
    Map<String, Object> result = new LNChatTimelineService()
      .getActivityTimeline(acc.Id);
    Test.stopTest();

    System.assertEquals(
      true,
      result.get('available'),
      'Empty is still a valid, available result'
    );
    System.assertEquals(0, ((List<Object>) result.get('activities')).size());
  }

  @isTest
  static void testControllerEntryPoint() {
    Account acc = new Account(Name = 'Controller Co');
    insert acc;
    insert new Task(
      WhatId = acc.Id,
      Subject = 'Call',
      Type = 'Call',
      ActivityDate = Date.today()
    );

    Test.startTest();
    Map<String, Object> result = LNChatController.getActivityTimeline(acc.Id);
    Test.stopTest();

    System.assertEquals(true, result.get('available'));
    System.assertEquals(1, ((List<Object>) result.get('activities')).size());
  }
}
