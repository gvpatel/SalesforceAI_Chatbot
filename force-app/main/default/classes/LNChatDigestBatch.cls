public class LNChatDigestBatch implements Database.Batchable<SObject>, Database.AllowsCallouts {
  public Database.QueryLocator start(Database.BatchableContext bc) {
    return Database.getQueryLocator(
      'SELECT Id, Name, Email, FirstName, LastName ' +
        'FROM User ' +
        'WHERE IsActive = true ' +
        'AND Email != null ' +
        'AND Id IN (SELECT OwnerId FROM Account)'
    );
  }

  public void execute(Database.BatchableContext bc, List<SObject> scope) {
    User rep = (User) scope[0];

    List<Account> accounts = [
      SELECT Id, Name, LastActivityDate
      FROM Account
      WHERE OwnerId = :rep.Id
      ORDER BY Name
      LIMIT 50
    ];
    if (accounts.isEmpty())
      return;

    Set<Id> accountIds = new Map<Id, Account>(accounts).keySet();

    Map<Id, List<Opportunity>> oppsByAccount = new Map<Id, List<Opportunity>>();
    Map<Id, List<Task>> tasksByAccount = new Map<Id, List<Task>>();
    Map<Id, List<Case>> casesByAccount = new Map<Id, List<Case>>();

    for (Opportunity o : [
      SELECT
        Id,
        AccountId,
        Name,
        StageName,
        Amount,
        CloseDate,
        LastStageChangeDate
      FROM Opportunity
      WHERE AccountId IN :accountIds AND IsClosed = FALSE
    ]) {
      if (!oppsByAccount.containsKey(o.AccountId))
        oppsByAccount.put(o.AccountId, new List<Opportunity>());
      oppsByAccount.get(o.AccountId).add(o);
    }

    for (Task t : [
      SELECT Id, WhatId, Subject, ActivityDate
      FROM Task
      WHERE
        WhatId IN :accountIds
        AND Status NOT IN ('Completed', 'Cancelled')
        AND ActivityDate < TODAY
    ]) {
      if (!tasksByAccount.containsKey(t.WhatId))
        tasksByAccount.put(t.WhatId, new List<Task>());
      tasksByAccount.get(t.WhatId).add(t);
    }

    for (Case c : [
      SELECT Id, AccountId, Subject, Priority
      FROM Case
      WHERE AccountId IN :accountIds AND Status NOT IN ('Closed', 'Resolved')
    ]) {
      if (!casesByAccount.containsKey(c.AccountId))
        casesByAccount.put(c.AccountId, new List<Case>());
      casesByAccount.get(c.AccountId).add(c);
    }

    List<Map<String, Object>> scoredAccounts = new List<Map<String, Object>>();

    for (Account a : accounts) {
      Integer daysSinceActivity = 999;
      if (a.LastActivityDate != null) {
        daysSinceActivity = a.LastActivityDate.daysBetween(Date.today());
      }

      List<Opportunity> opps = oppsByAccount.containsKey(a.Id)
        ? oppsByAccount.get(a.Id)
        : new List<Opportunity>();
      List<Task> tasks = tasksByAccount.containsKey(a.Id)
        ? tasksByAccount.get(a.Id)
        : new List<Task>();
      List<Case> cases = casesByAccount.containsKey(a.Id)
        ? casesByAccount.get(a.Id)
        : new List<Case>();

      Integer maxStalledDays = 0;
      Decimal totalPipeline = 0;
      String nearestOpp = '';
      for (Opportunity o : opps) {
        if (o.Amount != null)
          totalPipeline += o.Amount;
        if (o.LastStageChangeDate != null) {
          Integer stalledDays = o.LastStageChangeDate.date()
            .daysBetween(Date.today());
          if (stalledDays > maxStalledDays)
            maxStalledDays = stalledDays;
        }
        if (String.isBlank(nearestOpp)) {
          nearestOpp =
            o.Name +
            ' (' +
            o.StageName +
            ', $' +
            (o.Amount != null ? String.valueOf(o.Amount.intValue()) : '0') +
            ')';
        }
      }

      String score = 'GREEN';
      if (
        daysSinceActivity > 45 ||
        tasks.size() >= 3 ||
        cases.size() >= 2 ||
        maxStalledDays > 30
      ) {
        score = 'RED';
      } else if (
        daysSinceActivity > 21 ||
        !tasks.isEmpty() ||
        !cases.isEmpty() ||
        maxStalledDays > 15
      ) {
        score = 'YELLOW';
      }

      scoredAccounts.add(
        new Map<String, Object>{
          'id' => a.Id,
          'name' => a.Name,
          'score' => score,
          'daysSinceActivity' => daysSinceActivity,
          'overdueTaskCount' => tasks.size(),
          'openCaseCount' => cases.size(),
          'openOppCount' => opps.size(),
          'totalPipeline' => totalPipeline,
          'nearestOpp' => nearestOpp,
          'stalledDays' => maxStalledDays
        }
      );
    }

    // Skip rep if all accounts are green — no email, no LLM call
    Boolean hasIssues = false;
    for (Map<String, Object> acc : scoredAccounts) {
      if ((String) acc.get('score') != 'GREEN') {
        hasIssues = true;
        break;
      }
    }
    if (!hasIssues)
      return;

    String accountLines = '';
    for (Map<String, Object> acc : scoredAccounts) {
      accountLines += '- ' + acc.get('name') + ' [' + acc.get('score') + ']';
      if (String.isNotBlank((String) acc.get('nearestOpp'))) {
        accountLines += ' | Opp: ' + acc.get('nearestOpp');
      }
      if ((Integer) acc.get('overdueTaskCount') > 0) {
        accountLines += ' | Overdue tasks: ' + acc.get('overdueTaskCount');
      }
      if ((Integer) acc.get('openCaseCount') > 0) {
        accountLines += ' | Open cases: ' + acc.get('openCaseCount');
      }
      accountLines +=
        ' | Last activity: ' +
        acc.get('daysSinceActivity') +
        'd ago\n';
    }

    String llmPrompt =
      'You are a sales coaching assistant. A sales rep\'s accounts are listed below with health scores.\n\n' +
      'Rep: ' +
      rep.FirstName +
      ' ' +
      rep.LastName +
      '\n' +
      'Digest date: ' +
      String.valueOf(Date.today()) +
      '\n\n' +
      'Accounts:\n' +
      accountLines +
      '\n' +
      'Write:\n' +
      '1. A one-sentence pipeline health summary (total open pipeline value, deals closing this month).\n' +
      '2. Top 3 Actions This Week — specific named actions with account name and exact reason.\n' +
      '3. One short risk note per RED account.\n\n' +
      'Be direct and specific. Use the rep\'s actual account names and data. Plain text only.';

    String llmInsights = callLLM(llmPrompt);

    // Status colour + opportunity fallback for the PDF rendering
    for (Map<String, Object> a : scoredAccounts) {
      String sc = (String) a.get('score');
      a.put(
        'scoreColor',
        sc == 'RED' ? '#c00' : sc == 'YELLOW' ? '#dd7a01' : '#2e844a'
      );
      if (String.isBlank((String) a.get('nearestOpp'))) {
        a.put('nearestOpp', '—');
      }
    }

    String html = buildHtml(rep, scoredAccounts, llmInsights);

    // Render the same digest as a PDF and attach it (inline HTML body is kept too)
    Blob pdfBlob = renderDigestPdf(rep, scoredAccounts, llmInsights);
    Messaging.EmailFileAttachment pdf = new Messaging.EmailFileAttachment();
    pdf.setFileName('Account_Digest_' + Date.today().format() + '.pdf');
    pdf.setBody(pdfBlob);
    pdf.setContentType('application/pdf');

    Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
    mail.setToAddresses(new List<String>{ rep.Email });
    mail.setSubject('Your Account Digest — ' + Date.today().format());
    mail.setHtmlBody(html);
    mail.setFileAttachments(new List<Messaging.EmailFileAttachment>{ pdf });
    mail.setSaveAsActivity(false);
    Messaging.sendEmail(new List<Messaging.SingleEmailMessage>{ mail });
  }

  /** Renders the LNChatDigestPdf Visualforce page to PDF via static data hand-off. */
  private Blob renderDigestPdf(
    User rep,
    List<Map<String, Object>> scoredAccounts,
    String llmInsights
  ) {
    LNChatDigestPdfController.repNameVal = rep.FirstName + ' ' + rep.LastName;
    LNChatDigestPdfController.digestDateVal = Date.today().format();
    LNChatDigestPdfController.insightsVal = llmInsights;
    LNChatDigestPdfController.rowsVal = scoredAccounts;

    if (Test.isRunningTest()) {
      // getContentAsPDF returns unreliable bytes in tests — use a placeholder.
      return Blob.valueOf('TEST-PDF');
    }
    try {
      return Page.LNChatDigestPdf.getContentAsPDF();
    } catch (Exception e) {
      System.debug(
        LoggingLevel.WARN,
        'Digest PDF render failed: ' + e.getMessage()
      );
      // Fall back to attaching the HTML so the email still carries a file.
      return Blob.valueOf(buildHtml(rep, scoredAccounts, llmInsights));
    }
  }

  public void finish(Database.BatchableContext bc) {
    System.debug(LoggingLevel.INFO, 'LNChatDigestBatch completed.');
  }

  private String callLLM(String prompt) {
    try {
      List<AI_Config__mdt> configs = [
        SELECT ApiKey__c, ModelName__c
        FROM AI_Config__mdt
        WHERE DeveloperName = 'Default'
        LIMIT 1
      ];
      if (configs.isEmpty())
        return '';

      String apiKey = configs[0].ApiKey__c;
      String model = String.isNotBlank(configs[0].ModelName__c)
        ? configs[0].ModelName__c
        : 'gpt-4o';

      Map<String, Object> body = new Map<String, Object>{
        'model' => model,
        'max_completion_tokens' => 600,
        'messages' => new List<Object>{
          new Map<String, Object>{ 'role' => 'user', 'content' => prompt }
        }
      };

      HttpRequest req = new HttpRequest();
      req.setEndpoint('callout:OpenAI_GPT/v1/chat/completions');
      req.setMethod('POST');
      req.setHeader('Content-Type', 'application/json');
      req.setHeader('Authorization', 'Bearer ' + apiKey);
      req.setBody(JSON.serialize(body));
      req.setTimeout(30000);

      HttpResponse res = new Http().send(req);
      Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(
        res.getBody()
      );
      List<Object> choices = (List<Object>) parsed.get('choices');
      if (choices != null && !choices.isEmpty()) {
        Map<String, Object> msg = (Map<String, Object>) ((Map<String, Object>) choices[0])
          .get('message');
        return (String) msg.get('content');
      }
    } catch (Exception e) {
      System.debug(
        LoggingLevel.WARN,
        'LNChatDigestBatch LLM callout failed: ' + e.getMessage()
      );
    }
    return '';
  }

  private String buildHtml(
    User rep,
    List<Map<String, Object>> accounts,
    String llmInsights
  ) {
    String rows = '';
    for (Map<String, Object> a : accounts) {
      String emoji = (String) a.get('score') == 'RED'
        ? '🔴'
        : (String) a.get('score') == 'YELLOW' ? '🟡' : '🟢';
      rows +=
        '<tr>' +
        '<td style="padding:8px 12px;border-bottom:1px solid #eee;">' +
        emoji +
        ' <strong>' +
        a.get('name') +
        '</strong></td>' +
        '<td style="padding:8px 12px;border-bottom:1px solid #eee;">' +
        (String.isNotBlank((String) a.get('nearestOpp'))
          ? (String) a.get('nearestOpp')
          : '—') +
        '</td>' +
        '<td style="padding:8px 12px;border-bottom:1px solid #eee;">' +
        a.get('overdueTaskCount') +
        ' overdue</td>' +
        '<td style="padding:8px 12px;border-bottom:1px solid #eee;">' +
        a.get('openCaseCount') +
        ' cases</td>' +
        '<td style="padding:8px 12px;border-bottom:1px solid #eee;">' +
        a.get('daysSinceActivity') +
        'd ago</td>' +
        '</tr>';
    }

    String insightsBlock = '';
    if (String.isNotBlank(llmInsights)) {
      insightsBlock =
        '<div style="background:#f0f6ff;border-left:4px solid #0176d3;padding:16px;margin-bottom:24px;border-radius:4px;">' +
        '<pre style="white-space:pre-wrap;font-family:Arial,sans-serif;font-size:14px;margin:0;color:#3e3e3c;">' +
        llmInsights.escapeHtml4() +
        '</pre></div>';
    }

    return '<!DOCTYPE html><html><body style="font-family:Arial,sans-serif;max-width:720px;margin:0 auto;color:#3e3e3c;padding:24px;">' +
      '<h2 style="color:#0176d3;margin-bottom:4px;">Account Digest</h2>' +
      '<p style="color:#706e6b;margin-top:0;">' +
      Date.today().format() +
      '</p>' +
      '<p>Hi ' +
      rep.FirstName +
      ', here\'s your account health summary for this week.</p>' +
      insightsBlock +
      '<h3 style="margin-bottom:8px;">Your Accounts</h3>' +
      '<table style="width:100%;border-collapse:collapse;font-size:13px;">' +
      '<thead><tr style="background:#f3f3f3;text-align:left;">' +
      '<th style="padding:8px 12px;">Account</th>' +
      '<th style="padding:8px 12px;">Open Opportunity</th>' +
      '<th style="padding:8px 12px;">Tasks</th>' +
      '<th style="padding:8px 12px;">Cases</th>' +
      '<th style="padding:8px 12px;">Last Activity</th>' +
      '</tr></thead>' +
      '<tbody>' +
      rows +
      '</tbody>' +
      '</table>' +
      '<p style="margin-top:32px;font-size:11px;color:#b0adab;">Sent by AI Assistant · Unsubscribe not available for internal digests</p>' +
      '</body></html>';
  }
}
