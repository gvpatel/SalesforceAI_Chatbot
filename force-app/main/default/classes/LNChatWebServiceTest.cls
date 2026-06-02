@isTest
private class LNChatWebServiceTest {
  private class SearchSuccessMock implements HttpCalloutMock {
    public HttpResponse respond(HttpRequest req) {
      System.assert(
        req.getEndpoint().endsWith('/v1/chat/completions'),
        'Should call the OpenAI chat completions endpoint'
      );
      System.assertEquals(
        'Bearer test-key',
        req.getHeader('Authorization'),
        'Should send the API key'
      );
      HttpResponse res = new HttpResponse();
      res.setStatusCode(200);
      res.setBody(
        JSON.serialize(
          new Map<String, Object>{
            'choices' => new List<Object>{
              new Map<String, Object>{
                'message' => new Map<String, Object>{
                  'content' => 'Globex is a multinational manufacturing company based in Springfield.',
                  'annotations' => new List<Object>{
                    new Map<String, Object>{
                      'type' => 'url_citation',
                      'url_citation' => new Map<String, Object>{
                        'title' => 'Globex - Wikipedia',
                        'url' => 'https://en.wikipedia.org/wiki/Globex'
                      }
                    },
                    // duplicate URL — should be deduped
                    new Map<String, Object>{
                      'type' => 'url_citation',
                      'url_citation' => new Map<String, Object>{
                        'title' => 'Globex again',
                        'url' => 'https://en.wikipedia.org/wiki/Globex'
                      }
                    }
                  }
                }
              }
            }
          }
        )
      );
      return res;
    }
  }

  private class ErrorMock implements HttpCalloutMock {
    public HttpResponse respond(HttpRequest req) {
      HttpResponse res = new HttpResponse();
      res.setStatusCode(500);
      res.setBody('{"error":"server"}');
      return res;
    }
  }

  private class EmptyMock implements HttpCalloutMock {
    public HttpResponse respond(HttpRequest req) {
      HttpResponse res = new HttpResponse();
      res.setStatusCode(200);
      res.setBody(
        JSON.serialize(
          new Map<String, Object>{ 'choices' => new List<Object>() }
        )
      );
      return res;
    }
  }

  @isTest
  static void testSuccess() {
    Test.setMock(HttpCalloutMock.class, new SearchSuccessMock());
    Test.startTest();
    LNChatWebService svc = new LNChatWebService();
    svc.apiKeyOverride = 'test-key';
    Map<String, Object> result = svc.getCompanyOverview(
      'Globex',
      'https://globex.com',
      'Springfield, IL'
    );
    Test.stopTest();

    System.assertEquals(
      true,
      result.get('available'),
      'Should be available on 200'
    );
    System.assert(
      ((String) result.get('answer')).contains('Globex'),
      'Answer should be parsed'
    );
    List<Object> sources = (List<Object>) result.get('sources');
    System.assertEquals(
      1,
      sources.size(),
      'Duplicate citation URLs should be deduped to one'
    );
    Map<String, Object> src = (Map<String, Object>) sources[0];
    System.assertEquals('https://en.wikipedia.org/wiki/Globex', src.get('url'));
  }

  @isTest
  static void testNon200ReturnsUnavailable() {
    Test.setMock(HttpCalloutMock.class, new ErrorMock());
    Test.startTest();
    LNChatWebService svc = new LNChatWebService();
    svc.apiKeyOverride = 'test-key';
    Map<String, Object> result = svc.getCompanyOverview('Globex', null, null);
    Test.stopTest();

    System.assertEquals(
      false,
      result.get('available'),
      'Non-200 should be unavailable'
    );
    System.assert(
      ((String) result.get('reason')).contains('500'),
      'Reason should mention status'
    );
  }

  @isTest
  static void testEmptyChoicesUnavailable() {
    Test.setMock(HttpCalloutMock.class, new EmptyMock());
    Test.startTest();
    LNChatWebService svc = new LNChatWebService();
    svc.apiKeyOverride = 'test-key';
    Map<String, Object> result = svc.getCompanyOverview('Globex', null, null);
    Test.stopTest();

    System.assertEquals(
      false,
      result.get('available'),
      'No choices should be unavailable'
    );
  }

  @isTest
  static void testBlankNameNoCallout() {
    // No mock set — if a callout were attempted this would throw.
    Map<String, Object> result = new LNChatWebService()
      .getCompanyOverview('', null, null);
    System.assertEquals(false, result.get('available'));
    System.assertEquals('No account name provided', result.get('reason'));
  }

  @isTest
  static void testGracefulWhenUnconfigured() {
    // No mock and no injected key → either "key not configured" or a failed callout;
    // both must degrade to available:false rather than throwing.
    Map<String, Object> result = new LNChatWebService()
      .getCompanyOverview('Globex', null, null);
    System.assertEquals(false, result.get('available'));
  }

  @isTest
  static void testMock() {
    Map<String, Object> m = LNChatWebService.getCompanyOverviewMock();
    System.assertEquals(true, m.get('available'));
    System.assert(m.containsKey('answer'));
    System.assert(m.containsKey('sources'));
  }
}
