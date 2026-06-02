/**
 * Fetches a short, internet-sourced company overview using OpenAI's
 * web-search-capable chat model. Used to enrich Account record summaries
 * with grounded external context.
 *
 * Reuses the existing OpenAI_GPT Named Credential and the AI_Config__mdt
 * ApiKey__c — no separate search vendor or key required.
 *
 * Mirrors the defensive contract of LNChatERPService / LNChatBIService:
 * never throws to the caller — on any error/timeout it returns
 * { available: false, reason: '...' } so the summary degrades gracefully.
 */
public with sharing class LNChatWebService {
  private static final String NAMED_CREDENTIAL = 'callout:OpenAI_GPT';
  // Web-search-capable chat model (built-in browsing). Verify the current id/pricing.
  private static final String SEARCH_MODEL = 'gpt-4o-search-preview';

  /**
   * @param accountName Company name (required)
   * @param website     Account website (optional, sharpens the query)
   * @param location    "City, State" (optional, disambiguates the company)
   * @return { available, answer, sources:[{title,url}] } or { available:false, reason }
   */
  public Map<String, Object> getCompanyOverview(
    String accountName,
    String website,
    String location
  ) {
    if (String.isBlank(accountName)) {
      return getEmptyResponse('No account name provided');
    }

    String apiKey = getApiKey();
    if (String.isBlank(apiKey)) {
      return getEmptyResponse('OpenAI API key not configured');
    }

    try {
      String userPrompt =
        'Find the most recent news and developments about the company "' +
        accountName +
        '"' +
        (String.isNotBlank(location) ? ' located in ' + location : '') +
        (String.isNotBlank(website) ? ' (website: ' + website + ')' : '') +
        '. Focus on the latest notable items from roughly the last 12 months — ' +
        'announcements, press releases, deals, litigation, leadership changes, awards, expansions. ' +
        'For each item include what happened, when, and the source. ' +
        'If there is little recent news, say so briefly.';

      Map<String, Object> body = new Map<String, Object>{
        'model' => SEARCH_MODEL,
        'web_search_options' => new Map<String, Object>{
          'search_context_size' => 'low'
        },
        'messages' => new List<Object>{
          new Map<String, Object>{
            'role' => 'system',
            'content' => 'You are a news research assistant. Use web search to find the most ' +
            'recent, factual news about the company and cite your sources. Prefer recent items.'
          },
          new Map<String, Object>{ 'role' => 'user', 'content' => userPrompt }
        }
      };

      HttpRequest req = new HttpRequest();
      req.setEndpoint(NAMED_CREDENTIAL + '/v1/chat/completions');
      req.setMethod('POST');
      req.setHeader('Content-Type', 'application/json');
      req.setHeader('Authorization', 'Bearer ' + apiKey);
      req.setBody(JSON.serialize(body));
      req.setTimeout(20000);

      Http http = new Http();
      HttpResponse res = http.send(req);

      if (res.getStatusCode() == 200) {
        return parseResponse(res.getBody());
      }
      return getEmptyResponse(
        'Web search returned status ' + res.getStatusCode()
      );
    } catch (CalloutException ce) {
      System.debug(
        LoggingLevel.WARN,
        'LNChatWebService callout failed: ' + ce.getMessage()
      );
      return getEmptyResponse('Web search unavailable: ' + ce.getMessage());
    } catch (Exception e) {
      System.debug(
        LoggingLevel.ERROR,
        'LNChatWebService unexpected error: ' + e.getMessage()
      );
      return getEmptyResponse('Web search error: ' + e.getMessage());
    }
  }

  /** Parse an OpenAI /v1/chat/completions response: message.content + url_citation annotations. */
  private Map<String, Object> parseResponse(String responseBody) {
    Object parsed = JSON.deserializeUntyped(responseBody);
    if (!(parsed instanceof Map<String, Object>)) {
      return getEmptyResponse('Unexpected web search response');
    }
    Map<String, Object> root = (Map<String, Object>) parsed;

    List<Object> choices = (root.get('choices') instanceof List<Object>)
      ? (List<Object>) root.get('choices')
      : new List<Object>();
    if (choices.isEmpty() || !(choices[0] instanceof Map<String, Object>)) {
      return getEmptyResponse('No web results found');
    }

    Map<String, Object> message = (Map<String, Object>) ((Map<String, Object>) choices[0])
      .get('message');
    if (message == null) {
      return getEmptyResponse('No web results found');
    }

    String answer = (String) message.get('content');
    List<Object> sources = extractSources(message.get('annotations'));

    if (String.isBlank(answer) && sources.isEmpty()) {
      return getEmptyResponse('No web results found');
    }

    return new Map<String, Object>{
      'available' => true,
      'answer' => answer,
      'sources' => sources
    };
  }

  /** Pull { title, url } out of OpenAI url_citation annotations (deduped by URL). */
  private List<Object> extractSources(Object annotationsRaw) {
    List<Object> sources = new List<Object>();
    Set<String> seenUrls = new Set<String>();
    if (!(annotationsRaw instanceof List<Object>)) {
      return sources;
    }
    for (Object a : (List<Object>) annotationsRaw) {
      if (!(a instanceof Map<String, Object>)) {
        continue;
      }
      Map<String, Object> ann = (Map<String, Object>) a;
      if (!(ann.get('url_citation') instanceof Map<String, Object>)) {
        continue;
      }
      Map<String, Object> cit = (Map<String, Object>) ann.get('url_citation');
      String url = (String) cit.get('url');
      if (String.isBlank(url) || seenUrls.contains(url)) {
        continue;
      }
      seenUrls.add(url);
      sources.add(
        new Map<String, Object>{ 'title' => cit.get('title'), 'url' => url }
      );
    }
    return sources;
  }

  private Map<String, Object> getEmptyResponse(String reason) {
    return new Map<String, Object>{ 'available' => false, 'reason' => reason };
  }

  // Test-only injection point — CustomMetadata records cannot be inserted via DML in tests.
  @TestVisible
  private String apiKeyOverride;

  private String getApiKey() {
    if (Test.isRunningTest() && String.isNotBlank(apiKeyOverride)) {
      return apiKeyOverride;
    }
    List<AI_Config__mdt> configs = [
      SELECT ApiKey__c
      FROM AI_Config__mdt
      WHERE DeveloperName = 'Default'
      LIMIT 1
    ];
    if (!configs.isEmpty() && String.isNotBlank(configs[0].ApiKey__c)) {
      return configs[0].ApiKey__c;
    }
    return null;
  }

  @TestVisible
  public static Map<String, Object> getCompanyOverviewMock() {
    return new Map<String, Object>{
      'available' => true,
      'answer' => 'Acme Corp is a mid-market legal technology provider headquartered in ' +
      'Chicago, IL, offering matter-management and e-billing software to law firms.',
      'sources' => new List<Object>{
        new Map<String, Object>{
          'title' => 'Acme Corp - Company Profile',
          'url' => 'https://example.com/acme'
        },
        new Map<String, Object>{
          'title' => 'Acme Corp raises Series B',
          'url' => 'https://news.example.com/acme-series-b'
        }
      }
    };
  }
}
