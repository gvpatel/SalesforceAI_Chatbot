public with sharing class LNChatSearchService {

    private static final Set<String> ALLOWED_OBJECTS = new Set<String>{
        'Account', 'Contact', 'Opportunity', 'Case', 'Lead', 'Task', 'Event', 'Quote'
    };

    private static final Set<String> ALLOWED_OPERATORS = new Set<String>{
        '=', '!=', '<', '>', '<=', '>=', 'IN', 'NOT IN', 'LIKE'
    };

    // SOQL date literals that are safe to pass through without escaping
    private static final Set<String> DATE_LITERALS = new Set<String>{
        'TODAY', 'YESTERDAY', 'TOMORROW',
        'THIS_WEEK', 'LAST_WEEK', 'NEXT_WEEK',
        'THIS_MONTH', 'LAST_MONTH', 'NEXT_MONTH',
        'THIS_QUARTER', 'LAST_QUARTER', 'NEXT_QUARTER',
        'THIS_YEAR', 'LAST_YEAR', 'NEXT_YEAR',
        'LAST_90_DAYS', 'NEXT_90_DAYS'
    };

    public static Map<String, Object> searchRecords(
        String objectApiName,
        String filtersJson,
        String columnsJson,
        String orderByField,
        Boolean orderDesc,
        Integer limitRows
    ) {
        if (String.isBlank(objectApiName) || !ALLOWED_OBJECTS.contains(objectApiName)) {
            throw new AuraHandledException('Unsupported object: ' + objectApiName);
        }

        Map<String, Schema.SObjectField> fieldMap =
            Schema.getGlobalDescribe().get(objectApiName).getDescribe().fields.getMap();

        // Parse and validate columns
        List<String> requestedColumns = new List<String>();
        if (String.isNotBlank(columnsJson)) {
            try {
                requestedColumns = (List<String>) JSON.deserialize(columnsJson, List<String>.class);
            } catch (Exception e) {
                requestedColumns = new List<String>();
            }
        }

        List<String> safeColumns = new List<String>{ 'Id' };
        for (String col : requestedColumns) {
            String baseField = col.contains('.') ? col.substringBefore('.') : col;
            if (fieldMap.containsKey(baseField.toLowerCase()) && col != 'Id') {
                safeColumns.add(col);
            }
        }
        if (safeColumns.size() == 1) {
            safeColumns.add('Name');
        }

        // Parse and validate filters
        List<Map<String, Object>> filters = new List<Map<String, Object>>();
        if (String.isNotBlank(filtersJson)) {
            try {
                filters = (List<Map<String, Object>>) JSON.deserializeUntyped(filtersJson);
            } catch (Exception e) {
                filters = new List<Map<String, Object>>();
            }
        }

        List<String> whereClauses = new List<String>();
        for (Map<String, Object> filter : filters) {
            String field    = String.valueOf(filter.get('field'));
            String operator = String.valueOf(filter.get('operator')).toUpperCase();
            Object value    = filter.get('value');

            if (String.isBlank(field) || !fieldMap.containsKey(field.toLowerCase())) continue;
            if (!ALLOWED_OPERATORS.contains(operator)) continue;
            if (value == null) continue;

            String clause = buildClause(field, operator, value, fieldMap);
            if (String.isNotBlank(clause)) {
                whereClauses.add(clause);
            }
        }

        // Validate ORDER BY field
        String safeOrderBy = '';
        if (String.isNotBlank(orderByField) && fieldMap.containsKey(orderByField.toLowerCase())) {
            safeOrderBy = ' ORDER BY ' + orderByField + (orderDesc == true ? ' DESC' : ' ASC') + ' NULLS LAST';
        }

        Integer safeLimit = (limitRows != null && limitRows > 0) ? Math.min(limitRows, 50) : 20;

        String whereStr = whereClauses.isEmpty() ? '' : ' WHERE ' + String.join(whereClauses, ' AND ');
        String soql = 'SELECT ' + String.join(safeColumns, ', ')
            + ' FROM ' + objectApiName
            + whereStr
            + safeOrderBy
            + ' LIMIT ' + safeLimit;

        List<SObject> records = Database.query(soql);

        List<Map<String, Object>> rows = new List<Map<String, Object>>();
        for (SObject rec : records) {
            rows.add(rec.getPopulatedFieldsAsMap());
        }

        return new Map<String, Object>{
            'rows'          => rows,
            'count'         => records.size(),
            'columns'       => safeColumns,
            'objectApiName' => objectApiName
        };
    }

    private static String buildClause(
        String field,
        String operator,
        Object value,
        Map<String, Schema.SObjectField> fieldMap
    ) {
        Schema.DisplayType fieldType = fieldMap.get(field.toLowerCase()).getDescribe().getType();

        // IN / NOT IN — value must be a List
        if (operator == 'IN' || operator == 'NOT IN') {
            List<Object> vals;
            if (value instanceof List<Object>) {
                vals = (List<Object>) value;
            } else {
                // Single value wrapped as list
                vals = new List<Object>{ value };
            }
            List<String> escaped = new List<String>();
            for (Object v : vals) {
                escaped.add('\'' + String.escapeSingleQuotes(String.valueOf(v)) + '\'');
            }
            return field + ' ' + operator + ' (' + String.join(escaped, ', ') + ')';
        }

        String strVal = String.valueOf(value);

        // CURRENT_USER substitution
        if (strVal == 'CURRENT_USER') {
            return field + ' = \'' + UserInfo.getUserId() + '\'';
        }

        // SOQL date literals — pass through as-is
        String upperVal = strVal.toUpperCase();
        if (DATE_LITERALS.contains(upperVal) || upperVal.startsWith('LAST_N_DAYS:') || upperVal.startsWith('NEXT_N_DAYS:')) {
            return field + ' ' + operator + ' ' + upperVal;
        }

        // Boolean fields
        if (fieldType == Schema.DisplayType.BOOLEAN) {
            return field + ' ' + operator + ' ' + (strVal.toLowerCase() == 'true' ? 'true' : 'false');
        }

        // Numeric fields — no quoting needed
        if (fieldType == Schema.DisplayType.DOUBLE
            || fieldType == Schema.DisplayType.CURRENCY
            || fieldType == Schema.DisplayType.PERCENT
            || fieldType == Schema.DisplayType.INTEGER) {
            try {
                Double.valueOf(strVal);
                return field + ' ' + operator + ' ' + strVal;
            } catch (Exception e) {
                return null;
            }
        }

        // Date / DateTime — validate format then pass unquoted
        if (fieldType == Schema.DisplayType.DATE) {
            try {
                Date.valueOf(strVal);
                return field + ' ' + operator + ' ' + strVal;
            } catch (Exception e) {
                return null;
            }
        }
        if (fieldType == Schema.DisplayType.DATETIME) {
            try {
                DateTime.valueOf(strVal);
                return field + ' ' + operator + ' ' + strVal.replace(' ', 'T');
            } catch (Exception e) {
                return null;
            }
        }

        // Default: string — escape and quote
        return field + ' ' + operator + ' \'' + String.escapeSingleQuotes(strVal) + '\'';
    }
}
