/**
 * @description Service class for building and sending Microsoft Teams notifications
 * via incoming webhooks. Creates rich Adaptive Card payloads with record details.
 */
public with sharing class TeamsNotificationService {
    
    // Action type constants for color coding
    public static final String ACTION_INSERT = 'INSERT';
    public static final String ACTION_UPDATE = 'UPDATE';
    public static final String ACTION_DELETE = 'DELETE';
    
    // Color codes for different actions (Teams Adaptive Card accent colors)
    private static final String COLOR_INSERT = 'Good';      // Green
    private static final String COLOR_UPDATE = 'Warning';   // Yellow
    private static final String COLOR_DELETE = 'Attention'; // Red
    
    /**
     * @description Builds an Adaptive Card JSON payload for Teams webhook
     * @param objectName The API name of the Salesforce object
     * @param recordId The ID of the record
     * @param recordName The name/title of the record
     * @param actionType The action performed (INSERT, UPDATE, DELETE)
     * @param fieldValues Map of field labels to their values
     * @param instanceUrl The Salesforce instance URL for record links
     * @return JSON string formatted as Teams Adaptive Card
     */
    public static String buildAdaptiveCardPayload(
        String objectName,
        Id recordId,
        String recordName,
        String actionType,
        Map<String, String> fieldValues,
        String instanceUrl
    ) {
        // Delegate to overloaded method with null old values
        return buildAdaptiveCardPayload(objectName, recordId, recordName, actionType, fieldValues, null, instanceUrl);
    }
    
    /**
     * @description Builds an Adaptive Card JSON payload for Teams webhook with old/new value comparison
     * @param objectName The API name of the Salesforce object
     * @param recordId The ID of the record
     * @param recordName The name/title of the record
     * @param actionType The action performed (INSERT, UPDATE, DELETE)
     * @param fieldValues Map of field labels to their current values
     * @param fieldChanges Map of field labels to their old→new change strings (for updates)
     * @param instanceUrl The Salesforce instance URL for record links
     * @return JSON string formatted as Teams Adaptive Card
     */
    public static String buildAdaptiveCardPayload(
        String objectName,
        Id recordId,
        String recordName,
        String actionType,
        Map<String, String> fieldValues,
        Map<String, String> fieldChanges,
        String instanceUrl
    ) {
        String color = getColorForAction(actionType);
        String actionLabel = getActionLabel(actionType);
        String timestamp = Datetime.now().format('yyyy-MM-dd HH:mm:ss z');
        String recordUrl = instanceUrl + '/' + recordId;
        
        // Build the facts array for field values
        List<Map<String, String>> facts = new List<Map<String, String>>();
        
        // For updates with field changes, show old → new format
        if (actionType == ACTION_UPDATE && fieldChanges != null && !fieldChanges.isEmpty()) {
            for (String fieldLabel : fieldChanges.keySet()) {
                String changeValue = fieldChanges.get(fieldLabel);
                facts.add(new Map<String, String>{
                    'title' => fieldLabel,
                    'value' => changeValue
                });
            }
        } else if (fieldValues != null && !fieldValues.isEmpty()) {
            // For inserts/deletes or when no changes provided, show current values
            for (String fieldLabel : fieldValues.keySet()) {
                String fieldValue = fieldValues.get(fieldLabel);
                facts.add(new Map<String, String>{
                    'title' => fieldLabel,
                    'value' => String.isBlank(fieldValue) ? '(empty)' : fieldValue
                });
            }
        }
        
        // Build the Adaptive Card structure
        Map<String, Object> card = new Map<String, Object>{
            'type' => 'message',
            'attachments' => new List<Object>{
                new Map<String, Object>{
                    'contentType' => 'application/vnd.microsoft.card.adaptive',
                    'contentUrl' => null,
                    'content' => buildCardContent(
                        objectName,
                        recordName,
                        actionLabel,
                        color,
                        timestamp,
                        recordUrl,
                        facts
                    )
                }
            }
        };
        
        return JSON.serialize(card);
    }
    
    /**
     * @description Builds the inner content of the Adaptive Card
     */
    private static Map<String, Object> buildCardContent(
        String objectName,
        String recordName,
        String actionLabel,
        String color,
        String timestamp,
        String recordUrl,
        List<Map<String, String>> facts
    ) {
        List<Object> bodyItems = new List<Object>();
        
        // Header with action and object name
        bodyItems.add(new Map<String, Object>{
            'type' => 'TextBlock',
            'size' => 'Large',
            'weight' => 'Bolder',
            'text' => objectName + ' ' + actionLabel,
            'color' => color,
            'wrap' => true
        });
        
        // Record name
        bodyItems.add(new Map<String, Object>{
            'type' => 'TextBlock',
            'size' => 'Medium',
            'weight' => 'Bolder',
            'text' => recordName,
            'wrap' => true
        });
        
        // Timestamp
        bodyItems.add(new Map<String, Object>{
            'type' => 'TextBlock',
            'size' => 'Small',
            'text' => timestamp,
            'isSubtle' => true,
            'wrap' => true
        });
        
        // Separator
        bodyItems.add(new Map<String, Object>{
            'type' => 'TextBlock',
            'text' => ' ',
            'separator' => true
        });
        
        // Field values as FactSet
        if (!facts.isEmpty()) {
            bodyItems.add(new Map<String, Object>{
                'type' => 'FactSet',
                'facts' => facts
            });
        }
        
        // Actions - View in Salesforce button
        List<Object> actions = new List<Object>{
            new Map<String, Object>{
                'type' => 'Action.OpenUrl',
                'title' => 'View in Salesforce',
                'url' => recordUrl
            }
        };
        
        return new Map<String, Object>{
            '$schema' => 'http://adaptivecards.io/schemas/adaptive-card.json',
            'type' => 'AdaptiveCard',
            'version' => '1.4',
            'body' => bodyItems,
            'actions' => actions
        };
    }
    
    /**
     * @description Gets the accent color for the action type
     */
    private static String getColorForAction(String actionType) {
        if (actionType == ACTION_INSERT) {
            return COLOR_INSERT;
        } else if (actionType == ACTION_UPDATE) {
            return COLOR_UPDATE;
        } else if (actionType == ACTION_DELETE) {
            return COLOR_DELETE;
        }
        return 'Default';
    }
    
    /**
     * @description Gets a human-readable label for the action type
     */
    private static String getActionLabel(String actionType) {
        if (actionType == ACTION_INSERT) {
            return 'Created';
        } else if (actionType == ACTION_UPDATE) {
            return 'Updated';
        } else if (actionType == ACTION_DELETE) {
            return 'Deleted';
        }
        return 'Changed';
    }
    
    /**
     * @description Processes a custom Adaptive Card payload template with merge field substitution
     * @param customPayload The custom JSON template with merge fields
     * @param record The SObject record to get field values from
     * @param objectName The API name of the Salesforce object
     * @param recordId The ID of the record
     * @param recordName The name/title of the record
     * @param actionType The action performed (INSERT, UPDATE, DELETE)
     * @param instanceUrl The Salesforce instance URL for record links
     * @return Processed JSON string with merge fields replaced
     */
    public static String processCustomPayload(
        String customPayload,
        SObject record,
        String objectName,
        Id recordId,
        String recordName,
        String actionType,
        String instanceUrl
    ) {
        // Delegate to overloaded method with null old record
        return processCustomPayload(customPayload, record, null, objectName, recordId, recordName, actionType, instanceUrl);
    }
    
    /**
     * @description Processes a custom Adaptive Card payload template with merge field substitution
     * Supports {!OLD.FieldName} syntax for old values in update scenarios
     * @param customPayload The custom JSON template with merge fields
     * @param record The SObject record (new values)
     * @param oldRecord The old SObject record (previous values, for updates)
     * @param objectName The API name of the Salesforce object
     * @param recordId The ID of the record
     * @param recordName The name/title of the record
     * @param actionType The action performed (INSERT, UPDATE, DELETE)
     * @param instanceUrl The Salesforce instance URL for record links
     * @return Processed JSON string with merge fields replaced
     */
    public static String processCustomPayload(
        String customPayload,
        SObject record,
        SObject oldRecord,
        String objectName,
        Id recordId,
        String recordName,
        String actionType,
        String instanceUrl
    ) {
        if (String.isBlank(customPayload)) {
            return null;
        }
        
        String timestamp = Datetime.now().format('yyyy-MM-dd HH:mm:ss z');
        String recordUrl = instanceUrl + '/' + recordId;
        String actionLabel = getActionLabel(actionType);
        String color = getColorForAction(actionType);
        
        // Replace standard merge fields
        String processed = customPayload;
        processed = processed.replace('{!Id}', recordId != null ? String.valueOf(recordId) : '');
        processed = processed.replace('{!Name}', recordName != null ? recordName : '');
        processed = processed.replace('{!RecordUrl}', recordUrl);
        processed = processed.replace('{!ActionType}', actionType);
        processed = processed.replace('{!ActionLabel}', actionLabel);
        processed = processed.replace('{!ObjectName}', objectName);
        processed = processed.replace('{!Timestamp}', timestamp);
        processed = processed.replace('{!Color}', color);
        
        // Replace field-specific merge fields like {!FieldName} and {!OLD.FieldName}
        if (record != null) {
            // Get all field names from the object
            String objName = record.getSObjectType().getDescribe().getName();
            Map<String, Schema.SObjectField> fieldMap = 
                Schema.getGlobalDescribe().get(objName).getDescribe().fields.getMap();
            
            Map<String, String> replacements = new Map<String, String>();
            
            // First, handle {!OLD.FieldName} merge fields (for old/previous values)
            if (oldRecord != null) {
                Pattern oldPattern = Pattern.compile('\\{!OLD\\.([A-Za-z0-9_]+)\\}');
                Matcher oldMatcher = oldPattern.matcher(processed);
                
                while (oldMatcher.find()) {
                    String fieldName = oldMatcher.group(1);
                    try {
                        Object fieldValue = oldRecord.get(fieldName);
                        String stringValue = fieldValue != null ? String.valueOf(fieldValue) : '';
                        stringValue = escapeJsonString(stringValue);
                        replacements.put('{!OLD.' + fieldName + '}', stringValue);
                    } catch (Exception e) {
                        replacements.put('{!OLD.' + fieldName + '}', '');
                    }
                }
            } else {
                // No old record - replace all {!OLD.X} with empty
                Pattern oldPattern = Pattern.compile('\\{!OLD\\.([A-Za-z0-9_]+)\\}');
                Matcher oldMatcher = oldPattern.matcher(processed);
                while (oldMatcher.find()) {
                    String fieldName = oldMatcher.group(1);
                    replacements.put('{!OLD.' + fieldName + '}', '');
                }
            }
            
            // Then handle {!FieldName} merge fields (for current/new values)
            Pattern p = Pattern.compile('\\{!([A-Za-z0-9_]+)\\}');
            Matcher m = p.matcher(processed);
            
            while (m.find()) {
                String fieldName = m.group(1);
                // Skip standard merge fields we already handled
                if (fieldName == 'Id' || fieldName == 'Name' || fieldName == 'RecordUrl' || 
                    fieldName == 'ActionType' || fieldName == 'ActionLabel' || 
                    fieldName == 'ObjectName' || fieldName == 'Timestamp' || fieldName == 'Color') {
                    continue;
                }
                
                try {
                    Object fieldValue = record.get(fieldName);
                    String stringValue = fieldValue != null ? String.valueOf(fieldValue) : '';
                    stringValue = escapeJsonString(stringValue);
                    replacements.put('{!' + fieldName + '}', stringValue);
                } catch (Exception e) {
                    // Field doesn't exist or can't be accessed - replace with empty string
                    replacements.put('{!' + fieldName + '}', '');
                }
            }
            
            // Apply all replacements
            for (String key : replacements.keySet()) {
                processed = processed.replace(key, replacements.get(key));
            }
        }
        
        return processed;
    }
    
    /**
     * @description Escapes special characters for JSON strings
     * @param input The string to escape
     * @return Escaped string safe for JSON
     */
    private static String escapeJsonString(String input) {
        if (String.isBlank(input)) {
            return input;
        }
        return input.replace('\\', '\\\\')
                   .replace('"', '\\"')
                   .replace('\n', '\\n')
                   .replace('\r', '\\r')
                   .replace('\t', '\\t');
    }
    
    /**
     * @description Extracts field values from a record based on field API names
     * @param record The SObject record
     * @param fieldApiNames Comma-separated list of field API names
     * @return Map of field labels to their string values
     */
    public static Map<String, String> extractFieldValues(SObject record, String fieldApiNames) {
        Map<String, String> fieldValues = new Map<String, String>();
        
        if (String.isBlank(fieldApiNames) || record == null) {
            return fieldValues;
        }
        
        // Get field describe info for labels
        String objectName = record.getSObjectType().getDescribe().getName();
        Map<String, Schema.SObjectField> fieldMap = 
            Schema.getGlobalDescribe().get(objectName).getDescribe().fields.getMap();
        
        List<String> fields = fieldApiNames.split(',');
        for (String fieldName : fields) {
            fieldName = fieldName.trim();
            if (String.isBlank(fieldName)) {
                continue;
            }
            
            try {
                // Get field label
                String fieldLabel = fieldName;
                if (fieldMap.containsKey(fieldName.toLowerCase())) {
                    fieldLabel = fieldMap.get(fieldName.toLowerCase()).getDescribe().getLabel();
                }
                
                // Get field value
                Object fieldValue = record.get(fieldName);
                String stringValue = fieldValue != null ? String.valueOf(fieldValue) : '';
                
                fieldValues.put(fieldLabel, stringValue);
            } catch (Exception e) {
                // Skip fields that can't be accessed
                System.debug(LoggingLevel.WARN, 'Could not extract field ' + fieldName + ': ' + e.getMessage());
            }
        }
        
        return fieldValues;
    }
    
    /**
     * @description Extracts field changes comparing old and new record values
     * Returns a map of field labels to "oldValue → newValue" format strings
     * Only includes fields that actually changed
     * @param newRecord The new SObject record (current values)
     * @param oldRecord The old SObject record (previous values)
     * @param fieldApiNames Comma-separated list of field API names to check
     * @return Map of field labels to their change strings (e.g., "Active → Inactive")
     */
    public static Map<String, String> extractFieldChanges(SObject newRecord, SObject oldRecord, String fieldApiNames) {
        Map<String, String> fieldChanges = new Map<String, String>();
        
        if (String.isBlank(fieldApiNames) || newRecord == null) {
            return fieldChanges;
        }
        
        // Get field describe info for labels
        String objectName = newRecord.getSObjectType().getDescribe().getName();
        Map<String, Schema.SObjectField> fieldMap = 
            Schema.getGlobalDescribe().get(objectName).getDescribe().fields.getMap();
        
        List<String> fields = fieldApiNames.split(',');
        for (String fieldName : fields) {
            fieldName = fieldName.trim();
            if (String.isBlank(fieldName)) {
                continue;
            }
            
            try {
                // Get field label
                String fieldLabel = fieldName;
                if (fieldMap.containsKey(fieldName.toLowerCase())) {
                    fieldLabel = fieldMap.get(fieldName.toLowerCase()).getDescribe().getLabel();
                }
                
                // Get old and new values
                Object newValue = newRecord.get(fieldName);
                Object oldValue = oldRecord != null ? oldRecord.get(fieldName) : null;
                
                String newStringValue = newValue != null ? String.valueOf(newValue) : '';
                String oldStringValue = oldValue != null ? String.valueOf(oldValue) : '';
                
                // Check if value changed
                if (newStringValue != oldStringValue) {
                    // Format: "oldValue → newValue"
                    String oldDisplay = String.isBlank(oldStringValue) ? '(empty)' : oldStringValue;
                    String newDisplay = String.isBlank(newStringValue) ? '(empty)' : newStringValue;
                    fieldChanges.put(fieldLabel, oldDisplay + ' → ' + newDisplay);
                } else {
                    // Value didn't change - still show current value
                    fieldChanges.put(fieldLabel, String.isBlank(newStringValue) ? '(empty)' : newStringValue);
                }
            } catch (Exception e) {
                // Skip fields that can't be accessed
                System.debug(LoggingLevel.WARN, 'Could not extract field change for ' + fieldName + ': ' + e.getMessage());
            }
        }
        
        return fieldChanges;
    }
    
    /**
     * @description Extracts only the fields that actually changed between old and new records
     * @param newRecord The new SObject record (current values)
     * @param oldRecord The old SObject record (previous values)
     * @param fieldApiNames Comma-separated list of field API names to check
     * @return Map of field labels to their change strings, only for changed fields
     */
    public static Map<String, String> extractChangedFieldsOnly(SObject newRecord, SObject oldRecord, String fieldApiNames) {
        Map<String, String> changedFields = new Map<String, String>();
        
        if (String.isBlank(fieldApiNames) || newRecord == null || oldRecord == null) {
            return changedFields;
        }
        
        // Get field describe info for labels
        String objectName = newRecord.getSObjectType().getDescribe().getName();
        Map<String, Schema.SObjectField> fieldMap = 
            Schema.getGlobalDescribe().get(objectName).getDescribe().fields.getMap();
        
        List<String> fields = fieldApiNames.split(',');
        for (String fieldName : fields) {
            fieldName = fieldName.trim();
            if (String.isBlank(fieldName)) {
                continue;
            }
            
            try {
                // Get old and new values
                Object newValue = newRecord.get(fieldName);
                Object oldValue = oldRecord.get(fieldName);
                
                String newStringValue = newValue != null ? String.valueOf(newValue) : '';
                String oldStringValue = oldValue != null ? String.valueOf(oldValue) : '';
                
                // Only include if value actually changed
                if (newStringValue != oldStringValue) {
                    // Get field label
                    String fieldLabel = fieldName;
                    if (fieldMap.containsKey(fieldName.toLowerCase())) {
                        fieldLabel = fieldMap.get(fieldName.toLowerCase()).getDescribe().getLabel();
                    }
                    
                    // Format: "oldValue → newValue"
                    String oldDisplay = String.isBlank(oldStringValue) ? '(empty)' : oldStringValue;
                    String newDisplay = String.isBlank(newStringValue) ? '(empty)' : newStringValue;
                    changedFields.put(fieldLabel, oldDisplay + ' → ' + newDisplay);
                }
            } catch (Exception e) {
                System.debug(LoggingLevel.WARN, 'Could not check field change for ' + fieldName + ': ' + e.getMessage());
            }
        }
        
        return changedFields;
    }
}

