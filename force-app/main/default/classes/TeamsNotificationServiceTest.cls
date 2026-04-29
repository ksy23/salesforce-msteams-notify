/**
 * @description Test class for Teams notification components.
 * Uses mock HTTP callouts to test the full notification flow.
 */
@isTest
private class TeamsNotificationServiceTest {
    
    /**
     * @description Mock HTTP callout class for successful responses
     */
    private class MockHttpResponseSuccess implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            res.setBody('1');  // Teams returns '1' on success
            res.setStatusCode(200);
            return res;
        }
    }
    
    /**
     * @description Mock HTTP callout class for failed responses
     */
    private class MockHttpResponseFailure implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            res.setBody('{"error": "Bad Request"}');
            res.setStatusCode(400);
            return res;
        }
    }
    
    /**
     * @description Test building an Adaptive Card payload for INSERT action
     */
    @isTest
    static void testBuildAdaptiveCardPayload_Insert() {
        Map<String, String> fieldValues = new Map<String, String>{
            'Industry' => 'Technology',
            'Phone' => '555-1234'
        };
        
        String payload = TeamsNotificationService.buildAdaptiveCardPayload(
            'Account',
            '001000000000001AAA',
            'Test Account',
            TeamsNotificationService.ACTION_INSERT,
            fieldValues,
            'https://test.salesforce.com'
        );
        
        System.assertNotEquals(null, payload, 'Payload should not be null');
        System.assert(payload.contains('Account'), 'Payload should contain object name');
        System.assert(payload.contains('Test Account'), 'Payload should contain record name');
        System.assert(payload.contains('Created'), 'Payload should contain action label');
        System.assert(payload.contains('Good'), 'Payload should contain green color for insert');
        System.assert(payload.contains('Technology'), 'Payload should contain field value');
    }
    
    /**
     * @description Test building an Adaptive Card payload for UPDATE action
     */
    @isTest
    static void testBuildAdaptiveCardPayload_Update() {
        Map<String, String> fieldValues = new Map<String, String>{
            'Name' => 'Updated Account'
        };
        
        String payload = TeamsNotificationService.buildAdaptiveCardPayload(
            'Account',
            '001000000000001AAA',
            'Updated Account',
            TeamsNotificationService.ACTION_UPDATE,
            fieldValues,
            'https://test.salesforce.com'
        );
        
        System.assertNotEquals(null, payload, 'Payload should not be null');
        System.assert(payload.contains('Updated'), 'Payload should contain action label');
        System.assert(payload.contains('Warning'), 'Payload should contain yellow color for update');
    }
    
    /**
     * @description Test building an Adaptive Card payload for DELETE action
     */
    @isTest
    static void testBuildAdaptiveCardPayload_Delete() {
        String payload = TeamsNotificationService.buildAdaptiveCardPayload(
            'Account',
            '001000000000001AAA',
            'Deleted Account',
            TeamsNotificationService.ACTION_DELETE,
            new Map<String, String>(),
            'https://test.salesforce.com'
        );
        
        System.assertNotEquals(null, payload, 'Payload should not be null');
        System.assert(payload.contains('Deleted'), 'Payload should contain action label');
        System.assert(payload.contains('Attention'), 'Payload should contain red color for delete');
    }
    
    /**
     * @description Test building payload with empty field values
     */
    @isTest
    static void testBuildAdaptiveCardPayload_EmptyFields() {
        String payload = TeamsNotificationService.buildAdaptiveCardPayload(
            'Account',
            '001000000000001AAA',
            'Test Account',
            TeamsNotificationService.ACTION_INSERT,
            null,
            'https://test.salesforce.com'
        );
        
        System.assertNotEquals(null, payload, 'Payload should not be null even with empty fields');
    }
    
    /**
     * @description Test extracting field values from a record
     */
    @isTest
    static void testExtractFieldValues() {
        Account testAccount = new Account(
            Name = 'Test Extract Account',
            Industry = 'Technology',
            Phone = '555-9999'
        );
        insert testAccount;
        
        // Re-query to ensure all fields are available
        testAccount = [SELECT Id, Name, Industry, Phone FROM Account WHERE Id = :testAccount.Id];
        
        Map<String, String> values = TeamsNotificationService.extractFieldValues(
            testAccount, 
            'Name, Industry, Phone'
        );
        
        System.assertEquals(3, values.size(), 'Should extract 3 field values');
        System.assert(values.values().contains('Test Extract Account'), 'Should contain Name value');
        System.assert(values.values().contains('Technology'), 'Should contain Industry value');
    }
    
    /**
     * @description Test extracting field values with null inputs
     */
    @isTest
    static void testExtractFieldValues_NullInputs() {
        Map<String, String> values = TeamsNotificationService.extractFieldValues(null, 'Name');
        System.assertEquals(0, values.size(), 'Should return empty map for null record');
        
        Account testAccount = new Account(Name = 'Test');
        insert testAccount;
        
        values = TeamsNotificationService.extractFieldValues(testAccount, null);
        System.assertEquals(0, values.size(), 'Should return empty map for null field names');
        
        values = TeamsNotificationService.extractFieldValues(testAccount, '');
        System.assertEquals(0, values.size(), 'Should return empty map for empty field names');
    }
    
    /**
     * @description Test the queueable with successful HTTP callout
     */
    @isTest
    static void testQueueable_Success() {
        Test.setMock(HttpCalloutMock.class, new MockHttpResponseSuccess());
        
        String webhookUrl = 'https://outlook.office.com/webhook/test';
        String payload = '{"type":"message","text":"Test"}';
        
        Test.startTest();
        Boolean result = TeamsNotificationQueueable.sendNotification(webhookUrl, payload);
        Test.stopTest();
        
        System.assertEquals(true, result, 'Should return true for successful callout');
    }
    
    /**
     * @description Test the queueable with failed HTTP callout
     */
    @isTest
    static void testQueueable_Failure() {
        Test.setMock(HttpCalloutMock.class, new MockHttpResponseFailure());
        
        String webhookUrl = 'https://outlook.office.com/webhook/test';
        String payload = '{"type":"message","text":"Test"}';
        
        Test.startTest();
        Boolean result = TeamsNotificationQueueable.sendNotification(webhookUrl, payload);
        Test.stopTest();
        
        System.assertEquals(false, result, 'Should return false for failed callout');
    }
    
    /**
     * @description Test the queueable with null inputs
     */
    @isTest
    static void testQueueable_NullInputs() {
        Boolean result = TeamsNotificationQueueable.sendNotification(null, 'test');
        System.assertEquals(false, result, 'Should return false for null URL');
        
        result = TeamsNotificationQueueable.sendNotification('https://test.com', null);
        System.assertEquals(false, result, 'Should return false for null payload');
    }
    
    /**
     * @description Test enqueueing a notification
     */
    @isTest
    static void testEnqueueNotification() {
        Test.setMock(HttpCalloutMock.class, new MockHttpResponseSuccess());
        
        String webhookUrl = 'https://outlook.office.com/webhook/test';
        String payload = '{"type":"message","text":"Test"}';
        
        Test.startTest();
        Id jobId = TeamsNotificationQueueable.enqueueNotification(webhookUrl, payload);
        Test.stopTest();
        
        System.assertNotEquals(null, jobId, 'Should return a valid job ID');
    }
    
    /**
     * @description Test enqueueing with null inputs
     */
    @isTest
    static void testEnqueueNotification_NullInputs() {
        Id jobId = TeamsNotificationQueueable.enqueueNotification(null, 'test');
        System.assertEquals(null, jobId, 'Should return null for null URL');
        
        jobId = TeamsNotificationQueueable.enqueueNotification('https://test.com', null);
        System.assertEquals(null, jobId, 'Should return null for null payload');
    }
    
    /**
     * @description Test the trigger handler with Account insert
     * Note: This test requires a Custom Metadata record to be set up for Account
     */
    @isTest
    static void testHandlerAfterInsert() {
        Test.setMock(HttpCalloutMock.class, new MockHttpResponseSuccess());
        
        // Clear any cached configs
        TeamsNotificationHandler.clearCache();
        
        Test.startTest();
        Account testAccount = new Account(
            Name = 'Test Trigger Account',
            Industry = 'Technology'
        );
        insert testAccount;
        Test.stopTest();
        
        // Verify account was created (notification may or may not fire depending on config)
        Account insertedAccount = [SELECT Id, Name FROM Account WHERE Id = :testAccount.Id];
        System.assertEquals('Test Trigger Account', insertedAccount.Name, 'Account should be created');
    }
    
    /**
     * @description Test the trigger handler with Account update
     */
    @isTest
    static void testHandlerAfterUpdate() {
        Test.setMock(HttpCalloutMock.class, new MockHttpResponseSuccess());
        
        Account testAccount = new Account(Name = 'Test Update Account');
        insert testAccount;
        
        // Clear any cached configs
        TeamsNotificationHandler.clearCache();
        
        Test.startTest();
        testAccount.Name = 'Updated Account Name';
        update testAccount;
        Test.stopTest();
        
        Account updatedAccount = [SELECT Id, Name FROM Account WHERE Id = :testAccount.Id];
        System.assertEquals('Updated Account Name', updatedAccount.Name, 'Account should be updated');
    }
    
    /**
     * @description Test the trigger handler with Account delete
     */
    @isTest
    static void testHandlerAfterDelete() {
        Test.setMock(HttpCalloutMock.class, new MockHttpResponseSuccess());
        
        Account testAccount = new Account(Name = 'Test Delete Account');
        insert testAccount;
        Id accountId = testAccount.Id;
        
        // Clear any cached configs
        TeamsNotificationHandler.clearCache();
        
        Test.startTest();
        delete testAccount;
        Test.stopTest();
        
        List<Account> deletedAccounts = [SELECT Id FROM Account WHERE Id = :accountId];
        System.assertEquals(0, deletedAccounts.size(), 'Account should be deleted');
    }
    
    /**
     * @description Test handler with null inputs
     */
    @isTest
    static void testHandler_NullInputs() {
        // These should not throw exceptions
        TeamsNotificationHandler.handleAfterInsert(null);
        TeamsNotificationHandler.handleAfterInsert(new List<SObject>());
        TeamsNotificationHandler.handleAfterUpdate(null, null);
        TeamsNotificationHandler.handleAfterUpdate(new List<SObject>(), new Map<Id, SObject>());
        TeamsNotificationHandler.handleAfterDelete(null);
        TeamsNotificationHandler.handleAfterDelete(new List<SObject>());
        
        // If we reach here without exceptions, test passes
        System.assert(true, 'Handler methods should handle null inputs gracefully');
    }
    
    /**
     * @description Test extracting field changes between old and new records
     */
    @isTest
    static void testExtractFieldChanges() {
        // Create and insert old record
        Account oldAccount = new Account(
            Name = 'Old Account Name',
            Industry = 'Technology',
            Phone = '555-1111'
        );
        insert oldAccount;
        
        // Query to get all fields
        oldAccount = [SELECT Id, Name, Industry, Phone FROM Account WHERE Id = :oldAccount.Id];
        
        // Update the account
        Account newAccount = oldAccount.clone(true, true, true, true);
        newAccount.Name = 'New Account Name';
        newAccount.Industry = 'Healthcare';
        // Phone stays the same
        
        Test.startTest();
        Map<String, String> changes = TeamsNotificationService.extractFieldChanges(
            newAccount,
            oldAccount,
            'Name, Industry, Phone'
        );
        Test.stopTest();
        
        System.assertEquals(3, changes.size(), 'Should extract 3 field changes');
        
        // Check that changed fields show old → new format
        String nameChange = changes.get('Account Name');
        System.assert(nameChange.contains('→'), 'Name change should show arrow for changed value');
        System.assert(nameChange.contains('Old Account Name'), 'Name change should contain old value');
        System.assert(nameChange.contains('New Account Name'), 'Name change should contain new value');
        
        String industryChange = changes.get('Industry');
        System.assert(industryChange.contains('Technology'), 'Industry change should contain old value');
        System.assert(industryChange.contains('Healthcare'), 'Industry change should contain new value');
        
        // Phone didn't change - should show current value without arrow
        String phoneValue = changes.get('Phone');
        System.assertEquals('555-1111', phoneValue, 'Unchanged phone should show current value only');
    }
    
    /**
     * @description Test extracting only fields that actually changed
     */
    @isTest
    static void testExtractChangedFieldsOnly() {
        // Create and insert old record
        Account oldAccount = new Account(
            Name = 'Old Account Name',
            Industry = 'Technology',
            Phone = '555-1111'
        );
        insert oldAccount;
        
        oldAccount = [SELECT Id, Name, Industry, Phone FROM Account WHERE Id = :oldAccount.Id];
        
        // Clone and change only some fields
        Account newAccount = oldAccount.clone(true, true, true, true);
        newAccount.Name = 'New Account Name';
        // Industry and Phone stay the same
        
        Test.startTest();
        Map<String, String> changedOnly = TeamsNotificationService.extractChangedFieldsOnly(
            newAccount,
            oldAccount,
            'Name, Industry, Phone'
        );
        Test.stopTest();
        
        System.assertEquals(1, changedOnly.size(), 'Should only extract 1 changed field');
        System.assert(changedOnly.containsKey('Account Name'), 'Should contain Name which changed');
        System.assert(!changedOnly.containsKey('Industry'), 'Should not contain Industry which did not change');
        System.assert(!changedOnly.containsKey('Phone'), 'Should not contain Phone which did not change');
    }
    
    /**
     * @description Test building Adaptive Card payload with field changes
     */
    @isTest
    static void testBuildAdaptiveCardPayload_WithChanges() {
        Map<String, String> fieldValues = new Map<String, String>{
            'Industry' => 'Healthcare'
        };
        
        Map<String, String> fieldChanges = new Map<String, String>{
            'Industry' => 'Technology → Healthcare',
            'Phone' => '555-1111 → 555-2222'
        };
        
        String payload = TeamsNotificationService.buildAdaptiveCardPayload(
            'Account',
            '001000000000001AAA',
            'Test Account',
            TeamsNotificationService.ACTION_UPDATE,
            fieldValues,
            fieldChanges,
            'https://test.salesforce.com'
        );
        
        System.assertNotEquals(null, payload, 'Payload should not be null');
        System.assert(payload.contains('Technology → Healthcare'), 'Payload should contain change format');
        System.assert(payload.contains('555-1111 → 555-2222'), 'Payload should contain phone change');
    }
    
    /**
     * @description Test custom payload with OLD merge field syntax
     */
    @isTest
    static void testProcessCustomPayload_WithOldValues() {
        // Create and insert account
        Account oldAccount = new Account(
            Name = 'Old Name',
            Industry = 'Technology'
        );
        insert oldAccount;
        
        oldAccount = [SELECT Id, Name, Industry FROM Account WHERE Id = :oldAccount.Id];
        
        // Clone and change
        Account newAccount = oldAccount.clone(true, true, true, true);
        newAccount.Name = 'New Name';
        newAccount.Industry = 'Healthcare';
        
        String customPayload = '{"text": "Name changed from {!OLD.Name} to {!Name}. Industry: {!OLD.Industry} → {!Industry}"}';
        
        Test.startTest();
        String processed = TeamsNotificationService.processCustomPayload(
            customPayload,
            newAccount,
            oldAccount,
            'Account',
            newAccount.Id,
            newAccount.Name,
            TeamsNotificationService.ACTION_UPDATE,
            'https://test.salesforce.com'
        );
        Test.stopTest();
        
        System.assert(processed.contains('Old Name'), 'Should contain old name value');
        System.assert(processed.contains('New Name'), 'Should contain new name value');
        System.assert(processed.contains('Technology'), 'Should contain old industry');
        System.assert(processed.contains('Healthcare'), 'Should contain new industry');
    }
    
    /**
     * @description Test custom payload OLD merge fields when no old record provided
     */
    @isTest
    static void testProcessCustomPayload_NoOldRecord() {
        Account newAccount = new Account(
            Name = 'Test Account',
            Industry = 'Technology'
        );
        insert newAccount;
        
        newAccount = [SELECT Id, Name, Industry FROM Account WHERE Id = :newAccount.Id];
        
        String customPayload = '{"text": "Old: {!OLD.Name}, New: {!Name}"}';
        
        Test.startTest();
        String processed = TeamsNotificationService.processCustomPayload(
            customPayload,
            newAccount,
            null,  // No old record
            'Account',
            newAccount.Id,
            newAccount.Name,
            TeamsNotificationService.ACTION_INSERT,
            'https://test.salesforce.com'
        );
        Test.stopTest();
        
        // OLD.Name should be replaced with empty string
        System.assert(processed.contains('Old: ,'), 'OLD merge field should be empty when no old record');
        System.assert(processed.contains('Test Account'), 'Should contain new name value');
    }
    
    /**
     * @description Test extractFieldChanges with null inputs
     */
    @isTest
    static void testExtractFieldChanges_NullInputs() {
        Map<String, String> result = TeamsNotificationService.extractFieldChanges(null, null, 'Name');
        System.assertEquals(0, result.size(), 'Should return empty map for null new record');
        
        Account testAccount = new Account(Name = 'Test');
        insert testAccount;
        
        result = TeamsNotificationService.extractFieldChanges(testAccount, null, null);
        System.assertEquals(0, result.size(), 'Should return empty map for null field names');
    }
}

