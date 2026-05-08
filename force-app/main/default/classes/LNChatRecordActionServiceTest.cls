@IsTest
private class LNChatRecordActionServiceTest {

    @TestSetup
    static void makeData() {
        Account acc = new Account(Name = 'RAS Test Corp', Phone = '5555551234', Industry = 'Technology');
        insert acc;

        Contact con = new Contact(
            FirstName = 'Jane', LastName = 'RASSmith',
            Email = 'jane.rassmith@rastest.com', AccountId = acc.Id
        );
        insert con;

        Opportunity opp = new Opportunity(
            Name = 'RAS Test Opp', AccountId = acc.Id,
            StageName = 'Prospecting', CloseDate = Date.today().addDays(30)
        );
        insert opp;
    }

    private static Account getAcc() {
        return [SELECT Id, Name, Phone FROM Account WHERE Name = 'RAS Test Corp' LIMIT 1];
    }

    private static Contact getCon() {
        return [SELECT Id, FirstName, LastName, Email, AccountId FROM Contact WHERE LastName = 'RASSmith' LIMIT 1];
    }

    private static Opportunity getOpp() {
        return [SELECT Id, Name, AccountId FROM Opportunity WHERE Name = 'RAS Test Opp' LIMIT 1];
    }

    // ─── Guard clauses ────────────────────────────────────────────────────────

    @IsTest
    static void testUnsupportedObject() {
        Boolean threw = false;
        try {
            LNChatRecordActionService.executeAction(
                'Bogus__c', 'create', null,
                new Map<String, Object>{ 'Name' => 'X' }, null, false
            );
        } catch (AuraHandledException e) {
            threw = true;
        }
        System.assert(threw, 'Should throw for unsupported object');
    }

    @IsTest
    static void testUnsupportedOperation() {
        Boolean threw = false;
        try {
            LNChatRecordActionService.executeAction(
                'Account', 'delete', null,
                new Map<String, Object>{ 'Name' => 'X' }, null, false
            );
        } catch (AuraHandledException e) {
            threw = true;
        }
        System.assert(threw, 'Should throw for unsupported operation');
    }

    @IsTest
    static void testEmptyFields() {
        Boolean threw = false;
        try {
            LNChatRecordActionService.executeAction(
                'Account', 'create', null,
                new Map<String, Object>(), null, false
            );
        } catch (AuraHandledException e) {
            threw = true;
        }
        System.assert(threw, 'Should throw for empty fields');
    }

    @IsTest
    static void testUpdateWithoutRecordId() {
        Boolean threw = false;
        try {
            LNChatRecordActionService.executeAction(
                'Account', 'update', null,
                new Map<String, Object>{ 'Phone' => '999' }, null, false
            );
        } catch (AuraHandledException e) {
            threw = true;
        }
        System.assert(threw, 'Should throw for update without recordId');
    }

    // ─── CREATE happy path ────────────────────────────────────────────────────

    @IsTest
    static void testCreateAccount() {
        Test.startTest();
        Map<String, Object> result = LNChatRecordActionService.executeAction(
            'Account', 'create', null,
            new Map<String, Object>{ 'Name' => 'RAS New Account' },
            null, false
        );
        Test.stopTest();

        System.assertEquals(true, result.get('success'), 'Account create should succeed');
        System.assertNotEquals(null, result.get('recordId'), 'recordId should be returned');
        System.assertEquals(1, [SELECT COUNT() FROM Account WHERE Name = 'RAS New Account'], 'Account should exist');
    }

    @IsTest
    static void testCreateContact() {
        Account acc = getAcc();
        Test.startTest();
        Map<String, Object> result = LNChatRecordActionService.executeAction(
            'Contact', 'create', null,
            new Map<String, Object>{
                'FirstName' => 'Bob',
                'LastName'  => 'RASJones',
                'Email'     => 'bob.rasjones.unique@rastest.com',
                'AccountId' => acc.Id
            },
            null, false
        );
        Test.stopTest();

        System.assertEquals(true, result.get('success'));
        System.assertEquals(1, [SELECT COUNT() FROM Contact WHERE LastName = 'RASJones'], 'Contact should exist');
    }

    @IsTest
    static void testCreateTask() {
        Account acc = getAcc();
        Test.startTest();
        Map<String, Object> result = LNChatRecordActionService.executeAction(
            'Task', 'create', null,
            new Map<String, Object>{
                'Subject'      => 'RAS Follow up call',
                'Status'       => 'Not Started',
                'Priority'     => 'Normal',
                'ActivityDate' => String.valueOf(Date.today().addDays(7)),
                'WhatId'       => acc.Id
            },
            null, false
        );
        Test.stopTest();

        System.assertEquals(true, result.get('success'));
        System.assertEquals(1, [SELECT COUNT() FROM Task WHERE Subject = 'RAS Follow up call'], 'Task should exist');
    }

    @IsTest
    static void testCreateCase() {
        Account acc = getAcc();
        Test.startTest();
        Map<String, Object> result = LNChatRecordActionService.executeAction(
            'Case', 'create', null,
            new Map<String, Object>{
                'Subject'   => 'RAS Support Ticket',
                'Status'    => 'New',
                'Priority'  => 'Medium',
                'Origin'    => 'Web',
                'AccountId' => acc.Id
            },
            null, false
        );
        Test.stopTest();

        System.assertEquals(true, result.get('success'));
        System.assertEquals(1, [SELECT COUNT() FROM Case WHERE Subject = 'RAS Support Ticket'], 'Case should exist');
    }

    @IsTest
    static void testCreateOpportunity() {
        Account acc = getAcc();
        Test.startTest();
        Map<String, Object> result = LNChatRecordActionService.executeAction(
            'Opportunity', 'create', null,
            new Map<String, Object>{
                'Name'      => 'RAS New Opportunity Unique',
                'StageName' => 'Prospecting',
                'CloseDate' => String.valueOf(Date.today().addDays(30)),
                'AccountId' => acc.Id
            },
            null, false
        );
        Test.stopTest();

        System.assertEquals(true, result.get('success'));
        System.assertEquals(1, [SELECT COUNT() FROM Opportunity WHERE Name = 'RAS New Opportunity Unique']);
    }

    @IsTest
    static void testCreateQuote() {
        Opportunity opp = getOpp();
        Test.startTest();
        Map<String, Object> result = LNChatRecordActionService.executeAction(
            'Quote', 'create', null,
            new Map<String, Object>{
                'Name'           => 'RAS New Quote',
                'Status'         => 'Draft',
                'ExpirationDate' => String.valueOf(Date.today().addDays(30)),
                'OpportunityId'  => opp.Id
            },
            null, false
        );
        Test.stopTest();

        System.assertEquals(true, result.get('success'));
        System.assertEquals(1, [SELECT COUNT() FROM Quote WHERE Name = 'RAS New Quote']);
    }

    // ─── UPDATE happy path ────────────────────────────────────────────────────

    @IsTest
    static void testUpdateAccount() {
        Account acc = getAcc();
        Test.startTest();
        Map<String, Object> result = LNChatRecordActionService.executeAction(
            'Account', 'update', acc.Id,
            new Map<String, Object>{ 'Phone' => '9995550001' },
            acc.Id, false  // currentPageRecordId = same record → skips ambiguity check
        );
        Test.stopTest();

        System.assertEquals(true, result.get('success'));
        System.assertEquals('9995550001', [SELECT Phone FROM Account WHERE Id = :acc.Id].Phone);
    }

    @IsTest
    static void testUpdateContact() {
        Contact con = getCon();
        Test.startTest();
        Map<String, Object> result = LNChatRecordActionService.executeAction(
            'Contact', 'update', con.Id,
            new Map<String, Object>{ 'Title' => 'VP of Sales' },
            con.Id, false
        );
        Test.stopTest();

        System.assertEquals(true, result.get('success'));
        System.assertEquals('VP of Sales', [SELECT Title FROM Contact WHERE Id = :con.Id].Title);
    }

    // ─── Duplicate detection ──────────────────────────────────────────────────

    @IsTest
    static void testDuplicateAccount() {
        Account existing = getAcc();
        Test.startTest();
        Map<String, Object> result = LNChatRecordActionService.executeAction(
            'Account', 'create', null,
            new Map<String, Object>{ 'Name' => existing.Name },
            null, false
        );
        Test.stopTest();

        System.assertEquals(false, result.get('success'));
        System.assertEquals(true, result.get('isDuplicate'));
    }

    @IsTest
    static void testDuplicateContactByEmail() {
        Contact existing = getCon();
        Test.startTest();
        Map<String, Object> result = LNChatRecordActionService.executeAction(
            'Contact', 'create', null,
            new Map<String, Object>{
                'FirstName' => 'Other',
                'LastName'  => 'Person',
                'Email'     => existing.Email
            },
            null, false
        );
        Test.stopTest();

        System.assertEquals(false, result.get('success'));
        System.assertEquals(true, result.get('isDuplicate'));
    }

    @IsTest
    static void testDuplicateOpportunity() {
        Opportunity existing = getOpp();
        Test.startTest();
        Map<String, Object> result = LNChatRecordActionService.executeAction(
            'Opportunity', 'create', null,
            new Map<String, Object>{
                'Name'      => existing.Name,
                'AccountId' => existing.AccountId,
                'StageName' => 'Prospecting',
                'CloseDate' => String.valueOf(Date.today().addDays(30))
            },
            null, false
        );
        Test.stopTest();

        System.assertEquals(false, result.get('success'));
        System.assertEquals(true, result.get('isDuplicate'));
    }

    @IsTest
    static void testDuplicateCase() {
        Account acc = getAcc();
        insert new Case(Subject = 'RAS Dup Case', AccountId = acc.Id, Status = 'New', Priority = 'Medium', Origin = 'Web');

        Test.startTest();
        Map<String, Object> result = LNChatRecordActionService.executeAction(
            'Case', 'create', null,
            new Map<String, Object>{
                'Subject'   => 'RAS Dup Case',
                'AccountId' => acc.Id,
                'Status'    => 'New',
                'Priority'  => 'Medium',
                'Origin'    => 'Web'
            },
            null, false
        );
        Test.stopTest();

        System.assertEquals(false, result.get('success'));
        System.assertEquals(true, result.get('isDuplicate'));
    }

    @IsTest
    static void testBypassDuplicate() {
        Account existing = getAcc();
        Test.startTest();
        Map<String, Object> result = LNChatRecordActionService.executeAction(
            'Account', 'create', null,
            new Map<String, Object>{ 'Name' => existing.Name },
            null, true  // bypassDuplicate = true
        );
        Test.stopTest();

        System.assertEquals(true, result.get('success'), 'Bypass should allow creation despite duplicate name');
    }

    // ─── Ambiguous target ─────────────────────────────────────────────────────

    @IsTest
    static void testAmbiguousContact() {
        Account acc = getAcc();
        Contact c1 = new Contact(FirstName = 'Twin', LastName = 'RASAmbig', AccountId = acc.Id);
        Contact c2 = new Contact(FirstName = 'Twin', LastName = 'RASAmbig', AccountId = acc.Id);
        insert new List<Contact>{ c1, c2 };

        Test.startTest();
        // Update c1, but currentPageRecordId = acc.Id (different from c1) → ambiguity check runs
        Map<String, Object> result = LNChatRecordActionService.executeAction(
            'Contact', 'update', c1.Id,
            new Map<String, Object>{ 'Title' => 'Manager' },
            acc.Id, false
        );
        Test.stopTest();

        System.assertEquals(false, result.get('success'));
        System.assertEquals(true, result.get('isAmbiguous'));
    }
}
