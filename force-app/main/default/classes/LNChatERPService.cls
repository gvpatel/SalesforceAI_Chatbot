public with sharing class LNChatERPService {

    private static final String NAMED_CREDENTIAL = 'callout:External_ERP';

    public Map<String, Object> getRecordData(String externalId) {
        if (String.isBlank(externalId)) {
            return getEmptyResponse('No external ID provided');
        }

        try {
            HttpRequest req = new HttpRequest();
            req.setEndpoint(NAMED_CREDENTIAL + '/records/' + EncodingUtil.urlEncode(externalId, 'UTF-8'));
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

            return getEmptyResponse('ERP returned status ' + res.getStatusCode());

        } catch (CalloutException ce) {
            System.debug(LoggingLevel.WARN, 'LNChatERPService callout failed: ' + ce.getMessage());
            return getEmptyResponse('ERP system unavailable: ' + ce.getMessage());
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'LNChatERPService unexpected error: ' + e.getMessage());
            return getEmptyResponse('ERP error: ' + e.getMessage());
        }
    }

    @TestVisible
    public static Map<String, Object> getRecordDataMock() {
        return new Map<String, Object>{
            'available' => true,
            'externalId' => 'ERP-001',
            'orderHistory' => new List<Object>{
                new Map<String, Object>{
                    'orderId' => 'ORD-2025-001',
                    'date' => '2025-01-15',
                    'amount' => 125000,
                    'status' => 'Fulfilled',
                    'items' => 42
                },
                new Map<String, Object>{
                    'orderId' => 'ORD-2024-089',
                    'date' => '2024-10-03',
                    'amount' => 98500,
                    'status' => 'Fulfilled',
                    'items' => 35
                },
                new Map<String, Object>{
                    'orderId' => 'ORD-2024-055',
                    'date' => '2024-07-22',
                    'amount' => 67200,
                    'status' => 'Fulfilled',
                    'items' => 28
                }
            },
            'inventoryLevels' => new Map<String, Object>{
                'totalSkus' => 156,
                'inStock' => 142,
                'lowStock' => 10,
                'outOfStock' => 4,
                'totalValue' => 2340000
            },
            'financialData' => new Map<String, Object>{
                'ytdRevenue' => 390700,
                'ytdOrders' => 12,
                'averageOrderValue' => 32558,
                'paymentTerms' => 'Net 30',
                'creditLimit' => 500000,
                'outstandingBalance' => 125000,
                'overdueInvoices' => 0
            },
            'accountManager' => 'Sarah Mitchell',
            'contractEndDate' => '2025-12-31',
            'tier' => 'Gold'
        };
    }

    private Map<String, Object> getEmptyResponse(String reason) {
        return new Map<String, Object>{
            'available' => false,
            'reason' => reason,
            'orderHistory' => new List<Object>(),
            'inventoryLevels' => new Map<String, Object>(),
            'financialData' => new Map<String, Object>()
        };
    }
}
