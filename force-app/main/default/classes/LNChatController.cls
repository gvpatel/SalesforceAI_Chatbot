public with sharing class LNChatController {

    @AuraEnabled
    public static Map<String, Object> sendMessage(
        String userMessage,
        String recordId,
        String objectApiName,
        String conversationHistoryJson,
        String attachmentJson
    ) {
        try {
            if (String.isBlank(userMessage)) {
                throw new AuraHandledException('User message cannot be empty');
            }

            // All callouts must happen before any DML
            LNChatContextBuilderService contextBuilder = new LNChatContextBuilderService();
            Map<String, Object> contextData = contextBuilder.buildContext(recordId, objectApiName, userMessage);

            List<Map<String, String>> conversationHistory = parseConversationHistory(conversationHistoryJson);

            LNChatLLMService llmService = new LNChatLLMService();
            String llmResponseJson = llmService.chat(conversationHistory, userMessage, contextData, attachmentJson);

            // Inject record IDs into record_summary items using context data (more reliable than LLM)
            llmResponseJson = enrichSummaryRecordIds(llmResponseJson, contextData);

            LNChatResponseDTO responseDTO = LNChatResponseDTO.fromJson(llmResponseJson);

            // DML after all callouts are complete
            String sessionId = getOrCreateSession(recordId, objectApiName);
            saveChatMessage(sessionId, 'user', userMessage, null);
            saveChatMessage(sessionId, 'assistant', llmResponseJson, responseDTO.responseType);

            Map<String, Object> result = new Map<String, Object>{
                'responseType' => responseDTO.responseType,
                'title' => responseDTO.title,
                'summary' => responseDTO.summary,
                'data' => responseDTO.data,
                'actions' => serializeActions(responseDTO.actions),
                'rawJson' => responseDTO.rawJson,
                'sessionId' => sessionId
            };

            return result;

        } catch (AuraHandledException ahe) {
            throw ahe;
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'LNChatController.sendMessage error: ' + e.getMessage() + ' | ' + e.getStackTraceString());
            throw new AuraHandledException('An unexpected error occurred: ' + e.getMessage());
        }
    }

    @AuraEnabled(cacheable=true)
    public static List<Map<String, Object>> getConversationHistory(String recordId) {
        List<Map<String, Object>> messages = new List<Map<String, Object>>();

        if (String.isBlank(recordId)) {
            return messages;
        }

        try {
            List<LNChatSession__c> sessions = [
                SELECT Id
                FROM LNChatSession__c
                WHERE RecordId__c = :recordId
                ORDER BY LastActivityDate__c DESC
                LIMIT 1
            ];

            if (sessions.isEmpty()) {
                return messages;
            }

            String sessionId = sessions[0].Id;

            List<LNChatMessage__c> chatMessages = [
                SELECT Role__c, Content__c, ResponseType__c, CreatedDate
                FROM LNChatMessage__c
                WHERE Session__c = :sessionId
                ORDER BY CreatedDate ASC
                LIMIT 50
            ];

            for (LNChatMessage__c msg : chatMessages) {
                messages.add(new Map<String, Object>{
                    'role' => msg.Role__c,
                    'content' => msg.Content__c,
                    'responseType' => msg.ResponseType__c,
                    'timestamp' => String.valueOf(msg.CreatedDate)
                });
            }

        } catch (Exception e) {
            System.debug(LoggingLevel.WARN, 'getConversationHistory failed: ' + e.getMessage());
        }

        return messages;
    }

    @AuraEnabled(cacheable=true)
    public static Map<String, Object> getActivityTimeline(String recordId) {
        return new LNChatTimelineService().getActivityTimeline(recordId);
    }

    @AuraEnabled
    public static Map<String, Object> executeRecordAction(
        String objectApiName,
        String operation,
        String recordId,
        String fieldsJson,
        String currentPageRecordId,
        Boolean bypassDuplicate
    ) {
        try {
            Map<String, Object> fields = new Map<String, Object>();
            if (String.isNotBlank(fieldsJson)) {
                fields = (Map<String, Object>) JSON.deserializeUntyped(fieldsJson);
            }
            return LNChatRecordActionService.executeAction(objectApiName, operation, recordId, fields, currentPageRecordId, bypassDuplicate == true);
        } catch (AuraHandledException ahe) {
            throw ahe;
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'executeRecordAction error: ' + e.getMessage());
            throw new AuraHandledException('Record action failed: ' + e.getMessage());
        }
    }

    @AuraEnabled
    public static Map<String, Object> searchRecords(
        String objectApiName,
        String filtersJson,
        String columnsJson,
        String orderByField,
        Boolean orderDesc,
        Integer limitRows
    ) {
        try {
            return LNChatSearchService.searchRecords(
                objectApiName, filtersJson, columnsJson, orderByField, orderDesc, limitRows
            );
        } catch (AuraHandledException ahe) {
            throw ahe;
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'searchRecords error: ' + e.getMessage());
            throw new AuraHandledException('Search failed: ' + e.getMessage());
        }
    }

    @AuraEnabled
    public static void sendEmail(String toAddress, String subject, String htmlBody) {
        if (String.isBlank(toAddress) || String.isBlank(htmlBody)) {
            throw new AuraHandledException('Email address and content are required');
        }
        try {
            Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
            mail.setToAddresses(new List<String>{ toAddress });
            mail.setSubject(String.isBlank(subject) ? 'AI Assistant Response' : subject);
            mail.setHtmlBody(htmlBody);
            mail.setSaveAsActivity(false);
            Messaging.sendEmail(new List<Messaging.SingleEmailMessage>{ mail });
        } catch (Exception e) {
            throw new AuraHandledException('Failed to send email: ' + e.getMessage());
        }
    }

    @AuraEnabled
    public static void clearConversationHistory(String recordId) {
        if (String.isBlank(recordId)) {
            return;
        }

        try {
            List<LNChatSession__c> sessions = [
                SELECT Id
                FROM LNChatSession__c
                WHERE RecordId__c = :recordId
                LIMIT 1
            ];

            if (!sessions.isEmpty()) {
                List<LNChatMessage__c> messagesToDelete = [
                    SELECT Id
                    FROM LNChatMessage__c
                    WHERE Session__c = :sessions[0].Id
                ];
                if (!messagesToDelete.isEmpty()) {
                    delete messagesToDelete;
                }
                delete sessions[0];
            }
        } catch (Exception e) {
            throw new AuraHandledException('Failed to clear history: ' + e.getMessage());
        }
    }

    private static String getOrCreateSession(String recordId, String objectApiName) {
        if (String.isBlank(recordId)) {
            return null;
        }

        List<LNChatSession__c> existingSessions = [
            SELECT Id
            FROM LNChatSession__c
            WHERE RecordId__c = :recordId
            LIMIT 1
        ];

        if (!existingSessions.isEmpty()) {
            LNChatSession__c session = existingSessions[0];
            session.LastActivityDate__c = System.now();
            update session;
            return session.Id;
        }

        LNChatSession__c newSession = new LNChatSession__c(
            RecordId__c = recordId,
            ObjectApiName__c = objectApiName,
            LastActivityDate__c = System.now()
        );
        insert newSession;
        return newSession.Id;
    }

    private static void saveChatMessage(String sessionId, String role, String content, String responseType) {
        if (String.isBlank(sessionId)) {
            return;
        }

        try {
            LNChatMessage__c message = new LNChatMessage__c(
                Session__c = sessionId,
                Role__c = role,
                Content__c = content != null && content.length() > 131072 ? content.substring(0, 131072) : content,
                ResponseType__c = responseType
            );
            insert message;
        } catch (Exception e) {
            System.debug(LoggingLevel.WARN, 'saveChatMessage failed: ' + e.getMessage());
        }
    }

    private static List<Map<String, String>> parseConversationHistory(String historyJson) {
        List<Map<String, String>> history = new List<Map<String, String>>();

        if (String.isBlank(historyJson)) {
            return history;
        }

        try {
            List<Object> parsed = (List<Object>) JSON.deserializeUntyped(historyJson);
            for (Object item : parsed) {
                if (item instanceof Map<String, Object>) {
                    Map<String, Object> itemMap = (Map<String, Object>) item;
                    String role = (String) itemMap.get('role');
                    String content = (String) itemMap.get('content');
                    if (String.isNotBlank(role) && String.isNotBlank(content)) {
                        history.add(new Map<String, String>{
                            'role' => role,
                            'content' => content
                        });
                    }
                }
            }
        } catch (Exception e) {
            System.debug(LoggingLevel.WARN, 'parseConversationHistory failed: ' + e.getMessage());
        }

        return history;
    }

    private static List<Map<String, Object>> serializeActions(List<LNChatResponseDTO.ActionDTO> actions) {
        List<Map<String, Object>> result = new List<Map<String, Object>>();
        if (actions == null) {
            return result;
        }
        for (LNChatResponseDTO.ActionDTO action : actions) {
            result.add(new Map<String, Object>{
                'label' => action.label,
                'flowApiName' => action.flowApiName,
                'inputVariables' => action.inputVariables
            });
        }
        return result;
    }

    // Post-process record_summary responses to inject Salesforce record IDs into section items.
    // The LLM has the IDs in context but may not reliably include them — we look them up here instead.
    private static String enrichSummaryRecordIds(String responseJson, Map<String, Object> contextData) {
        if (String.isBlank(responseJson) || contextData == null) return responseJson;
        try {
            Map<String, Object> response = (Map<String, Object>) JSON.deserializeUntyped(responseJson);
            if ((String) response.get('responseType') != 'record_summary') return responseJson;

            // Build name/subject → Id lookup across all related record lists
            Map<String, String> nameToId = new Map<String, String>();

            Map<String, Object> related = (Map<String, Object>) contextData.get('relatedRecords');
            if (related != null) {
                for (String key : related.keySet()) {
                    Object val = related.get(key);
                    if (!(val instanceof List<Object>)) continue;
                    for (Object obj : (List<Object>) val) {
                        if (!(obj instanceof Map<String, Object>)) continue;
                        Map<String, Object> rec = (Map<String, Object>) obj;
                        String recId = (String) rec.get('Id');
                        if (String.isBlank(recId)) continue;
                        // Name field (Account, Opportunity, Case, Order, Contract, Quote)
                        String recName = (String) rec.get('Name');
                        if (String.isNotBlank(recName)) nameToId.put(recName.toLowerCase(), recId);
                        // Subject (Task)
                        String subject = (String) rec.get('Subject');
                        if (String.isNotBlank(subject)) nameToId.put(subject.toLowerCase(), recId);
                        // Contact: FirstName + LastName
                        String lastName = (String) rec.get('LastName');
                        if (String.isNotBlank(lastName)) {
                            String firstName = (String) rec.get('FirstName');
                            String full = (String.isNotBlank(firstName) ? firstName + ' ' : '') + lastName;
                            nameToId.put(full.toLowerCase(), recId);
                        }
                    }
                }
            }

            // Also include the main record itself
            Map<String, Object> sfRecord = (Map<String, Object>) contextData.get('salesforceRecord');
            if (sfRecord != null) {
                String recId = (String) sfRecord.get('Id');
                String recName = (String) sfRecord.get('Name');
                if (String.isNotBlank(recId) && String.isNotBlank(recName)) {
                    nameToId.put(recName.toLowerCase(), recId);
                }
            }

            if (nameToId.isEmpty()) return responseJson;

            // Walk sections → items and inject missing recordIds
            Map<String, Object> data = (Map<String, Object>) response.get('data');
            if (data == null) return responseJson;
            List<Object> sections = (List<Object>) data.get('sections');
            if (sections == null) return responseJson;

            Boolean modified = false;
            for (Object secObj : sections) {
                if (!(secObj instanceof Map<String, Object>)) continue;
                List<Object> items = (List<Object>) ((Map<String, Object>) secObj).get('items');
                if (items == null) continue;
                for (Object itmObj : items) {
                    if (!(itmObj instanceof Map<String, Object>)) continue;
                    Map<String, Object> item = (Map<String, Object>) itmObj;
                    if (String.isNotBlank((String) item.get('recordId'))) continue;
                    String itemName = (String) item.get('name');
                    if (String.isBlank(itemName)) continue;
                    String foundId = nameToId.get(itemName.toLowerCase());
                    if (String.isNotBlank(foundId)) {
                        item.put('recordId', foundId);
                        modified = true;
                    }
                }
            }

            return modified ? JSON.serialize(response) : responseJson;

        } catch (Exception e) {
            System.debug(LoggingLevel.WARN, 'enrichSummaryRecordIds failed: ' + e.getMessage());
            return responseJson;
        }
    }
}
