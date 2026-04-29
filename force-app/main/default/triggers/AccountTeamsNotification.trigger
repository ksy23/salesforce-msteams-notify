/**
 * @description Sample trigger for sending Teams notifications on Account record changes.
 * Copy this trigger and rename it for other objects you want to monitor.
 * 
 * To use with a different object:
 * 1. Copy this file and rename it (e.g., OpportunityTeamsNotification.trigger)
 * 2. Change "Account" to your object name in the trigger declaration
 * 3. Create a Custom Metadata record for Teams_Notification_Config__mdt with:
 *    - Object_API_Name__c = your object's API name
 *    - Webhook_URL__c = your Teams webhook URL
 *    - Configure which events to trigger on
 */
trigger AccountTeamsNotification on Account (after insert, after update, after delete) {
    
    // Handle insert events
    if (Trigger.isAfter && Trigger.isInsert) {
        TeamsNotificationHandler.handleAfterInsert(Trigger.new);
    }
    
    // Handle update events
    if (Trigger.isAfter && Trigger.isUpdate) {
        TeamsNotificationHandler.handleAfterUpdate(Trigger.new, Trigger.oldMap);
    }
    
    // Handle delete events
    if (Trigger.isAfter && Trigger.isDelete) {
        TeamsNotificationHandler.handleAfterDelete(Trigger.old);
    }
}

