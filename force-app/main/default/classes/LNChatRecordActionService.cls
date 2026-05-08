public with sharing class LNChatRecordActionService {

    private static final Set<String> ALLOWED_OBJECTS = new Set<String>{
        'Account', 'Contact', 'Task', 'Event', 'Case', 'Opportunity', 'Quote'
    };

    public static Map<String, Object> executeAction(
        String objectApiName,
        String operation,
        String recordId,
        Map<String, Object> fields,
        String currentPageRecordId
    ) {
        return executeAction(objectApiName, operation, recordId, fields, currentPageRecordId, false);
    }

    public static Map<String, Object> executeAction(
        String objectApiName,
        String operation,
        String recordId,
        Map<String, Object> fields,
        String currentPageRecordId,
        Boolean bypassDuplicate
    ) {
        if (String.isBlank(objectApiName) || !ALLOWED_OBJECTS.contains(objectApiName)) {
            throw new AuraHandledException('Unsupported object: ' + objectApiName);
        }
        if (String.isBlank(operation)) {
            throw new AuraHandledException('Operation is required');
        }
        if (fields == null || fields.isEmpty()) {
            throw new AuraHandledException('No fields provided');
        }

        String opLower = operation.toLowerCase();
        Boolean skipDupCheck = bypassDuplicate == true;

        // For UPDATE: check ambiguity only when not bypassing and not the current page record
        Boolean isCurrentPageRecord = String.isNotBlank(currentPageRecordId)
            && String.isNotBlank(recordId)
            && currentPageRecordId.equals(recordId);

        if (!skipDupCheck && opLower == 'update' && String.isNotBlank(recordId) && !isCurrentPageRecord) {
            try {
                List<Map<String, Object>> ambiguous = findAmbiguousTargets(objectApiName, recordId);
                if (!ambiguous.isEmpty()) {
                    return new Map<String, Object>{
                        'success'     => false,
                        'isDuplicate' => true,
                        'isAmbiguous' => true,
                        'duplicates'  => ambiguous
                    };
                }
            } catch (Exception e) {
                System.debug(LoggingLevel.WARN, 'Ambiguous target check failed: ' + e.getMessage());
            }
        }

        // Check for value collisions — skip when user has chosen to bypass
        if (!skipDupCheck) {
            String excludeId = String.isNotBlank(recordId) ? recordId : 'NONE_ID';
            List<Map<String, Object>> duplicates = findDuplicates(objectApiName, fields, excludeId);
            if (!duplicates.isEmpty()) {
                return new Map<String, Object>{
                    'success'     => false,
                    'isDuplicate' => true,
                    'isAmbiguous' => false,
                    'duplicates'  => duplicates
                };
            }
        }

        // Event: StartDateTime is a read-only alias — remap to writable ActivityDateTime
        if (objectApiName == 'Event' && fields.containsKey('StartDateTime')) {
            fields.put('ActivityDateTime', fields.get('StartDateTime'));
            fields.remove('StartDateTime');
        }

        // Event requires DurationInMinutes — compute from ActivityDateTime/EndDateTime if absent
        if (objectApiName == 'Event' && !fields.containsKey('DurationInMinutes')) {
            String startStr = strVal(fields, 'ActivityDateTime');
            String endStr   = strVal(fields, 'EndDateTime');
            Integer mins = 60;
            if (String.isNotBlank(startStr) && String.isNotBlank(endStr)) {
                try {
                    DateTime startDt = DateTime.valueOf(startStr.replace('T', ' '));
                    DateTime endDt   = DateTime.valueOf(endStr.replace('T', ' '));
                    Integer computed = (Integer)((endDt.getTime() - startDt.getTime()) / 60000);
                    if (computed > 0) mins = computed;
                } catch (Exception e) { }
            }
            fields.put('DurationInMinutes', mins);
        }

        if (opLower == 'create') {
            return doCreate(objectApiName, fields);
        } else if (opLower == 'update') {
            if (String.isBlank(recordId)) {
                throw new AuraHandledException('recordId is required for update');
            }
            return doUpdate(objectApiName, recordId, fields);
        } else {
            throw new AuraHandledException('Unsupported operation: ' + operation);
        }
    }

    // ─── Ambiguous Target (UPDATE only) ──────────────────────────────────────
    // Checks whether the target record shares key identity fields with other records,
    // meaning the user's request is ambiguous (e.g. "update contact Test" but 2 exist).

    private static List<Map<String, Object>> findAmbiguousTargets(String objectApiName, String recordId) {
        if (objectApiName == 'Contact') {
            List<Contact> targets = [SELECT FirstName, LastName FROM Contact WHERE Id = :recordId LIMIT 1];
            if (targets.isEmpty() || String.isBlank(targets[0].LastName)) return new List<Map<String, Object>>();
            String lastName  = targets[0].LastName;
            String firstName = targets[0].FirstName;
            String soql = 'SELECT Id, Name, Email, Phone, Account.Name FROM Contact'
                        + ' WHERE LastName = :lastName AND Id != :recordId';
            if (String.isNotBlank(firstName)) soql += ' AND FirstName = :firstName';
            soql += ' LIMIT 5';
            List<Map<String, Object>> results = new List<Map<String, Object>>();
            for (Contact c : (List<Contact>) Database.query(soql)) {
                results.add(new Map<String, Object>{
                    'id' => c.Id, 'name' => c.Name, 'email' => c.Email,
                    'phone' => c.Phone, 'account' => c.Account != null ? c.Account.Name : null
                });
            }
            return results;

        } else if (objectApiName == 'Account') {
            List<Account> targets = [SELECT Name FROM Account WHERE Id = :recordId LIMIT 1];
            if (targets.isEmpty() || String.isBlank(targets[0].Name)) return new List<Map<String, Object>>();
            String name = targets[0].Name;
            List<Map<String, Object>> results = new List<Map<String, Object>>();
            for (Account a : [SELECT Id, Name, Phone, BillingCity, BillingState FROM Account WHERE Name = :name AND Id != :recordId LIMIT 5]) {
                results.add(new Map<String, Object>{
                    'id' => a.Id, 'name' => a.Name, 'phone' => a.Phone,
                    'city' => a.BillingCity, 'state' => a.BillingState
                });
            }
            return results;

        } else if (objectApiName == 'Opportunity') {
            List<Opportunity> targets = [SELECT Name, AccountId FROM Opportunity WHERE Id = :recordId LIMIT 1];
            if (targets.isEmpty() || String.isBlank(targets[0].Name)) return new List<Map<String, Object>>();
            String name      = targets[0].Name;
            String accountId = targets[0].AccountId;
            List<Map<String, Object>> results = new List<Map<String, Object>>();
            for (Opportunity o : [SELECT Id, Name, StageName, CloseDate, Account.Name FROM Opportunity WHERE Name = :name AND AccountId = :accountId AND Id != :recordId LIMIT 5]) {
                results.add(new Map<String, Object>{
                    'id' => o.Id, 'name' => o.Name, 'stage' => o.StageName,
                    'close' => String.valueOf(o.CloseDate), 'account' => o.Account != null ? o.Account.Name : null
                });
            }
            return results;

        } else if (objectApiName == 'Quote') {
            List<Quote> targets = [SELECT Name, OpportunityId FROM Quote WHERE Id = :recordId LIMIT 1];
            if (targets.isEmpty() || String.isBlank(targets[0].Name)) return new List<Map<String, Object>>();
            String name  = targets[0].Name;
            String oppId = targets[0].OpportunityId;
            List<Map<String, Object>> results = new List<Map<String, Object>>();
            for (Quote q : [SELECT Id, Name, Status, ExpirationDate FROM Quote WHERE Name = :name AND OpportunityId = :oppId AND Id != :recordId LIMIT 5]) {
                results.add(new Map<String, Object>{
                    'id' => q.Id, 'name' => q.Name, 'status' => q.Status,
                    'expiry' => q.ExpirationDate != null ? String.valueOf(q.ExpirationDate) : null
                });
            }
            return results;

        } else if (objectApiName == 'Lead') {
            List<Lead> targets = [SELECT FirstName, LastName, Company FROM Lead WHERE Id = :recordId LIMIT 1];
            if (targets.isEmpty() || String.isBlank(targets[0].LastName)) return new List<Map<String, Object>>();
            String lastName  = targets[0].LastName;
            String firstName = targets[0].FirstName;
            String soql = 'SELECT Id, Name, Email, Phone, Company FROM Lead'
                        + ' WHERE LastName = :lastName AND IsConverted = false AND Id != :recordId';
            if (String.isNotBlank(firstName)) soql += ' AND FirstName = :firstName';
            soql += ' LIMIT 5';
            List<Map<String, Object>> results = new List<Map<String, Object>>();
            for (Lead l : (List<Lead>) Database.query(soql)) {
                results.add(new Map<String, Object>{
                    'id' => l.Id, 'name' => l.Name, 'email' => l.Email,
                    'phone' => l.Phone, 'company' => l.Company
                });
            }
            return results;

        } else if (objectApiName == 'Event') {
            List<Event> targets = [SELECT Subject FROM Event WHERE Id = :recordId LIMIT 1];
            if (targets.isEmpty() || String.isBlank(targets[0].Subject)) return new List<Map<String, Object>>();
            String subject = targets[0].Subject;
            List<Map<String, Object>> results = new List<Map<String, Object>>();
            for (Event e : [
                SELECT Id, Subject, StartDateTime, EndDateTime
                FROM Event
                WHERE Subject = :subject AND StartDateTime >= TODAY AND Id != :recordId
                LIMIT 5
            ]) {
                results.add(new Map<String, Object>{
                    'id'      => e.Id,
                    'name'    => e.Subject,
                    'start'   => e.StartDateTime != null ? String.valueOf(e.StartDateTime) : null,
                    'end'     => e.EndDateTime   != null ? String.valueOf(e.EndDateTime)   : null
                });
            }
            return results;
        }

        return new List<Map<String, Object>>();
    }

    // ─── Duplicate Detection ──────────────────────────────────────────────────

    private static List<Map<String, Object>> findDuplicates(
        String objectApiName,
        Map<String, Object> fields,
        String excludeId
    ) {
        try {
            if (objectApiName == 'Account')     return findAccountDuplicates(fields, excludeId);
            if (objectApiName == 'Contact')     return findContactDuplicates(fields, excludeId);
            if (objectApiName == 'Lead')        return findLeadDuplicates(fields, excludeId);
            if (objectApiName == 'Opportunity') return findOpportunityDuplicates(fields, excludeId);
            if (objectApiName == 'Case')        return findCaseDuplicates(fields, excludeId);
            if (objectApiName == 'Quote')       return findQuoteDuplicates(fields, excludeId);
            if (objectApiName == 'Event')       return findEventDuplicates(fields, excludeId);
        } catch (Exception e) {
            System.debug(LoggingLevel.WARN, 'Duplicate check failed for ' + objectApiName + ': ' + e.getMessage());
        }
        return new List<Map<String, Object>>();
    }

    private static List<Map<String, Object>> findAccountDuplicates(Map<String, Object> fields, String excludeId) {
        String name = strVal(fields, 'Name');
        if (String.isBlank(name)) return new List<Map<String, Object>>();

        List<Map<String, Object>> results = new List<Map<String, Object>>();
        for (Account a : [
            SELECT Id, Name, Phone, BillingCity, BillingState, Website
            FROM Account
            WHERE Name = :name AND Id != :excludeId
            LIMIT 5
        ]) {
            results.add(new Map<String, Object>{
                'id'      => a.Id,
                'name'    => a.Name,
                'phone'   => a.Phone,
                'city'    => a.BillingCity,
                'state'   => a.BillingState,
                'website' => a.Website
            });
        }
        return results;
    }

    private static List<Map<String, Object>> findContactDuplicates(Map<String, Object> fields, String excludeId) {
        List<Map<String, Object>> results = new List<Map<String, Object>>();

        // Email is strongest signal
        String email = strVal(fields, 'Email');
        if (String.isNotBlank(email)) {
            for (Contact c : [
                SELECT Id, Name, Email, Phone, Account.Name
                FROM Contact
                WHERE Email = :email AND Id != :excludeId
                LIMIT 5
            ]) {
                results.add(new Map<String, Object>{
                    'id'      => c.Id,
                    'name'    => c.Name,
                    'email'   => c.Email,
                    'phone'   => c.Phone,
                    'account' => c.Account != null ? c.Account.Name : null
                });
            }
        }

        // Name match scoped to the same account — only a duplicate if same name within same account
        if (results.isEmpty()) {
            String firstName = strVal(fields, 'FirstName');
            String lastName  = strVal(fields, 'LastName');
            String accountId = strVal(fields, 'AccountId');
            if (String.isNotBlank(lastName)) {
                String soql = 'SELECT Id, Name, Email, Phone, Account.Name FROM Contact'
                    + ' WHERE LastName = :lastName AND Id != :excludeId';
                if (String.isNotBlank(firstName)) {
                    soql += ' AND FirstName = :firstName';
                }
                // Scope to same account when AccountId is provided; otherwise skip name-only check
                if (String.isNotBlank(accountId)) {
                    soql += ' AND AccountId = :accountId';
                } else {
                    // No account context — skip name-only cross-account dup check
                    return results;
                }
                soql += ' LIMIT 5';
                for (Contact c : (List<Contact>) Database.query(soql)) {
                    results.add(new Map<String, Object>{
                        'id'      => c.Id,
                        'name'    => c.Name,
                        'email'   => c.Email,
                        'phone'   => c.Phone,
                        'account' => c.Account != null ? c.Account.Name : null
                    });
                }
            }
        }

        return results;
    }

    private static List<Map<String, Object>> findLeadDuplicates(Map<String, Object> fields, String excludeId) {
        List<Map<String, Object>> results = new List<Map<String, Object>>();

        String email = strVal(fields, 'Email');
        if (String.isNotBlank(email)) {
            for (Lead l : [
                SELECT Id, Name, Email, Phone, Company
                FROM Lead
                WHERE Email = :email AND Id != :excludeId AND IsConverted = false
                LIMIT 5
            ]) {
                results.add(new Map<String, Object>{
                    'id'      => l.Id,
                    'name'    => l.Name,
                    'email'   => l.Email,
                    'phone'   => l.Phone,
                    'company' => l.Company
                });
            }
        }

        if (results.isEmpty()) {
            String lastName  = strVal(fields, 'LastName');
            String company   = strVal(fields, 'Company');
            if (String.isNotBlank(lastName) && String.isNotBlank(company)) {
                for (Lead l : [
                    SELECT Id, Name, Email, Phone, Company
                    FROM Lead
                    WHERE LastName = :lastName AND Company = :company AND Id != :excludeId AND IsConverted = false
                    LIMIT 5
                ]) {
                    results.add(new Map<String, Object>{
                        'id'      => l.Id,
                        'name'    => l.Name,
                        'email'   => l.Email,
                        'phone'   => l.Phone,
                        'company' => l.Company
                    });
                }
            }
        }

        return results;
    }

    private static List<Map<String, Object>> findOpportunityDuplicates(Map<String, Object> fields, String excludeId) {
        String name      = strVal(fields, 'Name');
        String accountId = strVal(fields, 'AccountId');
        if (String.isBlank(name) || String.isBlank(accountId)) return new List<Map<String, Object>>();

        List<Map<String, Object>> results = new List<Map<String, Object>>();
        for (Opportunity o : [
            SELECT Id, Name, StageName, CloseDate, Amount, Account.Name
            FROM Opportunity
            WHERE Name = :name AND AccountId = :accountId AND Id != :excludeId
            LIMIT 5
        ]) {
            results.add(new Map<String, Object>{
                'id'      => o.Id,
                'name'    => o.Name,
                'stage'   => o.StageName,
                'close'   => String.valueOf(o.CloseDate),
                'amount'  => o.Amount != null ? String.valueOf(o.Amount) : null,
                'account' => o.Account != null ? o.Account.Name : null
            });
        }
        return results;
    }

    private static List<Map<String, Object>> findCaseDuplicates(Map<String, Object> fields, String excludeId) {
        String subject   = strVal(fields, 'Subject');
        String accountId = strVal(fields, 'AccountId');
        if (String.isBlank(subject) || String.isBlank(accountId)) return new List<Map<String, Object>>();

        List<Map<String, Object>> results = new List<Map<String, Object>>();
        for (Case c : [
            SELECT Id, CaseNumber, Subject, Status, Priority, Account.Name
            FROM Case
            WHERE Subject = :subject AND AccountId = :accountId AND Id != :excludeId
            LIMIT 5
        ]) {
            results.add(new Map<String, Object>{
                'id'      => c.Id,
                'number'  => c.CaseNumber,
                'subject' => c.Subject,
                'status'  => c.Status,
                'account' => c.Account != null ? c.Account.Name : null
            });
        }
        return results;
    }

    private static List<Map<String, Object>> findQuoteDuplicates(Map<String, Object> fields, String excludeId) {
        String name   = strVal(fields, 'Name');
        String oppId  = strVal(fields, 'OpportunityId');
        if (String.isBlank(name) || String.isBlank(oppId)) return new List<Map<String, Object>>();

        List<Map<String, Object>> results = new List<Map<String, Object>>();
        for (Quote q : [
            SELECT Id, Name, Status, ExpirationDate, OpportunityId
            FROM Quote
            WHERE Name = :name AND OpportunityId = :oppId AND Id != :excludeId
            LIMIT 5
        ]) {
            results.add(new Map<String, Object>{
                'id'     => q.Id,
                'name'   => q.Name,
                'status' => q.Status,
                'expiry' => q.ExpirationDate != null ? String.valueOf(q.ExpirationDate) : null
            });
        }
        return results;
    }

    private static List<Map<String, Object>> findEventDuplicates(Map<String, Object> fields, String excludeId) {
        String subject  = strVal(fields, 'Subject');
        String startStr = strVal(fields, 'StartDateTime');
        if (String.isBlank(subject) || String.isBlank(startStr)) return new List<Map<String, Object>>();
        DateTime startDt;
        try { startDt = DateTime.valueOf(startStr); } catch (Exception e) { return new List<Map<String, Object>>(); }

        List<Map<String, Object>> results = new List<Map<String, Object>>();
        for (Event e : [
            SELECT Id, Subject, StartDateTime, EndDateTime
            FROM Event
            WHERE Subject = :subject AND StartDateTime = :startDt AND Id != :excludeId
            LIMIT 5
        ]) {
            results.add(new Map<String, Object>{
                'id'    => e.Id,
                'name'  => e.Subject,
                'start' => e.StartDateTime != null ? String.valueOf(e.StartDateTime) : null,
                'end'   => e.EndDateTime   != null ? String.valueOf(e.EndDateTime)   : null
            });
        }
        return results;
    }

    // ─── DML ──────────────────────────────────────────────────────────────────

    private static Map<String, Object> doCreate(String objectApiName, Map<String, Object> fields) {
        SObject record = Schema.getGlobalDescribe().get(objectApiName).newSObject();
        applyFields(record, objectApiName, fields);
        insert record;
        return new Map<String, Object>{ 'recordId' => record.Id, 'success' => true };
    }

    private static Map<String, Object> doUpdate(String objectApiName, String recordId, Map<String, Object> fields) {
        SObject record = Schema.getGlobalDescribe().get(objectApiName).newSObject(recordId);
        applyFields(record, objectApiName, fields);
        update record;
        return new Map<String, Object>{ 'recordId' => recordId, 'success' => true };
    }

    private static void applyFields(SObject record, String objectApiName, Map<String, Object> fields) {
        Map<String, Schema.SObjectField> fieldMap =
            Schema.getGlobalDescribe().get(objectApiName).getDescribe().fields.getMap();

        for (String fieldName : fields.keySet()) {
            Schema.SObjectField fieldToken = fieldMap.get(fieldName.toLowerCase());
            if (fieldToken == null) continue;

            Schema.DescribeFieldResult fd = fieldToken.getDescribe();
            if (!fd.isCreateable()) continue;

            Object rawValue = fields.get(fieldName);
            if (rawValue == null) continue;

            String strValue = String.valueOf(rawValue);
            if (String.isBlank(strValue)) continue;

            try {
                Schema.DisplayType ft = fd.getType();
                if (ft == Schema.DisplayType.DATE) {
                    record.put(fieldName, Date.valueOf(strValue));
                } else if (ft == Schema.DisplayType.DATETIME) {
                    record.put(fieldName, DateTime.valueOf(strValue.replace('T', ' ')));
                } else if (ft == Schema.DisplayType.DOUBLE
                        || ft == Schema.DisplayType.CURRENCY
                        || ft == Schema.DisplayType.PERCENT) {
                    record.put(fieldName, Double.valueOf(strValue));
                } else if (ft == Schema.DisplayType.INTEGER) {
                    record.put(fieldName, Integer.valueOf(strValue));
                } else if (ft == Schema.DisplayType.BOOLEAN) {
                    record.put(fieldName, Boolean.valueOf(strValue));
                } else {
                    record.put(fieldName, strValue);
                }
            } catch (Exception e) {
                System.debug(LoggingLevel.WARN, 'LNChatRecordActionService: skipping field ' + fieldName + ': ' + e.getMessage());
            }
        }
    }

    // ─── Utility ──────────────────────────────────────────────────────────────

    private static String strVal(Map<String, Object> fields, String key) {
        Object val = fields.get(key);
        return val != null ? String.valueOf(val).trim() : '';
    }
}
