@IsTest
private class LNChatControllerTest {

    // ─── HTTP Mock: OpenAI success ──────────────────────────────────────────

    private static String buildOpenAIResponse(String contentJson) {
        return '{"id":"chatcmpl-test01","object":"chat.completion","choices":[{"index":0,'
            + '"message":{"role":"assistant","content":"' + contentJson + '"},'
            + '"finish_reason":"stop"}],'
            + '"model":"gpt-4o","usage":{"prompt_tokens":100,"completion_tokens":50}}';
    }

    private class AnthropicSuccessMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setHeader('Content-Type', 'application/json');
            String content = '{\\"responseType\\":\\"kpi_cards\\",'
                + '\\"title\\":\\"Account KPIs\\",'
                + '\\"summary\\":\\"This account is performing well.\\",'
                + '\\"data\\":{\\"cards\\":[{'
                + '\\"label\\":\\"Revenue\\",'
                + '\\"value\\":\\"$125K\\",'
                + '\\"unit\\":\\"USD\\",'
                + '\\"trend\\":\\"+12%\\",'
                + '\\"trendDirection\\":\\"up\\",'
                + '\\"icon\\":\\"money\\"'
                + '}]},'
                + '\\"actions\\":[]'
                + '}';
            res.setBody(buildOpenAIResponse(content));
            return res;
        }
    }

    private class AnthropicOverloadMock implements HttpCalloutMock {
        private Integer callCount = 0;
        public HttpResponse respond(HttpRequest req) {
            callCount++;
            HttpResponse res = new HttpResponse();
            if (callCount == 1) {
                res.setStatusCode(429);
                res.setBody('{"error":{"type":"rate_limit_error","message":"Rate limit exceeded"}}');
            } else {
                res.setStatusCode(200);
                String content = '{\\"responseType\\":\\"summary\\",'
                    + '\\"title\\":\\"Test\\",'
                    + '\\"summary\\":\\"Summary text.\\",'
                    + '\\"data\\":{\\"sections\\":[],\\"badges\\":[]},'
                    + '\\"actions\\":[]'
                    + '}';
                res.setBody(buildOpenAIResponse(content));
            }
            return res;
        }
    }

    private class AnthropicErrorMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(401);
            res.setBody('{"error":{"type":"invalid_request_error","message":"Invalid API key"}}');
            return res;
        }
    }

    private class ERPSuccessMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setBody(JSON.serialize(LNChatERPService.getRecordDataMock()));
            return res;
        }
    }

    private class BISuccessMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setBody(JSON.serialize(LNChatBIService.getMetricsMock()));
            return res;
        }
    }

    private class MultiMock implements HttpCalloutMock {
        private List<HttpCalloutMock> mocks;
        private Integer index = 0;

        public MultiMock(List<HttpCalloutMock> mocks) {
            this.mocks = mocks;
        }

        public HttpResponse respond(HttpRequest req) {
            HttpCalloutMock mock = mocks[Math.min(index, mocks.size() - 1)];
            index++;
            return mock.respond(req);
        }
    }

    // ─── Test Data Setup ────────────────────────────────────────────────────

    @TestSetup
    static void makeData() {
        Account acc = new Account(Name = 'Test Corp', Industry = 'Technology', AnnualRevenue = 5000000);
        insert acc;

        Contact con = new Contact(
            FirstName = 'Test', LastName = 'CBContact',
            Email = 'test.cbcontact@testcorp.com', AccountId = acc.Id
        );
        insert con;

        Opportunity opp = new Opportunity(
            Name = 'CB Test Opportunity', AccountId = acc.Id,
            StageName = 'Prospecting', CloseDate = Date.today().addDays(30)
        );
        insert opp;

        Case cas = new Case(
            Subject = 'CB Test Case', AccountId = acc.Id,
            Status = 'New', Priority = 'Medium', Origin = 'Web'
        );
        insert cas;

        Lead lead = new Lead(
            FirstName = 'Test', LastName = 'CBLead',
            Company = 'Test Corp', Status = 'Open - Not Contacted'
        );
        insert lead;
    }

    private static Account getTestAccount() {
        return [SELECT Id, Name FROM Account WHERE Name = 'Test Corp' LIMIT 1];
    }

    private static Contact getTestContact() {
        return [SELECT Id FROM Contact WHERE LastName = 'CBContact' LIMIT 1];
    }

    private static Opportunity getTestOpportunity() {
        return [SELECT Id FROM Opportunity WHERE Name = 'CB Test Opportunity' LIMIT 1];
    }

    private static Case getTestCase() {
        return [SELECT Id FROM Case WHERE Subject = 'CB Test Case' LIMIT 1];
    }

    private static Lead getTestLead() {
        return [SELECT Id FROM Lead WHERE LastName = 'CBLead' LIMIT 1];
    }

    // ─── LNChatController Tests ─────────────────────────────────────────────

    @IsTest
    static void testSendMessage_HappyPath() {
        Account acc = getTestAccount();

        Test.setMock(HttpCalloutMock.class, new MultiMock(new List<HttpCalloutMock>{
            new ERPSuccessMock(),
            new BISuccessMock(),
            new AnthropicSuccessMock()
        }));

        Test.startTest();
        Map<String, Object> result = LNChatController.sendMessage(
            'Summarize this account',
            acc.Id,
            'Account',
            '[]',
            null
        );
        Test.stopTest();

        System.assertNotEquals(null, result, 'Result should not be null');
        System.assertEquals('kpi_cards', (String) result.get('responseType'), 'Response type should be kpi_cards');
        System.assertNotEquals(null, result.get('sessionId'), 'Session ID should be created');
    }

    @IsTest
    static void testSendMessage_BlankMessage() {
        Account acc = getTestAccount();
        Boolean exceptionThrown = false;

        Test.startTest();
        try {
            LNChatController.sendMessage('', acc.Id, 'Account', '[]', null);
        } catch (AuraHandledException e) {
            exceptionThrown = true;
        }
        Test.stopTest();

        System.assert(exceptionThrown, 'Exception should have been thrown for blank message');
    }

    @IsTest
    static void testSendMessage_NullRecordId() {
        Test.setMock(HttpCalloutMock.class, new MultiMock(new List<HttpCalloutMock>{
            new AnthropicSuccessMock()
        }));

        Test.startTest();
        Map<String, Object> result = LNChatController.sendMessage(
            'General question',
            null,
            null,
            null,
            null
        );
        Test.stopTest();

        System.assertNotEquals(null, result, 'Result should not be null even with null recordId');
    }

    @IsTest
    static void testSendMessage_APIFailure() {
        Account acc = getTestAccount();
        Boolean exceptionThrown = false;

        Test.setMock(HttpCalloutMock.class, new AnthropicErrorMock());

        Test.startTest();
        try {
            LNChatController.sendMessage('Summarize', acc.Id, 'Account', '[]', null);
        } catch (AuraHandledException e) {
            exceptionThrown = true;
        }
        Test.stopTest();

        System.assert(exceptionThrown, 'Exception should have been thrown on API failure');
    }

    @IsTest
    static void testSendMessage_WithConversationHistory() {
        Account acc = getTestAccount();

        Test.setMock(HttpCalloutMock.class, new MultiMock(new List<HttpCalloutMock>{
            new ERPSuccessMock(),
            new BISuccessMock(),
            new AnthropicSuccessMock()
        }));

        String historyJson = '[{"role":"user","content":"Hello"},{"role":"assistant","content":"{\\"responseType\\":\\"summary\\",\\"title\\":\\"Hi\\",\\"summary\\":\\"Hello!\\",\\"data\\":{},\\"actions\\":[]}"}]';

        Test.startTest();
        Map<String, Object> result = LNChatController.sendMessage(
            'What are the open opportunities?',
            acc.Id,
            'Account',
            historyJson,
            null
        );
        Test.stopTest();

        System.assertNotEquals(null, result, 'Result with history should not be null');
    }

    @IsTest
    static void testGetConversationHistory_NoSession() {
        Account acc = getTestAccount();

        Test.startTest();
        List<Map<String, Object>> history = LNChatController.getConversationHistory(acc.Id);
        Test.stopTest();

        System.assertNotEquals(null, history, 'History should not be null');
        System.assertEquals(0, history.size(), 'History should be empty for new record');
    }

    @IsTest
    static void testGetConversationHistory_WithMessages() {
        Account acc = getTestAccount();

        LNChatSession__c session = new LNChatSession__c(
            RecordId__c = acc.Id,
            ObjectApiName__c = 'Account',
            LastActivityDate__c = System.now()
        );
        insert session;

        LNChatMessage__c msg1 = new LNChatMessage__c(
            Session__c = session.Id,
            Role__c = 'user',
            Content__c = 'Test message'
        );
        LNChatMessage__c msg2 = new LNChatMessage__c(
            Session__c = session.Id,
            Role__c = 'assistant',
            Content__c = '{"responseType":"summary","title":"Test","summary":"OK","data":{},"actions":[]}',
            ResponseType__c = 'summary'
        );
        insert new List<LNChatMessage__c>{ msg1, msg2 };

        Test.startTest();
        List<Map<String, Object>> history = LNChatController.getConversationHistory(acc.Id);
        Test.stopTest();

        System.assertEquals(2, history.size(), 'Should return 2 messages');
        System.assertEquals('user', (String) history[0].get('role'), 'First message should be from user');
    }

    @IsTest
    static void testClearConversationHistory() {
        Account acc = getTestAccount();

        LNChatSession__c session = new LNChatSession__c(
            RecordId__c = acc.Id,
            ObjectApiName__c = 'Account',
            LastActivityDate__c = System.now()
        );
        insert session;

        LNChatMessage__c msg = new LNChatMessage__c(
            Session__c = session.Id,
            Role__c = 'user',
            Content__c = 'Message to clear'
        );
        insert msg;

        Test.startTest();
        LNChatController.clearConversationHistory(acc.Id);
        Test.stopTest();

        List<LNChatSession__c> sessions = [SELECT Id FROM LNChatSession__c WHERE RecordId__c = :acc.Id];
        System.assertEquals(0, sessions.size(), 'Session should be deleted');

        List<LNChatMessage__c> messages = [SELECT Id FROM LNChatMessage__c WHERE Session__c = :session.Id];
        System.assertEquals(0, messages.size(), 'Messages should be deleted');
    }

    @IsTest
    static void testClearConversationHistory_NoSession() {
        Account acc = getTestAccount();

        Test.startTest();
        LNChatController.clearConversationHistory(acc.Id);
        Test.stopTest();

        System.assert(true, 'Should not throw when no session exists');
    }

    // ─── LNChatResponseDTO Tests ────────────────────────────────────────────

    @IsTest
    static void testResponseDTO_FromJson_KpiCards() {
        String json = '{"responseType":"kpi_cards","title":"KPIs","summary":"Test summary","data":{"cards":[{"label":"Revenue","value":"$100K","unit":"USD","trend":"+10%","trendDirection":"up","icon":"money"}]},"actions":[]}';

        Test.startTest();
        LNChatResponseDTO dto = LNChatResponseDTO.fromJson(json);
        Test.stopTest();

        System.assertEquals('kpi_cards', dto.responseType);
        System.assertEquals('KPIs', dto.title);
        System.assertEquals('Test summary', dto.summary);
        System.assertNotEquals(null, dto.data);
        System.assertEquals(0, dto.actions.size());
    }

    @IsTest
    static void testResponseDTO_FromJson_WithActions() {
        String json = '{"responseType":"alert","title":"Risk","summary":"High risk detected","data":{"severity":"critical","alertTitle":"Alert","message":"Msg","details":["Detail 1"]},"actions":[{"label":"Create Case","flowApiName":"Create_Case_Flow","inputVariables":{"priority":"High"}}]}';

        Test.startTest();
        LNChatResponseDTO dto = LNChatResponseDTO.fromJson(json);
        Test.stopTest();

        System.assertEquals('alert', dto.responseType);
        System.assertEquals(1, dto.actions.size());
        System.assertEquals('Create Case', dto.actions[0].label);
        System.assertEquals('Create_Case_Flow', dto.actions[0].flowApiName);
    }

    @IsTest
    static void testResponseDTO_FromJson_EmptyString() {
        Test.startTest();
        LNChatResponseDTO dto = LNChatResponseDTO.fromJson('');
        Test.stopTest();

        System.assertEquals('alert', dto.responseType, 'Empty JSON should produce error DTO');
    }

    @IsTest
    static void testResponseDTO_FromJson_MalformedJson() {
        Test.startTest();
        LNChatResponseDTO dto = LNChatResponseDTO.fromJson('{not valid json}');
        Test.stopTest();

        System.assertEquals('alert', dto.responseType, 'Malformed JSON should produce error DTO');
    }

    // ─── LNChatContextBuilderService Tests ────────────────────────────────────────

    @IsTest
    static void testContextBuilder_ValidAccount() {
        Account acc = getTestAccount();

        Test.setMock(HttpCalloutMock.class, new MultiMock(new List<HttpCalloutMock>{
            new ERPSuccessMock(),
            new BISuccessMock()
        }));

        Test.startTest();
        LNChatContextBuilderService builder = new LNChatContextBuilderService();
        Map<String, Object> context = builder.buildContext(acc.Id, 'Account');
        Test.stopTest();

        System.assertNotEquals(null, context, 'Context should not be null');
        System.assertEquals('Account', (String) context.get('objectApiName'));
        System.assertNotEquals(null, context.get('salesforceRecord'));
    }

    @IsTest
    static void testWebGate_SummaryIntentAddsWebData() {
        Account acc = new Account(Name = 'Globex Corp', BillingCity = 'Springfield', BillingState = 'IL');
        insert acc;
        Test.setMock(HttpCalloutMock.class, new MultiMock(new List<HttpCalloutMock>{
            new ERPSuccessMock(), new BISuccessMock()
        }));

        Test.startTest();
        Map<String, Object> ctx = new LNChatContextBuilderService()
            .buildContext(acc.Id, 'Account', 'summarize this account');
        Test.stopTest();

        System.assert(ctx.containsKey('webData'), 'Summary intent on Account should attempt web enrichment');
        Map<String, Object> webData = (Map<String, Object>) ctx.get('webData');
        // No API key configured in the test org -> graceful unavailable, no callout made.
        System.assertEquals(false, webData.get('available'));
    }

    @IsTest
    static void testWebGate_NonSummaryNoWebData() {
        Account acc = new Account(Name = 'Globex Corp');
        insert acc;
        Test.setMock(HttpCalloutMock.class, new MultiMock(new List<HttpCalloutMock>{
            new ERPSuccessMock(), new BISuccessMock()
        }));

        Test.startTest();
        Map<String, Object> ctx = new LNChatContextBuilderService()
            .buildContext(acc.Id, 'Account', 'show open opportunities');
        Test.stopTest();

        System.assertEquals(false, ctx.containsKey('webData'), 'Non-summary intent should not call web');
    }

    @IsTest
    static void testWantsSummary() {
        System.assertEquals(true, LNChatContextBuilderService.wantsSummary('Please summarize this account'));
        System.assertEquals(true, LNChatContextBuilderService.wantsSummary('meeting prep please'));
        System.assertEquals(false, LNChatContextBuilderService.wantsSummary('create a contact'));
        System.assertEquals(false, LNChatContextBuilderService.wantsSummary(null));
    }

    @IsTest
    static void testContextBuilder_MissingRecordId() {
        Test.startTest();
        LNChatContextBuilderService builder = new LNChatContextBuilderService();
        Map<String, Object> context = builder.buildContext(null, null);
        Test.stopTest();

        System.assertNotEquals(null, context, 'Context should not be null');
        System.assertNotEquals(null, context.get('error'), 'Error key should be present');
    }

    @IsTest
    static void testContextBuilder_InvalidObjectType() {
        Test.setMock(HttpCalloutMock.class, new MultiMock(new List<HttpCalloutMock>{
            new ERPSuccessMock(),
            new BISuccessMock()
        }));

        Test.startTest();
        LNChatContextBuilderService builder = new LNChatContextBuilderService();
        Map<String, Object> context = builder.buildContext('001000000000001AAA', 'NonExistentObject__c');
        Test.stopTest();

        Map<String, Object> sfRecord = (Map<String, Object>) context.get('salesforceRecord');
        System.assertNotEquals(null, sfRecord, 'SF record should not be null');
        System.assertNotEquals(null, sfRecord.get('error'), 'SF record should have error');
    }

    // ─── LNChatERPService Mock Tests ──────────────────────────────────────

    @IsTest
    static void testERPService_MockData() {
        Map<String, Object> mockData = LNChatERPService.getRecordDataMock();

        System.assertEquals(true, (Boolean) mockData.get('available'));
        System.assertNotEquals(null, mockData.get('orderHistory'));
        System.assertNotEquals(null, mockData.get('financialData'));
    }

    @IsTest
    static void testERPService_BlankExternalId() {
        Test.startTest();
        LNChatERPService erpService = new LNChatERPService();
        Map<String, Object> result = erpService.getRecordData('');
        Test.stopTest();

        System.assertEquals(false, (Boolean) result.get('available'));
    }

    // ─── LNChatBIService Mock Tests ───────────────────────────────────────

    @IsTest
    static void testBIService_MockData() {
        Map<String, Object> mockData = LNChatBIService.getMetricsMock();

        System.assertEquals(true, (Boolean) mockData.get('available'));
        System.assertNotEquals(null, mockData.get('kpis'));
        System.assertNotEquals(null, mockData.get('trendData'));
    }

    @IsTest
    static void testBIService_BlankExternalId() {
        Test.startTest();
        LNChatBIService biService = new LNChatBIService();
        Map<String, Object> result = biService.getMetrics('');
        Test.stopTest();

        System.assertEquals(false, (Boolean) result.get('available'));
    }

    // ─── Session reuse test ──────────────────────────────────────────────────

    @IsTest
    static void testSendMessage_ReuseExistingSession() {
        Account acc = getTestAccount();

        // Pre-create a session so sendMessage will UPDATE it rather than INSERT a new one
        LNChatSession__c existing = new LNChatSession__c(
            RecordId__c = acc.Id,
            ObjectApiName__c = 'Account',
            LastActivityDate__c = System.now()
        );
        insert existing;

        Test.setMock(HttpCalloutMock.class, new MultiMock(new List<HttpCalloutMock>{
            new ERPSuccessMock(),
            new BISuccessMock(),
            new AnthropicSuccessMock()
        }));

        Test.startTest();
        Map<String, Object> result = LNChatController.sendMessage(
            'Follow-up question', acc.Id, 'Account', '[]', null
        );
        Test.stopTest();

        System.assertEquals(existing.Id, (String) result.get('sessionId'), 'Should reuse the pre-existing session');
    }

    // ─── LLM 429 retry ───────────────────────────────────────────────────────

    @IsTest
    static void testSendMessage_Retry429() {
        Account acc = getTestAccount();

        // AnthropicOverloadMock: call 1 returns 429, call 2 returns 200
        Test.setMock(HttpCalloutMock.class, new MultiMock(new List<HttpCalloutMock>{
            new ERPSuccessMock(),
            new BISuccessMock(),
            new AnthropicOverloadMock()
        }));

        Test.startTest();
        Map<String, Object> result = LNChatController.sendMessage(
            'Summarize this account', acc.Id, 'Account', '[]', null
        );
        Test.stopTest();

        System.assertNotEquals(null, result, 'Result should not be null after retry');
        System.assertEquals('summary', (String) result.get('responseType'));
    }

    // ─── Attachment passthrough ───────────────────────────────────────────────

    @IsTest
    static void testSendMessage_WithImageAttachment() {
        Account acc = getTestAccount();

        Test.setMock(HttpCalloutMock.class, new MultiMock(new List<HttpCalloutMock>{
            new ERPSuccessMock(),
            new BISuccessMock(),
            new AnthropicSuccessMock()
        }));

        // Minimal 1x1 pixel PNG in base64
        String attachmentJson = '{"type":"image","name":"test.png","mimeType":"image/png",'
            + '"base64Data":"data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg=="}';

        Test.startTest();
        Map<String, Object> result = LNChatController.sendMessage(
            'What is in this image?', acc.Id, 'Account', '[]', attachmentJson
        );
        Test.stopTest();

        System.assertNotEquals(null, result, 'Result should not be null with image attachment');
        System.assertEquals('kpi_cards', (String) result.get('responseType'));
    }

    // ─── executeRecordAction ─────────────────────────────────────────────────

    @IsTest
    static void testExecuteRecordAction_CreateAccount() {
        Test.startTest();
        Map<String, Object> result = LNChatController.executeRecordAction(
            'Account', 'create', null,
            '{"Name":"CB New Account"}',
            null, false
        );
        Test.stopTest();

        System.assertEquals(true, result.get('success'), 'Account create via controller should succeed');
        System.assertNotEquals(null, result.get('recordId'));
    }

    @IsTest
    static void testExecuteRecordAction_UnsupportedObject() {
        Boolean threw = false;
        try {
            Test.startTest();
            LNChatController.executeRecordAction(
                'Bogus__c', 'create', null, '{"Name":"X"}', null, false
            );
            Test.stopTest();
        } catch (AuraHandledException e) {
            threw = true;
            Test.stopTest();
        }
        System.assert(threw, 'Should throw AuraHandledException for unsupported object');
    }

    // ─── LNChatContextBuilderService — additional object paths ─────────────────────

    @IsTest
    static void testContextBuilder_ContactRecord() {
        Contact con = getTestContact();

        Test.setMock(HttpCalloutMock.class, new MultiMock(new List<HttpCalloutMock>{
            new ERPSuccessMock(),
            new BISuccessMock()
        }));

        Test.startTest();
        LNChatContextBuilderService builder = new LNChatContextBuilderService();
        Map<String, Object> context = builder.buildContext(con.Id, 'Contact');
        Test.stopTest();

        System.assertEquals('Contact', (String) context.get('objectApiName'));
        System.assertNotEquals(null, context.get('salesforceRecord'));
        System.assertNotEquals(null, context.get('relatedRecords'));
    }

    @IsTest
    static void testContextBuilder_OpportunityRecord() {
        Opportunity opp = getTestOpportunity();

        Test.setMock(HttpCalloutMock.class, new MultiMock(new List<HttpCalloutMock>{
            new ERPSuccessMock(),
            new BISuccessMock()
        }));

        Test.startTest();
        LNChatContextBuilderService builder = new LNChatContextBuilderService();
        Map<String, Object> context = builder.buildContext(opp.Id, 'Opportunity');
        Test.stopTest();

        System.assertEquals('Opportunity', (String) context.get('objectApiName'));
        System.assertNotEquals(null, context.get('salesforceRecord'));
    }

    @IsTest
    static void testContextBuilder_CaseRecord() {
        Case cas = getTestCase();

        Test.setMock(HttpCalloutMock.class, new MultiMock(new List<HttpCalloutMock>{
            new ERPSuccessMock(),
            new BISuccessMock()
        }));

        Test.startTest();
        LNChatContextBuilderService builder = new LNChatContextBuilderService();
        Map<String, Object> context = builder.buildContext(cas.Id, 'Case');
        Test.stopTest();

        System.assertEquals('Case', (String) context.get('objectApiName'));
        System.assertNotEquals(null, context.get('salesforceRecord'));
    }

    @IsTest
    static void testContextBuilder_LeadRecord() {
        Lead lead = getTestLead();

        Test.setMock(HttpCalloutMock.class, new MultiMock(new List<HttpCalloutMock>{
            new ERPSuccessMock(),
            new BISuccessMock()
        }));

        Test.startTest();
        LNChatContextBuilderService builder = new LNChatContextBuilderService();
        Map<String, Object> context = builder.buildContext(lead.Id, 'Lead');
        Test.stopTest();

        System.assertEquals('Lead', (String) context.get('objectApiName'));
        System.assertNotEquals(null, context.get('salesforceRecord'));
    }
}
