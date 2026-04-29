/**
 * @description Queueable class for making async HTTP callouts to Microsoft Teams webhooks.
 * This allows notifications to be sent from trigger contexts where direct callouts are not permitted.
 * Also creates audit log records for each notification attempt.
 */
public with sharing class TeamsNotificationQueueable implements Queueable, Database.AllowsCallouts {
    
    private String webhookUrl;
    private String payload;
    private String sourceRecordId;
    private String sourceObject;
    private String configName;
    private String actionType;
    
    /**
     * @description Constructor for the queueable job with full context
     * @param webhookUrl The MS Teams incoming webhook URL
     * @param payload The JSON payload to send (Adaptive Card format)
     * @param sourceRecordId The ID of the record that triggered the notification
     * @param sourceObject The API name of the source object
     * @param configName The DeveloperName of the Custom Metadata config
     * @param actionType The action type (INSERT, UPDATE, DELETE)
     */
    public TeamsNotificationQueueable(
        String webhookUrl, 
        String payload,
        String sourceRecordId,
        String sourceObject,
        String configName,
        String actionType
    ) {
        this.webhookUrl = webhookUrl;
        this.payload = payload;
        this.sourceRecordId = sourceRecordId;
        this.sourceObject = sourceObject;
        this.configName = configName;
        this.actionType = actionType;
    }
    
    /**
     * @description Legacy constructor for backward compatibility
     * @param webhookUrl The MS Teams incoming webhook URL
     * @param payload The JSON payload to send (Adaptive Card format)
     */
    public TeamsNotificationQueueable(String webhookUrl, String payload) {
        this(webhookUrl, payload, null, null, null, null);
    }
    
    /**
     * @description Executes the HTTP callout to Teams webhook and creates audit log
     * @param context The queueable context
     */
    public void execute(QueueableContext context) {
        NotificationResult result = sendNotificationWithResult(
            this.webhookUrl, 
            this.payload
        );
        
        // Create audit log record
        createAuditLog(result);
    }
    
    /**
     * @description Sends the HTTP POST request and returns detailed result
     * @param webhookUrl The webhook URL
     * @param payload The JSON payload
     * @return NotificationResult with response details
     */
    public static NotificationResult sendNotificationWithResult(String webhookUrl, String payload) {
        NotificationResult result = new NotificationResult();
        result.webhookUrl = webhookUrl;
        result.payload = payload;
        result.sentDateTime = Datetime.now();
        
        if (String.isBlank(webhookUrl) || String.isBlank(payload)) {
            result.isSuccess = false;
            result.errorMessage = 'Missing webhook URL or payload';
            System.debug(LoggingLevel.ERROR, 'TeamsNotificationQueueable: ' + result.errorMessage);
            return result;
        }
        
        Long startTime = System.currentTimeMillis();
        
        try {
            HttpRequest req = new HttpRequest();
            req.setEndpoint(webhookUrl);
            req.setMethod('POST');
            req.setHeader('Content-Type', 'application/json');
            req.setBody(payload);
            req.setTimeout(30000); // 30 second timeout
            
            Http http = new Http();
            HttpResponse res = http.send(req);
            
            result.processingTimeMs = System.currentTimeMillis() - startTime;
            result.statusCode = res.getStatusCode();
            result.responseBody = res.getBody();
            result.isSuccess = (result.statusCode >= 200 && result.statusCode < 300);
            
            if (result.isSuccess) {
                System.debug(LoggingLevel.INFO, 'TeamsNotificationQueueable: Notification sent successfully');
            } else {
                result.errorMessage = 'HTTP ' + result.statusCode + ': ' + result.responseBody;
                System.debug(LoggingLevel.ERROR, 
                    'TeamsNotificationQueueable: Failed to send notification. Status: ' + result.statusCode + 
                    ', Body: ' + result.responseBody
                );
            }
        } catch (Exception e) {
            result.processingTimeMs = System.currentTimeMillis() - startTime;
            result.isSuccess = false;
            result.errorMessage = e.getTypeName() + ': ' + e.getMessage() + '\n' + e.getStackTraceString();
            System.debug(LoggingLevel.ERROR, 
                'TeamsNotificationQueueable: Exception sending notification: ' + e.getMessage() + 
                '\nStack trace: ' + e.getStackTraceString()
            );
        }
        
        return result;
    }
    
    /**
     * @description Legacy method for backward compatibility
     * @param webhookUrl The webhook URL
     * @param payload The JSON payload
     * @return Boolean indicating success or failure
     */
    public static Boolean sendNotification(String webhookUrl, String payload) {
        NotificationResult result = sendNotificationWithResult(webhookUrl, payload);
        return result.isSuccess;
    }
    
    /**
     * @description Creates an audit log record for the notification
     * @param result The notification result
     */
    private void createAuditLog(NotificationResult result) {
        try {
            Teams_Notification_Log__c log = new Teams_Notification_Log__c();
            log.Source_Record_Id__c = this.sourceRecordId;
            log.Source_Object__c = this.sourceObject;
            log.Config_Name__c = this.configName;
            log.Action_Type__c = this.actionType;
            log.Webhook_URL__c = truncateField(result.webhookUrl, 2000);
            log.Request_Payload__c = truncateField(result.payload, 32000);
            log.Response_Status_Code__c = result.statusCode;
            log.Response_Body__c = truncateField(result.responseBody, 5000);
            log.Is_Success__c = result.isSuccess;
            log.Error_Message__c = truncateField(result.errorMessage, 5000);
            log.Sent_DateTime__c = result.sentDateTime;
            log.Processing_Time_Ms__c = result.processingTimeMs;
            
            insert log;
            
            System.debug(LoggingLevel.INFO, 'TeamsNotificationQueueable: Created audit log ' + log.Id);
        } catch (Exception e) {
            // Don't fail the job if audit logging fails - just log the error
            System.debug(LoggingLevel.ERROR, 
                'TeamsNotificationQueueable: Failed to create audit log: ' + e.getMessage()
            );
        }
    }
    
    /**
     * @description Truncates a string to fit within field limits
     * @param value The string to truncate
     * @param maxLength Maximum allowed length
     * @return Truncated string
     */
    private static String truncateField(String value, Integer maxLength) {
        if (String.isBlank(value)) {
            return value;
        }
        if (value.length() <= maxLength) {
            return value;
        }
        return value.substring(0, maxLength - 3) + '...';
    }
    
    /**
     * @description Enqueues a notification with full context for audit logging
     * @param webhookUrl The MS Teams incoming webhook URL
     * @param payload The JSON payload to send
     * @param sourceRecordId The ID of the record that triggered the notification
     * @param sourceObject The API name of the source object
     * @param configName The DeveloperName of the Custom Metadata config
     * @param actionType The action type (INSERT, UPDATE, DELETE)
     * @return The job ID of the enqueued job, or null if enqueuing failed
     */
    public static Id enqueueNotification(
        String webhookUrl, 
        String payload,
        String sourceRecordId,
        String sourceObject,
        String configName,
        String actionType
    ) {
        if (String.isBlank(webhookUrl) || String.isBlank(payload)) {
            System.debug(LoggingLevel.ERROR, 'TeamsNotificationQueueable: Cannot enqueue - missing URL or payload');
            return null;
        }
        
        try {
            // Check if we can enqueue (governor limits)
            if (Limits.getQueueableJobs() < Limits.getLimitQueueableJobs()) {
                TeamsNotificationQueueable job = new TeamsNotificationQueueable(
                    webhookUrl, 
                    payload,
                    sourceRecordId,
                    sourceObject,
                    configName,
                    actionType
                );
                return System.enqueueJob(job);
            } else {
                System.debug(LoggingLevel.WARN, 
                    'TeamsNotificationQueueable: Cannot enqueue - queueable limit reached'
                );
                return null;
            }
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 
                'TeamsNotificationQueueable: Exception enqueuing job: ' + e.getMessage()
            );
            return null;
        }
    }
    
    /**
     * @description Legacy enqueue method for backward compatibility
     * @param webhookUrl The MS Teams incoming webhook URL
     * @param payload The JSON payload to send
     * @return The job ID of the enqueued job, or null if enqueuing failed
     */
    public static Id enqueueNotification(String webhookUrl, String payload) {
        return enqueueNotification(webhookUrl, payload, null, null, null, null);
    }
    
    /**
     * @description Inner class to hold notification result details
     */
    public class NotificationResult {
        public String webhookUrl;
        public String payload;
        public Integer statusCode;
        public String responseBody;
        public Boolean isSuccess;
        public String errorMessage;
        public Datetime sentDateTime;
        public Long processingTimeMs;
        
        public NotificationResult() {
            this.isSuccess = false;
        }
    }
}
