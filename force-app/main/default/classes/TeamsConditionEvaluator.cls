/**
 * @description Evaluates conditions defined in Custom Metadata to determine if notifications should be sent.
 * Supports various operators for field-based rules.
 * 
 * Condition Format: FieldName OPERATOR Value
 * Multiple conditions on separate lines are AND'd together.
 * 
 * Supported Operators:
 * - EQUALS, = : Field equals value
 * - NOT_EQUALS, != : Field does not equal value
 * - CHANGED : Field value changed (requires old record)
 * - CHANGED_TO : Field changed to specific value
 * - CHANGED_FROM : Field changed from specific value
 * - CONTAINS : Field contains value (text fields)
 * - IN : Field value is in comma-separated list
 * - NOT_IN : Field value is not in comma-separated list
 * - IS_BLANK : Field is null or empty
 * - IS_NOT_BLANK : Field has a value
 * - GREATER_THAN, > : Field is greater than value (numeric)
 * - LESS_THAN, < : Field is less than value (numeric)
 * - GREATER_OR_EQUAL, >= : Field is greater than or equal to value
 * - LESS_OR_EQUAL, <= : Field is less than or equal to value
 */
public with sharing class TeamsConditionEvaluator {
    
    // Operator constants
    private static final Set<String> EQUALS_OPS = new Set<String>{'EQUALS', '='};
    private static final Set<String> NOT_EQUALS_OPS = new Set<String>{'NOT_EQUALS', '!='};
    private static final Set<String> GREATER_OPS = new Set<String>{'GREATER_THAN', '>'};
    private static final Set<String> LESS_OPS = new Set<String>{'LESS_THAN', '<'};
    private static final Set<String> GREATER_EQ_OPS = new Set<String>{'GREATER_OR_EQUAL', '>='};
    private static final Set<String> LESS_EQ_OPS = new Set<String>{'LESS_OR_EQUAL', '<='};
    
    /**
     * @description Evaluates all conditions for a record
     * @param conditions The conditions string from Custom Metadata
     * @param newRecord The current/new record
     * @param oldRecord The old record (for update scenarios, null for insert/delete)
     * @param actionType The action type (INSERT, UPDATE, DELETE)
     * @return True if all conditions are met (or no conditions specified), false otherwise
     */
    public static Boolean evaluateConditions(
        String conditions,
        SObject newRecord,
        SObject oldRecord,
        String actionType
    ) {
        // No conditions = always send
        if (String.isBlank(conditions)) {
            return true;
        }
        
        // Parse and evaluate each condition line
        List<String> conditionLines = conditions.split('\n');
        for (String line : conditionLines) {
            line = line.trim();
            
            // Skip empty lines and comments
            if (String.isBlank(line) || line.startsWith('//') || line.startsWith('#')) {
                continue;
            }
            
            // Evaluate the condition - all must be true (AND logic)
            if (!evaluateSingleCondition(line, newRecord, oldRecord, actionType)) {
                return false;
            }
        }
        
        return true;
    }
    
    /**
     * @description Evaluates a single condition line
     * @param conditionLine A single condition in format: FieldName OPERATOR Value
     * @param newRecord The current/new record
     * @param oldRecord The old record (for update scenarios)
     * @param actionType The action type
     * @return True if condition is met, false otherwise
     */
    private static Boolean evaluateSingleCondition(
        String conditionLine,
        SObject newRecord,
        SObject oldRecord,
        String actionType
    ) {
        // Parse the condition
        ConditionParts parts = parseCondition(conditionLine);
        if (parts == null) {
            System.debug(LoggingLevel.WARN, 'TeamsConditionEvaluator: Could not parse condition: ' + conditionLine);
            return true; // Skip malformed conditions
        }
        
        String fieldName = parts.fieldName;
        String operator = parts.operator.toUpperCase();
        String conditionValue = parts.value;
        
        // Get field values
        Object newValue = getFieldValue(newRecord, fieldName);
        Object oldValue = oldRecord != null ? getFieldValue(oldRecord, fieldName) : null;
        
        // Evaluate based on operator
        if (EQUALS_OPS.contains(operator)) {
            return evaluateEquals(newValue, conditionValue);
        } else if (NOT_EQUALS_OPS.contains(operator)) {
            return !evaluateEquals(newValue, conditionValue);
        } else if (operator == 'CHANGED') {
            return evaluateChanged(newValue, oldValue, actionType);
        } else if (operator == 'CHANGED_TO') {
            return evaluateChangedTo(newValue, oldValue, conditionValue, actionType);
        } else if (operator == 'CHANGED_FROM') {
            return evaluateChangedFrom(newValue, oldValue, conditionValue, actionType);
        } else if (operator == 'CONTAINS') {
            return evaluateContains(newValue, conditionValue);
        } else if (operator == 'IN') {
            return evaluateIn(newValue, conditionValue);
        } else if (operator == 'NOT_IN') {
            return !evaluateIn(newValue, conditionValue);
        } else if (operator == 'IS_BLANK') {
            return isBlank(newValue);
        } else if (operator == 'IS_NOT_BLANK') {
            return !isBlank(newValue);
        } else if (GREATER_OPS.contains(operator)) {
            return evaluateNumericComparison(newValue, conditionValue, 'GT');
        } else if (LESS_OPS.contains(operator)) {
            return evaluateNumericComparison(newValue, conditionValue, 'LT');
        } else if (GREATER_EQ_OPS.contains(operator)) {
            return evaluateNumericComparison(newValue, conditionValue, 'GTE');
        } else if (LESS_EQ_OPS.contains(operator)) {
            return evaluateNumericComparison(newValue, conditionValue, 'LTE');
        }
        
        System.debug(LoggingLevel.WARN, 'TeamsConditionEvaluator: Unknown operator: ' + operator);
        return true; // Unknown operator - skip
    }
    
    /**
     * @description Parses a condition line into its components
     */
    private static ConditionParts parseCondition(String conditionLine) {
        // Handle operators that don't require a value first
        if (conditionLine.toUpperCase().endsWith(' IS_BLANK')) {
            String fieldName = conditionLine.substring(0, conditionLine.length() - 9).trim();
            return new ConditionParts(fieldName, 'IS_BLANK', '');
        }
        if (conditionLine.toUpperCase().endsWith(' IS_NOT_BLANK')) {
            String fieldName = conditionLine.substring(0, conditionLine.length() - 13).trim();
            return new ConditionParts(fieldName, 'IS_NOT_BLANK', '');
        }
        if (conditionLine.toUpperCase().endsWith(' CHANGED')) {
            String fieldName = conditionLine.substring(0, conditionLine.length() - 8).trim();
            return new ConditionParts(fieldName, 'CHANGED', '');
        }
        
        // Try to match patterns with operators
        // Order matters - check longer operators first
        List<String> operators = new List<String>{
            'CHANGED_TO', 'CHANGED_FROM', 'NOT_EQUALS', 'GREATER_OR_EQUAL', 'LESS_OR_EQUAL',
            'GREATER_THAN', 'LESS_THAN', 'NOT_IN', 'CONTAINS', 'EQUALS', 'IN',
            '!=', '>=', '<=', '>', '<', '='
        };
        
        for (String op : operators) {
            String searchOp = ' ' + op + ' ';
            Integer idx = conditionLine.toUpperCase().indexOf(searchOp.toUpperCase());
            if (idx > 0) {
                String fieldName = conditionLine.substring(0, idx).trim();
                String value = conditionLine.substring(idx + searchOp.length()).trim();
                return new ConditionParts(fieldName, op, value);
            }
        }
        
        return null;
    }
    
    /**
     * @description Gets a field value from a record safely
     */
    private static Object getFieldValue(SObject record, String fieldName) {
        if (record == null || String.isBlank(fieldName)) {
            return null;
        }
        try {
            return record.get(fieldName);
        } catch (Exception e) {
            System.debug(LoggingLevel.WARN, 'TeamsConditionEvaluator: Could not get field ' + fieldName + ': ' + e.getMessage());
            return null;
        }
    }
    
    /**
     * @description Evaluates if field value equals condition value
     */
    private static Boolean evaluateEquals(Object fieldValue, String conditionValue) {
        String fieldStr = fieldValue != null ? String.valueOf(fieldValue) : '';
        return fieldStr.equalsIgnoreCase(conditionValue);
    }
    
    /**
     * @description Evaluates if field value changed
     */
    private static Boolean evaluateChanged(Object newValue, Object oldValue, String actionType) {
        // For insert, consider it "changed" if has a value
        if (actionType == TeamsNotificationService.ACTION_INSERT) {
            return !isBlank(newValue);
        }
        // For delete, consider it "changed" 
        if (actionType == TeamsNotificationService.ACTION_DELETE) {
            return true;
        }
        // For update, compare old and new
        String newStr = newValue != null ? String.valueOf(newValue) : '';
        String oldStr = oldValue != null ? String.valueOf(oldValue) : '';
        return !newStr.equals(oldStr);
    }
    
    /**
     * @description Evaluates if field changed to a specific value
     */
    private static Boolean evaluateChangedTo(Object newValue, Object oldValue, String targetValue, String actionType) {
        // Must have changed AND new value must equal target
        if (!evaluateChanged(newValue, oldValue, actionType)) {
            return false;
        }
        return evaluateEquals(newValue, targetValue);
    }
    
    /**
     * @description Evaluates if field changed from a specific value
     */
    private static Boolean evaluateChangedFrom(Object newValue, Object oldValue, String sourceValue, String actionType) {
        // Must have changed AND old value must equal source
        if (!evaluateChanged(newValue, oldValue, actionType)) {
            return false;
        }
        String oldStr = oldValue != null ? String.valueOf(oldValue) : '';
        return oldStr.equalsIgnoreCase(sourceValue);
    }
    
    /**
     * @description Evaluates if field contains a substring
     */
    private static Boolean evaluateContains(Object fieldValue, String searchValue) {
        if (fieldValue == null || String.isBlank(searchValue)) {
            return false;
        }
        String fieldStr = String.valueOf(fieldValue);
        return fieldStr.containsIgnoreCase(searchValue);
    }
    
    /**
     * @description Evaluates if field value is in a comma-separated list
     */
    private static Boolean evaluateIn(Object fieldValue, String valueList) {
        if (fieldValue == null || String.isBlank(valueList)) {
            return false;
        }
        String fieldStr = String.valueOf(fieldValue).toLowerCase();
        List<String> values = valueList.split(',');
        for (String v : values) {
            if (fieldStr.equals(v.trim().toLowerCase())) {
                return true;
            }
        }
        return false;
    }
    
    /**
     * @description Evaluates numeric comparisons
     */
    private static Boolean evaluateNumericComparison(Object fieldValue, String conditionValue, String compType) {
        if (fieldValue == null) {
            return false;
        }
        
        try {
            Decimal fieldNum = Decimal.valueOf(String.valueOf(fieldValue));
            Decimal conditionNum = Decimal.valueOf(conditionValue.trim());
            
            if (compType == 'GT') {
                return fieldNum > conditionNum;
            } else if (compType == 'LT') {
                return fieldNum < conditionNum;
            } else if (compType == 'GTE') {
                return fieldNum >= conditionNum;
            } else if (compType == 'LTE') {
                return fieldNum <= conditionNum;
            }
        } catch (Exception e) {
            System.debug(LoggingLevel.WARN, 'TeamsConditionEvaluator: Numeric comparison failed: ' + e.getMessage());
        }
        return false;
    }
    
    /**
     * @description Checks if a value is blank/null
     */
    private static Boolean isBlank(Object value) {
        if (value == null) {
            return true;
        }
        if (value instanceof String) {
            return String.isBlank((String)value);
        }
        return false;
    }
    
    /**
     * @description Inner class to hold parsed condition parts
     */
    private class ConditionParts {
        public String fieldName;
        public String operator;
        public String value;
        
        public ConditionParts(String fieldName, String operator, String value) {
            this.fieldName = fieldName;
            this.operator = operator;
            this.value = value;
        }
    }
}

