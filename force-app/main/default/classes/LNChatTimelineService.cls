/**
 * Assembles a chronological activity feed (Tasks + Events) for an Account,
 * for the horizontal activity-timeline LWC.
 *
 * Defensive, like LNChatERPService/LNChatBIService — never throws; returns
 * { available, truncated, activities:[ {id, sobjectType, subject, dateMs, type, source} ] }.
 *
 * SOURCE detection is org-safe: integration fields (Gong/SalesLoft) are only
 * referenced when they actually exist in the org, so this deploys to orgs that
 * lack those managed packages (every node simply reads "Salesforce" there).
 */
public with sharing class LNChatTimelineService {
  private static final Integer PER_OBJECT_LIMIT = 200;

  // Candidate integration fields → source label. Only the ones present in the org are queried.
  private static final Map<String, String> SOURCE_FIELD_LABEL = new Map<String, String>{
    'Gong__Gong_Call__c' => 'Gong',
    'Gong__Activity_Source__c' => 'Gong',
    'SalesLoft1__SalesLoft_Cadence_Name__c' => 'SalesLoft'
  };

  public Map<String, Object> getActivityTimeline(String recordId) {
    if (String.isBlank(recordId)) {
      return emptyResponse('No record Id provided');
    }
    try {
      List<Object> activities = new List<Object>();
      Boolean truncated = false;

      // ── Tasks ──
      List<String> taskSourceFields = presentSourceFields('Task');
      List<String> taskFields = new List<String>{
        'Id',
        'Subject',
        'ActivityDate',
        'CreatedDate',
        'Type',
        'TaskSubtype'
      };
      taskFields.addAll(taskSourceFields);
      String taskSoql =
        'SELECT ' +
        String.join(taskFields, ', ') +
        ' FROM Task WHERE AccountId = :recordId ORDER BY ActivityDate DESC NULLS LAST LIMIT ' +
        (PER_OBJECT_LIMIT + 1);
      List<SObject> tasks = Database.query(taskSoql);
      truncated = truncated || tasks.size() > PER_OBJECT_LIMIT;
      for (Integer i = 0; i < Math.min(tasks.size(), PER_OBJECT_LIMIT); i++) {
        SObject t = tasks[i];
        activities.add(
          new Map<String, Object>{
            'id' => t.Id,
            'sobjectType' => 'Task',
            'subject' => (String) t.get('Subject'),
            'dateMs' => toMs(t.get('ActivityDate'), t.get('CreatedDate')),
            'type' => taskType(
              (String) t.get('Type'),
              (String) t.get('TaskSubtype')
            ),
            'source' => sourceOf(t, taskSourceFields)
          }
        );
      }

      // ── Events ──
      List<String> eventSourceFields = presentSourceFields('Event');
      List<String> eventFields = new List<String>{
        'Id',
        'Subject',
        'ActivityDateTime',
        'CreatedDate'
      };
      eventFields.addAll(eventSourceFields);
      String eventSoql =
        'SELECT ' +
        String.join(eventFields, ', ') +
        ' FROM Event WHERE AccountId = :recordId ORDER BY ActivityDateTime DESC NULLS LAST LIMIT ' +
        (PER_OBJECT_LIMIT + 1);
      List<SObject> events = Database.query(eventSoql);
      truncated = truncated || events.size() > PER_OBJECT_LIMIT;
      for (Integer i = 0; i < Math.min(events.size(), PER_OBJECT_LIMIT); i++) {
        SObject e = events[i];
        activities.add(
          new Map<String, Object>{
            'id' => e.Id,
            'sobjectType' => 'Event',
            'subject' => (String) e.get('Subject'),
            'dateMs' => toMs(e.get('ActivityDateTime'), e.get('CreatedDate')),
            'type' => 'meeting',
            'source' => sourceOf(e, eventSourceFields)
          }
        );
      }

      return new Map<String, Object>{
        'available' => true,
        'truncated' => truncated,
        'activities' => activities
      };
    } catch (Exception ex) {
      System.debug(
        LoggingLevel.ERROR,
        'LNChatTimelineService error: ' + ex.getMessage()
      );
      return emptyResponse(ex.getMessage());
    }
  }

  /** Integration source fields that actually exist on the object in this org. */
  private List<String> presentSourceFields(String objType) {
    List<String> present = new List<String>();
    Schema.SObjectType sot = Schema.getGlobalDescribe().get(objType);
    if (sot == null) {
      return present;
    }
    Map<String, Schema.SObjectField> fmap = sot.getDescribe().fields.getMap();
    for (String f : SOURCE_FIELD_LABEL.keySet()) {
      if (fmap.containsKey(f.toLowerCase())) {
        present.add(f);
      }
    }
    return present;
  }

  private String sourceOf(SObject rec, List<String> sourceFields) {
    for (String f : sourceFields) {
      if (rec.get(f) != null) {
        return SOURCE_FIELD_LABEL.get(f);
      }
    }
    return 'Salesforce';
  }

  private String taskType(String type, String subtype) {
    String t = (type == null ? '' : type.toLowerCase());
    String s = (subtype == null ? '' : subtype.toLowerCase());
    if (t.contains('call') || s.contains('call')) {
      return 'call';
    }
    if (t.contains('email') || s.contains('email')) {
      return 'email';
    }
    return 'other';
  }

  /** ActivityDate (Date) or ActivityDateTime (Datetime) → epoch ms; falls back to CreatedDate. */
  private Long toMs(Object activityDate, Object createdDate) {
    if (activityDate instanceof Datetime) {
      return ((Datetime) activityDate).getTime();
    }
    if (activityDate instanceof Date) {
      return Datetime.newInstance(
          (Date) activityDate,
          Time.newInstance(0, 0, 0, 0)
        )
        .getTime();
    }
    if (createdDate instanceof Datetime) {
      return ((Datetime) createdDate).getTime();
    }
    return null;
  }

  private Map<String, Object> emptyResponse(String reason) {
    return new Map<String, Object>{
      'available' => false,
      'reason' => reason,
      'activities' => new List<Object>()
    };
  }
}
