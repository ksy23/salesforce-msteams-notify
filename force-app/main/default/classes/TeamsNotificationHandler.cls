/**
 * @description Handler class for processing trigger events and sending Teams notifications.
 * Reads configuration from Custom Metadata and enqueues notifications for matching records.
 */
public with sharing class TeamsNotificationHandler {
    
    // Cache for configurations to avoid repeated queries within same transaction
    private static Map<String, List<Teams_Notification_Config__mdt>> configCache = 
        new Map<String, List<Teams_Notification_Config__mdt>>();
    
    /**
     * @description Handles after insert trigger events
     * @param newRecords List of newly inserted records
     */
    public static void handleAfterInsert(List<SObject> newRecords) {
        if (newRecords == null || newRecords.isEmpty()) {
            return;
        }
        
        String objectName = newRecords[0].getSObjectType().getDescribe().getName();
        processNotifications(newRecords, null, objectName, TeamsNotificationService.ACTION_INSERT);
    }
    
    /**
     * @description Handles after update trigger events
     * @param newRecords List of updated records (new values)
     * @param oldRecordsMap Map of old record values by ID
     */
    public static void handleAfterUpdate(List<SObject> newRecords, Map<Id, SObject> oldRecordsMap) {
        if (newRecords == null || newRecords.isEmpty()) {
            return;
        }
        
        String objectName = newRecords[0].getSObjectType().getDescribe().getName();
        processNotifications(newRecords, oldRecordsMap, objectName, TeamsNotificationService.ACTION_UPDATE);
    }
    
    /**
     * @description Handles after delete trigger events
     * @param oldRecords List of deleted records
     */
    public static void handleAfterDelete(List<SObject> oldRecords) {
        if (oldRecords == null || oldRecords.isEmpty()) {
            return;
        }
        
        String objectName = oldRecords[0].getSObjectType().getDescribe().getName();
        processNotifications(oldRecords, null, objectName, TeamsNotificationService.ACTION_DELETE);
    }
    
    /**
     * @description Main processing method that builds and enqueues notifications
     */
    private static void processNotifications(
        List<SObject> records,
        Map<Id, SObject> oldRecordsMap,
        String objectName,
        String actionType
    ) {
        // Get active configurations for this object and action
        List<Teams_Notification_Config__mdt> configs = getActiveConfigs(objectName, actionType);
        
        if (configs.isEmpty()) {
            return;
        }
        
        String instanceUrl = URL.getOrgDomainUrl().toExternalForm();
        
        for (Teams_Notification_Config__mdt config : configs) {
            for (SObject record : records) {
                // Get the old record for condition evaluation (updates only)
                SObject oldRecord = null;
                if (oldRecordsMap != null && record.Id != null) {
                    oldRecord = oldRecordsMap.get(record.Id);
                }
                
                // Evaluate conditions - skip this record if conditions not met
                if (!TeamsConditionEvaluator.evaluateConditions(
                    config.Conditions__c,
                    record,
                    oldRecord,
                    actionType
                )) {
                    continue; // Skip this record, conditions not met
                }
                
                // Get record name (try Name field, fall back to Id)
                String recordName = getRecordName(record);
                Id recordId = record.Id;
                
                // For delete, we might not have Id available the same way
                if (actionType == TeamsNotificationService.ACTION_DELETE) {
                    recordId = (Id) record.get('Id');
                }
                
                // Build the payload - use custom if provided, otherwise build default
                String payload;
                if (String.isNotBlank(config.Custom_Card_Payload__c)) {
                    // Use custom payload with merge field substitution (supports {!OLD.FieldName} syntax)
                    payload = TeamsNotificationService.processCustomPayload(
                        config.Custom_Card_Payload__c,
                        record,
                        oldRecord,
                        objectName,
                        recordId,
                        recordName,
                        actionType,
                        instanceUrl
                    );
                } else {
                    // Extract configured field values
                    Map<String, String> fieldValues = TeamsNotificationService.extractFieldValues(
                        record, 
                        config.Fields_To_Display__c
                    );
                    
                    // For updates, also extract field changes to show old → new values
                    Map<String, String> fieldChanges = null;
                    if (actionType == TeamsNotificationService.ACTION_UPDATE && oldRecord != null) {
                        fieldChanges = TeamsNotificationService.extractFieldChanges(
                            record,
                            oldRecord,
                            config.Fields_To_Display__c
                        );
                    }
                    
                    payload = TeamsNotificationService.buildAdaptiveCardPayload(
                        objectName,
                        recordId,
                        recordName,
                        actionType,
                        fieldValues,
                        fieldChanges,
                        instanceUrl
                    );
                }
                
                // Get the webhook URL (prefer long URL if populated)
                String webhookUrl = getWebhookUrl(config);
                
                // Enqueue the notification with audit context
                TeamsNotificationQueueable.enqueueNotification(
                    webhookUrl, 
                    payload,
                    String.valueOf(recordId),
                    objectName,
                    config.DeveloperName,
                    actionType
                );
            }
        }
    }
    
    /**
     * @description Gets active configurations for the specified object and action type
     * @param objectName The API name of the object
     * @param actionType The action type (INSERT, UPDATE, DELETE)
     * @return List of matching active configurations
     */
    private static List<Teams_Notification_Config__mdt> getActiveConfigs(String objectName, String actionType) {
        // Check cache first
        String cacheKey = objectName + '_' + actionType;
        if (configCache.containsKey(cacheKey)) {
            return configCache.get(cacheKey);
        }
        
        // Query all active configs for this object
        List<Teams_Notification_Config__mdt> allConfigs = [
            SELECT 
                DeveloperName,
                Webhook_URL__c,
                Webhook_URL_Long__c,
                Object_API_Name__c,
                Trigger_On_Insert__c,
                Trigger_On_Update__c,
                Trigger_On_Delete__c,
                Fields_To_Display__c,
                Custom_Card_Payload__c,
                Conditions__c,
                Is_Active__c
            FROM Teams_Notification_Config__mdt
            WHERE Object_API_Name__c = :objectName
            AND Is_Active__c = true
        ];
        
        // Filter by action type
        List<Teams_Notification_Config__mdt> matchingConfigs = new List<Teams_Notification_Config__mdt>();
        for (Teams_Notification_Config__mdt config : allConfigs) {
            Boolean matches = false;
            
            if (actionType == TeamsNotificationService.ACTION_INSERT && config.Trigger_On_Insert__c) {
                matches = true;
            } else if (actionType == TeamsNotificationService.ACTION_UPDATE && config.Trigger_On_Update__c) {
                matches = true;
            } else if (actionType == TeamsNotificationService.ACTION_DELETE && config.Trigger_On_Delete__c) {
                matches = true;
            }
            
            if (matches) {
                matchingConfigs.add(config);
            }
        }
        
        // Cache the result
        configCache.put(cacheKey, matchingConfigs);
        
        return matchingConfigs;
    }
    
    /**
     * @description Gets a display name for the record
     * @param record The SObject record
     * @return The record name or ID as fallback
     */
    private static String getRecordName(SObject record) {
        // Try common name fields
        List<String> nameFields = new List<String>{'Name', 'Subject', 'Title', 'CaseNumber'};
        
        for (String fieldName : nameFields) {
            try {
                Object value = record.get(fieldName);
                if (value != null && String.isNotBlank(String.valueOf(value))) {
                    return String.valueOf(value);
                }
            } catch (Exception e) {
                // Field doesn't exist, continue to next
            }
        }
        
        // Fall back to ID
        return String.valueOf(record.get('Id'));
    }
    
    /**
     * @description Gets the effective webhook URL from config (prefers long URL over short)
     * @param config The configuration record
     * @return The webhook URL to use
     */
    private static String getWebhookUrl(Teams_Notification_Config__mdt config) {
        // Prefer the long URL field if populated (for Power Automate and other long URLs)
        if (String.isNotBlank(config.Webhook_URL_Long__c)) {
            return config.Webhook_URL_Long__c;
        }
        // Fall back to the standard URL field
        return config.Webhook_URL__c;
    }
    
    /**
     * @description Clears the configuration cache (useful for testing)
     */
    @TestVisible
    private static void clearCache() {
        configCache.clear();
    }
}

