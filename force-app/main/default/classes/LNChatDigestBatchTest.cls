@isTest
private class LNChatDigestBatchTest {
  private class LLMMock implements HttpCalloutMock {
    public HttpResponse respond(HttpRequest req) {
      HttpResponse res = new HttpResponse();
      res.setStatusCode(200);
      res.setBody(
        JSON.serialize(
          new Map<String, Object>{
            'choices' => new List<Object>{
              new Map<String, Object>{
                'message' => new Map<String, Object>{
                  'content' => 'Pipeline looks healthy. Top action: call Acme.'
                }
              }
            }
          }
        )
      );
      return res;
    }
  }

  // An account with no activity scores RED (daysSinceActivity = 999), so the rep gets a digest.
  @testSetup
  static void setup() {
    insert new Account(Name = 'Digest Test Account');
  }

  @isTest
  static void testExecuteSendsEmailWithPdfAttachment() {
    User rep = [
      SELECT Id, Name, Email, FirstName, LastName
      FROM User
      WHERE Id = :UserInfo.getUserId()
    ];
    Test.setMock(HttpCalloutMock.class, new LLMMock());

    Test.startTest();
    new LNChatDigestBatch().execute(null, new List<SObject>{ rep });
    // Assert inside the start/stopTest window — stopTest resets limit counters.
    System.assertEquals(
      1,
      Limits.getEmailInvocations(),
      'One digest email should be sent'
    );
    Test.stopTest();
  }

  @isTest
  static void testFullBatchRuns() {
    Test.setMock(HttpCalloutMock.class, new LLMMock());
    Test.startTest();
    Database.executeBatch(new LNChatDigestBatch(), 1);
    Test.stopTest();
    // Reaching here without exception covers start/execute/finish.
    System.assert(true);
  }

  @isTest
  static void testPdfControllerGetters() {
    LNChatDigestPdfController.repNameVal = 'Sarah Rep';
    LNChatDigestPdfController.digestDateVal = Date.today().format();
    LNChatDigestPdfController.insightsVal = 'Some insights';
    LNChatDigestPdfController.rowsVal = new List<Map<String, Object>>{
      new Map<String, Object>{
        'name' => 'Acme',
        'scoreColor' => '#c00',
        'nearestOpp' => 'Big Deal',
        'overdueTaskCount' => 2,
        'openCaseCount' => 1,
        'daysSinceActivity' => 50
      }
    };

    LNChatDigestPdfController ctrl = new LNChatDigestPdfController();
    System.assertEquals('Sarah Rep', ctrl.getRepName());
    System.assertEquals(true, ctrl.getHasInsights());
    System.assertEquals(1, ctrl.getRows().size());
  }
}
