public with sharing class LNChatContextBuilderService {

    // Summary/overview intent keywords (aligned with LLMService Rule 16) that
    // gate the optional web-search callout so it fires only when relevant.
    private static final List<String> SUMMARY_INTENT_KEYWORDS = new List<String>{
        'summarize', 'summary', 'overview', 'review', 'meeting prep',
        'call prep', 'pre-call', 'brief'
    };

    // Backwards-compatible overload (no user message → no web enrichment).
    public Map<String, Object> buildContext(String recordId, String objectApiName) {
        return buildContext(recordId, objectApiName, null);
    }

    public Map<String, Object> buildContext(String recordId, String objectApiName, String userMessage) {
        Map<String, Object> context = new Map<String, Object>();

        if (String.isBlank(recordId) || String.isBlank(objectApiName)) {
            context.put('error', 'Missing recordId or objectApiName');
            return context;
        }

        context.put('objectApiName', objectApiName);
        context.put('recordId', recordId);

        Map<String, Object> sfRecord = querySalesforceRecord(recordId, objectApiName);
        context.put('salesforceRecord', sfRecord);

        Map<String, Object> relatedRecords = queryRelatedRecords(recordId, objectApiName, sfRecord);
        context.put('relatedRecords', relatedRecords);

        String externalId = extractExternalId(sfRecord, objectApiName);

        LNChatERPService erpService = new LNChatERPService();
        Map<String, Object> erpData;
        try {
            erpData = erpService.getRecordData(externalId);
        } catch (Exception e) {
            System.debug(LoggingLevel.WARN, 'ERP data fetch failed: ' + e.getMessage());
            erpData = new Map<String, Object>{ 'available' => false, 'reason' => e.getMessage() };
        }
        context.put('erpData', erpData);

        LNChatBIService biService = new LNChatBIService();
        Map<String, Object> biData;
        try {
            biData = biService.getMetrics(externalId);
        } catch (Exception e) {
            System.debug(LoggingLevel.WARN, 'BI data fetch failed: ' + e.getMessage());
            biData = new Map<String, Object>{ 'available' => false, 'reason' => e.getMessage() };
        }
        context.put('biData', biData);

        // Internet-sourced company overview — only for Account summaries, to keep
        // the extra callout (and the account name leaving the org) off non-summary turns.
        if (objectApiName == 'Account' && wantsSummary(userMessage)) {
            try {
                LNChatWebService webSvc = new LNChatWebService();
                String acctName = (String) sfRecord.get('Name');
                String website = (String) sfRecord.get('Website');
                String location = buildLocation(sfRecord);
                context.put('webData', webSvc.getCompanyOverview(acctName, website, location));
            } catch (Exception e) {
                System.debug(LoggingLevel.WARN, 'Web data fetch failed: ' + e.getMessage());
                context.put('webData', new Map<String, Object>{ 'available' => false, 'reason' => e.getMessage() });
            }
        }

        context.put('contextBuildTimestamp', String.valueOf(System.now()));

        return context;
    }

    @TestVisible
    private static Boolean wantsSummary(String userMessage) {
        if (String.isBlank(userMessage)) {
            return false;
        }
        String msg = userMessage.toLowerCase();
        for (String kw : SUMMARY_INTENT_KEYWORDS) {
            if (msg.contains(kw)) {
                return true;
            }
        }
        return false;
    }

    private String buildLocation(Map<String, Object> sfRecord) {
        String city = (String) sfRecord.get('BillingCity');
        String state = (String) sfRecord.get('BillingState');
        List<String> parts = new List<String>();
        if (String.isNotBlank(city)) { parts.add(city); }
        if (String.isNotBlank(state)) { parts.add(state); }
        return String.join(parts, ', ');
    }

    private Map<String, Object> querySalesforceRecord(String recordId, String objectApiName) {
        Map<String, Object> result = new Map<String, Object>();

        try {
            Schema.SObjectType sObjType = Schema.getGlobalDescribe().get(objectApiName);
            if (sObjType == null) {
                result.put('error', 'Unknown object type: ' + objectApiName);
                return result;
            }

            Schema.DescribeSObjectResult describeResult = sObjType.getDescribe();
            Map<String, Schema.SObjectField> fieldMap = describeResult.fields.getMap();

            List<String> queryableFields = new List<String>();
            for (String fieldName : fieldMap.keySet()) {
                Schema.DescribeFieldResult fieldDescribe = fieldMap.get(fieldName).getDescribe();
                if (fieldDescribe.isAccessible() && !fieldDescribe.isCalculated()) {
                    queryableFields.add(fieldName);
                }
            }

            if (queryableFields.isEmpty()) {
                queryableFields.add('Id');
            }

            String soql = 'SELECT ' + String.join(queryableFields, ', ')
                + ' FROM ' + objectApiName
                + ' WHERE Id = :recordId'
                + ' LIMIT 1';

            List<SObject> records = Database.query(soql);
            if (!records.isEmpty()) {
                Map<String, Object> populatedFields = records[0].getPopulatedFieldsAsMap();
                for (String key : populatedFields.keySet()) {
                    result.put(key, populatedFields.get(key));
                }
            }

        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'querySalesforceRecord failed: ' + e.getMessage());
            result.put('error', e.getMessage());
        }

        return result;
    }

    private Map<String, Object> queryRelatedRecords(String recordId, String objectApiName, Map<String, Object> sfRecord) {
        Map<String, Object> related = new Map<String, Object>();

        if (objectApiName == 'Account') {
            related.putAll(queryAccountRelated(recordId));
        } else if (objectApiName == 'Contact') {
            related.putAll(queryContactRelated(recordId, sfRecord));
        } else if (objectApiName == 'Opportunity') {
            related.putAll(queryOpportunityRelated(recordId, sfRecord));
        } else if (objectApiName == 'Case') {
            related.putAll(queryCaseRelated(recordId));
        } else if (objectApiName == 'Lead') {
            related.putAll(queryLeadRelated(recordId));
        }

        return related;
    }

    // ─── Account ─────────────────────────────────────────────────────────────

    private Map<String, Object> queryAccountRelated(String accountId) {
        Map<String, Object> related = new Map<String, Object>();

        try {
            related.put('contacts', convertToMapList([
                SELECT Id, Name, Title, Email, Phone, Department, LastActivityDate
                FROM Contact
                WHERE AccountId = :accountId
                ORDER BY LastActivityDate DESC NULLS LAST
                LIMIT 10
            ]));
        } catch (Exception e) { related.put('contacts_error', e.getMessage()); }

        try {
            related.put('opportunities', convertToMapList([
                SELECT Id, Name, StageName, Amount, CloseDate, Probability, Type, OwnerId
                FROM Opportunity
                WHERE AccountId = :accountId AND IsClosed = false
                ORDER BY CloseDate ASC
                LIMIT 5
            ]));
        } catch (Exception e) { related.put('opportunities_error', e.getMessage()); }

        try {
            related.put('cases', convertToMapList([
                SELECT Id, CaseNumber, Subject, Status, Priority, Type, Origin, CreatedDate
                FROM Case
                WHERE AccountId = :accountId AND Status NOT IN ('Closed', 'Resolved')
                ORDER BY CreatedDate DESC
                LIMIT 5
            ]));
        } catch (Exception e) { related.put('cases_error', e.getMessage()); }

        try {
            related.put('tasks', convertToMapList([
                SELECT Id, Subject, Status, Priority, ActivityDate, Description
                FROM Task
                WHERE WhatId = :accountId AND Status NOT IN ('Completed', 'Cancelled')
                ORDER BY ActivityDate ASC NULLS LAST
                LIMIT 5
            ]));
        } catch (Exception e) { related.put('tasks_error', e.getMessage()); }

        try {
            related.put('orders', convertToMapList([
                SELECT Id, OrderNumber, Status, TotalAmount, EffectiveDate, EndDate, Type
                FROM Order
                WHERE AccountId = :accountId
                ORDER BY EffectiveDate DESC NULLS LAST
                LIMIT 5
            ]));
        } catch (Exception e) { related.put('orders_error', e.getMessage()); }

        try {
            related.put('contracts', convertToMapList([
                SELECT Id, ContractNumber, Status, StartDate, EndDate, ContractTerm
                FROM Contract
                WHERE AccountId = :accountId
                ORDER BY StartDate DESC NULLS LAST
                LIMIT 5
            ]));
        } catch (Exception e) { related.put('contracts_error', e.getMessage()); }

        try {
            related.put('quotes', convertToMapList([
                SELECT Id, Name, Status, GrandTotal, ExpirationDate, CreatedDate
                FROM Quote
                WHERE Account.Id = :accountId
                ORDER BY CreatedDate DESC
                LIMIT 5
            ]));
        } catch (Exception e) { related.put('quotes_error', e.getMessage()); }

        return related;
    }

    // ─── Contact ─────────────────────────────────────────────────────────────

    private Map<String, Object> queryContactRelated(String contactId, Map<String, Object> sfRecord) {
        Map<String, Object> related = new Map<String, Object>();

        try {
            related.put('opportunities', convertToMapList([
                SELECT Id, Name, StageName, Amount, CloseDate, Probability, Type
                FROM Opportunity
                WHERE Id IN (
                    SELECT OpportunityId FROM OpportunityContactRole WHERE ContactId = :contactId
                )
                AND IsClosed = false
                ORDER BY CloseDate ASC
                LIMIT 5
            ]));
        } catch (Exception e) { related.put('opportunities_error', e.getMessage()); }

        try {
            related.put('cases', convertToMapList([
                SELECT Id, CaseNumber, Subject, Status, Priority, CreatedDate
                FROM Case
                WHERE ContactId = :contactId AND Status NOT IN ('Closed', 'Resolved')
                ORDER BY CreatedDate DESC
                LIMIT 5
            ]));
        } catch (Exception e) { related.put('cases_error', e.getMessage()); }

        try {
            related.put('tasks', convertToMapList([
                SELECT Id, Subject, Status, Priority, ActivityDate, Description
                FROM Task
                WHERE WhoId = :contactId AND Status NOT IN ('Completed', 'Cancelled')
                ORDER BY ActivityDate ASC NULLS LAST
                LIMIT 5
            ]));
        } catch (Exception e) { related.put('tasks_error', e.getMessage()); }

        String accountId = (String) sfRecord.get('AccountId');
        if (String.isNotBlank(accountId)) {
            try {
                List<Account> accs = [
                    SELECT Id, Name, Industry, Phone, BillingCity, BillingState, AnnualRevenue, NumberOfEmployees
                    FROM Account WHERE Id = :accountId LIMIT 1
                ];
                if (!accs.isEmpty()) {
                    related.put('account', accs[0].getPopulatedFieldsAsMap());
                }
            } catch (Exception e) { related.put('account_error', e.getMessage()); }
        }

        return related;
    }

    // ─── Opportunity ─────────────────────────────────────────────────────────

    private Map<String, Object> queryOpportunityRelated(String oppId, Map<String, Object> sfRecord) {
        Map<String, Object> related = new Map<String, Object>();

        try {
            related.put('contacts', convertOCRToMapList([
                SELECT ContactId, Contact.Name, Contact.Title, Contact.Email, Contact.Phone, Role, IsPrimary
                FROM OpportunityContactRole
                WHERE OpportunityId = :oppId
                LIMIT 10
            ]));
        } catch (Exception e) { related.put('contacts_error', e.getMessage()); }

        try {
            related.put('tasks', convertToMapList([
                SELECT Id, Subject, Status, Priority, ActivityDate, Description
                FROM Task
                WHERE WhatId = :oppId AND Status NOT IN ('Completed', 'Cancelled')
                ORDER BY ActivityDate ASC NULLS LAST
                LIMIT 5
            ]));
        } catch (Exception e) { related.put('tasks_error', e.getMessage()); }

        try {
            related.put('quotes', convertToMapList([
                SELECT Id, Name, Status, GrandTotal, ExpirationDate, CreatedDate
                FROM Quote
                WHERE OpportunityId = :oppId
                ORDER BY CreatedDate DESC
                LIMIT 5
            ]));
        } catch (Exception e) { related.put('quotes_error', e.getMessage()); }

        String accountId = (String) sfRecord.get('AccountId');
        if (String.isNotBlank(accountId)) {
            try {
                List<Account> accs = [
                    SELECT Id, Name, Industry, Phone, BillingCity, AnnualRevenue
                    FROM Account WHERE Id = :accountId LIMIT 1
                ];
                if (!accs.isEmpty()) {
                    related.put('account', accs[0].getPopulatedFieldsAsMap());
                }
            } catch (Exception e) { related.put('account_error', e.getMessage()); }

            try {
                related.put('orders', convertToMapList([
                    SELECT Id, OrderNumber, Status, TotalAmount, EffectiveDate
                    FROM Order WHERE AccountId = :accountId
                    ORDER BY EffectiveDate DESC NULLS LAST LIMIT 5
                ]));
            } catch (Exception e) { related.put('orders_error', e.getMessage()); }
        }

        return related;
    }

    // ─── Case ─────────────────────────────────────────────────────────────────

    private Map<String, Object> queryCaseRelated(String caseId) {
        Map<String, Object> related = new Map<String, Object>();

        try {
            related.put('tasks', convertToMapList([
                SELECT Id, Subject, Status, Priority, ActivityDate, Description
                FROM Task
                WHERE WhatId = :caseId AND Status NOT IN ('Completed', 'Cancelled')
                ORDER BY ActivityDate ASC NULLS LAST
                LIMIT 5
            ]));
        } catch (Exception e) { related.put('tasks_error', e.getMessage()); }

        return related;
    }

    // ─── Lead ─────────────────────────────────────────────────────────────────

    private Map<String, Object> queryLeadRelated(String leadId) {
        Map<String, Object> related = new Map<String, Object>();

        try {
            related.put('tasks', convertToMapList([
                SELECT Id, Subject, Status, Priority, ActivityDate, Description
                FROM Task
                WHERE WhoId = :leadId AND Status NOT IN ('Completed', 'Cancelled')
                ORDER BY ActivityDate ASC NULLS LAST
                LIMIT 5
            ]));
        } catch (Exception e) { related.put('tasks_error', e.getMessage()); }

        return related;
    }

    // ─── Helpers ──────────────────────────────────────────────────────────────

    private List<Map<String, Object>> convertToMapList(List<SObject> records) {
        List<Map<String, Object>> result = new List<Map<String, Object>>();
        for (SObject record : records) {
            result.add(record.getPopulatedFieldsAsMap());
        }
        return result;
    }

    private List<Map<String, Object>> convertOCRToMapList(List<OpportunityContactRole> roles) {
        List<Map<String, Object>> result = new List<Map<String, Object>>();
        for (OpportunityContactRole ocr : roles) {
            Map<String, Object> row = new Map<String, Object>{
                'contactId' => ocr.ContactId,
                'role'      => ocr.Role,
                'isPrimary' => ocr.IsPrimary
            };
            if (ocr.Contact != null) {
                row.put('name',  ocr.Contact.Name);
                row.put('title', ocr.Contact.Title);
                row.put('email', ocr.Contact.Email);
                row.put('phone', ocr.Contact.Phone);
            }
            result.add(row);
        }
        return result;
    }

    private String extractExternalId(Map<String, Object> sfRecord, String objectApiName) {
        Object sourceId = sfRecord.get('SourceSystemIdentifier__c');
        if (sourceId != null && String.isNotBlank(String.valueOf(sourceId))) {
            return String.valueOf(sourceId);
        }

        Object extId = sfRecord.get('External_Id__c');
        if (extId != null && String.isNotBlank(String.valueOf(extId))) {
            return String.valueOf(extId);
        }

        Object recordId = sfRecord.get('Id');
        return recordId != null ? String.valueOf(recordId) : '';
    }
}
