public with sharing class LNChatBIService {

    private static final String NAMED_CREDENTIAL = 'callout:External_BI';

    public Map<String, Object> getMetrics(String externalId) {
        if (String.isBlank(externalId)) {
            return getEmptyResponse('No external ID provided');
        }

        try {
            HttpRequest req = new HttpRequest();
            req.setEndpoint(NAMED_CREDENTIAL + '/metrics?entityId=' + EncodingUtil.urlEncode(externalId, 'UTF-8'));
            req.setMethod('GET');
            req.setHeader('Accept', 'application/json');
            req.setHeader('Content-Type', 'application/json');
            req.setTimeout(10000);

            Http http = new Http();
            HttpResponse res = http.send(req);

            if (res.getStatusCode() == 200) {
                Object parsed = JSON.deserializeUntyped(res.getBody());
                if (parsed instanceof Map<String, Object>) {
                    return (Map<String, Object>) parsed;
                }
            }

            return getEmptyResponse('BI system returned status ' + res.getStatusCode());

        } catch (CalloutException ce) {
            System.debug(LoggingLevel.WARN, 'LNChatBIService callout failed: ' + ce.getMessage());
            return getEmptyResponse('BI system unavailable: ' + ce.getMessage());
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'LNChatBIService unexpected error: ' + e.getMessage());
            return getEmptyResponse('BI error: ' + e.getMessage());
        }
    }

    @TestVisible
    public static Map<String, Object> getMetricsMock() {
        return new Map<String, Object>{
            'available' => true,
            'kpis' => new Map<String, Object>{
                'customerHealthScore' => 82,
                'npsScore' => 68,
                'churnRisk' => 'Low',
                'engagementScore' => 74,
                'supportTicketVolume' => 3,
                'productAdoptionRate' => 0.87
            },
            'trendData' => new Map<String, Object>{
                'revenueByQuarter' => new List<Object>{
                    new Map<String, Object>{ 'quarter' => 'Q1 2024', 'revenue' => 67200 },
                    new Map<String, Object>{ 'quarter' => 'Q2 2024', 'revenue' => 78900 },
                    new Map<String, Object>{ 'quarter' => 'Q3 2024', 'revenue' => 98500 },
                    new Map<String, Object>{ 'quarter' => 'Q4 2024', 'revenue' => 115300 },
                    new Map<String, Object>{ 'quarter' => 'Q1 2025', 'revenue' => 125000 }
                },
                'supportTicketsByMonth' => new List<Object>{
                    new Map<String, Object>{ 'month' => 'Nov 2024', 'count' => 8 },
                    new Map<String, Object>{ 'month' => 'Dec 2024', 'count' => 5 },
                    new Map<String, Object>{ 'month' => 'Jan 2025', 'count' => 3 }
                }
            },
            'benchmarkComparisons' => new Map<String, Object>{
                'revenueGrowthVsIndustry' => '+12% above avg',
                'retentionVsIndustry' => '+8% above avg',
                'npsVsIndustry' => '+5 above avg',
                'industrySegment' => 'Enterprise Software'
            },
            'predictions' => new Map<String, Object>{
                'renewalProbability' => 0.91,
                'upsellProbability' => 0.64,
                'predictedRevenueNextQuarter' => 138000,
                'churnProbabilityNextYear' => 0.09
            }
        };
    }

    private Map<String, Object> getEmptyResponse(String reason) {
        return new Map<String, Object>{
            'available' => false,
            'reason' => reason,
            'kpis' => new Map<String, Object>(),
            'trendData' => new Map<String, Object>(),
            'benchmarkComparisons' => new Map<String, Object>(),
            'predictions' => new Map<String, Object>()
        };
    }
}
