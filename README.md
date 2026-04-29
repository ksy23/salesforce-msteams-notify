# Salesforce to Microsoft Teams Notification Component

A configurable Salesforce Apex solution that sends rich Adaptive Card notifications to Microsoft Teams via incoming webhooks when records are created, updated, or deleted.

## Features

- **Configurable per object** - Set up notifications for any standard or custom object
- **Rich Adaptive Cards** - Beautiful, formatted notifications with record details
- **Old/New value tracking** - Updates show field changes in "oldValue → newValue" format
- **Color-coded actions** - Green for create, yellow for update, red for delete
- **Direct links** - Click to view the record in Salesforce
- **Async processing** - Uses Queueable to avoid trigger callout limitations
- **Custom Metadata driven** - Deploy configurations across environments
- **Power Automate support** - Works with both Teams Incoming Webhooks and Power Automate flows

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                         Salesforce                              │
│  ┌─────────┐    ┌─────────────┐    ┌────────────────────────┐  │
│  │ Trigger │───▶│   Handler   │───▶│ TeamsNotificationService│  │
│  └─────────┘    └─────────────┘    └────────────────────────┘  │
│                        │                       │                │
│                        ▼                       ▼                │
│              ┌─────────────────┐    ┌─────────────────────┐    │
│              │ Custom Metadata │    │  Queueable (Async)  │    │
│              └─────────────────┘    └─────────────────────┘    │
└─────────────────────────────────────────────────────────────────┘
                                              │
                                              │ HTTP POST
                                              ▼
                                   ┌─────────────────────┐
                                   │   MS Teams Webhook  │
                                   └─────────────────────┘
                                              │
                                              ▼
                                   ┌─────────────────────┐
                                   │   Teams Channel     │
                                   └─────────────────────┘
```

## Installation

### Prerequisites

- Salesforce CLI (sf or sfdx)
- A Salesforce org (sandbox or developer edition recommended for testing)
- Microsoft Teams channel with permission to create incoming webhooks

### Deploy to Salesforce

1. Clone this repository:
   ```bash
   git clone <repository-url>
   cd sf-teams-notify
   ```

2. Authenticate with your Salesforce org:
   ```bash
   sf org login web -a MyOrg
   ```

3. Deploy the source:
   ```bash
   sf project deploy start -o MyOrg
   ```

## Configuration

### Step 1: Create a Teams Incoming Webhook

1. In Microsoft Teams, go to the channel where you want notifications
2. Click the `...` menu next to the channel name
3. Select **Connectors** (or **Workflows** in newer Teams versions)
4. Find **Incoming Webhook** and click **Configure**
5. Give your webhook a name and optionally upload an icon
6. Click **Create** and copy the webhook URL

### Step 2: Configure the Custom Metadata

1. In Salesforce Setup, search for **Custom Metadata Types**
2. Find **Teams Notification Config** and click **Manage Records**
3. Click **New** to create a configuration
4. Fill in the fields:
   - **Label**: A friendly name (e.g., "Opportunity Alerts")
   - **Object API Name**: The object to monitor (e.g., `Opportunity`)
   - **Webhook URL**: For short URLs (≤255 chars) like standard Teams Incoming Webhooks
   - **Webhook URL (Long)**: For long URLs (>255 chars) like Power Automate flows - this takes precedence if populated
   - **Custom Card Payload**: Optional custom Adaptive Card JSON with merge fields (see below)
   - **Conditions**: Optional conditions that must be met to send notification (see below)
   - **Trigger On Insert**: Check to notify on record creation
   - **Trigger On Update**: Check to notify on record updates
   - **Trigger On Delete**: Check to notify on record deletion
   - **Fields To Display**: Comma-separated field API names (e.g., `Name,Amount,StageName`)
   - **Is Active**: Check to enable notifications

> **Note**: Power Automate webhook URLs are typically longer than 255 characters. Use the **Webhook URL (Long)** field for these.

### Conditional Notifications

Use the **Conditions** field to control when notifications are sent. Each condition is on a separate line, and ALL conditions must be met (AND logic).

**Condition Format:** `FieldName OPERATOR Value`

**Supported Operators:**

| Operator | Description | Example |
|----------|-------------|---------|
| `EQUALS` or `=` | Field equals value | `Status EQUALS Closed` |
| `NOT_EQUALS` or `!=` | Field does not equal value | `Type != Test` |
| `CHANGED` | Field value changed | `StageName CHANGED` |
| `CHANGED_TO` | Field changed to specific value | `Status CHANGED_TO Approved` |
| `CHANGED_FROM` | Field changed from specific value | `Status CHANGED_FROM Draft` |
| `CONTAINS` | Field contains substring | `Name CONTAINS Enterprise` |
| `IN` | Field is in comma-separated list | `Type IN Customer,Partner,Prospect` |
| `NOT_IN` | Field is not in list | `Status NOT_IN Draft,Cancelled` |
| `IS_BLANK` | Field is null/empty | `Description IS_BLANK` |
| `IS_NOT_BLANK` | Field has a value | `Email IS_NOT_BLANK` |
| `GREATER_THAN` or `>` | Numeric greater than | `Amount > 10000` |
| `LESS_THAN` or `<` | Numeric less than | `Probability < 50` |
| `>=` | Greater than or equal | `Amount >= 5000` |
| `<=` | Less than or equal | `Discount <= 20` |

**Example Conditions:**

```
# Only notify when Status changes to Closed-Won
StageName CHANGED_TO Closed Won

# And the Amount is over $10,000
Amount > 10000

# And it's an Enterprise account type
Type EQUALS Enterprise
```

> **Note**: Lines starting with `#` or `//` are treated as comments and ignored.

### Custom Adaptive Card Payloads

You can provide your own Adaptive Card JSON template using the **Custom Card Payload** field. Use merge fields to insert dynamic values:

| Merge Field | Description |
|-------------|-------------|
| `{!Id}` | Record ID |
| `{!Name}` | Record name |
| `{!RecordUrl}` | Full URL to the record in Salesforce |
| `{!ActionType}` | INSERT, UPDATE, or DELETE |
| `{!ActionLabel}` | Created, Updated, or Deleted |
| `{!ObjectName}` | API name of the object |
| `{!Timestamp}` | Current date/time |
| `{!Color}` | Good (green), Warning (yellow), or Attention (red) |
| `{!FieldName}` | Any field API name for current/new value (e.g., `{!Industry}`, `{!Phone}`) |
| `{!OLD.FieldName}` | Previous value of a field for updates (e.g., `{!OLD.Status}`, `{!OLD.Industry}`) |

**Example Custom Payload:**

```json
{
  "type": "message",
  "attachments": [{
    "contentType": "application/vnd.microsoft.card.adaptive",
    "content": {
      "$schema": "http://adaptivecards.io/schemas/adaptive-card.json",
      "type": "AdaptiveCard",
      "version": "1.4",
      "body": [
        {
          "type": "TextBlock",
          "size": "Large",
          "weight": "Bolder",
          "text": "{!ObjectName} {!ActionLabel}",
          "color": "{!Color}"
        },
        {
          "type": "TextBlock",
          "text": "{!Name}",
          "size": "Medium"
        },
        {
          "type": "FactSet",
          "facts": [
            {"title": "Industry", "value": "{!Industry}"},
            {"title": "Phone", "value": "{!Phone}"}
          ]
        }
      ],
      "actions": [{
        "type": "Action.OpenUrl",
        "title": "View Record",
        "url": "{!RecordUrl}"
      }]
    }
  }]
}
```

**Example Custom Payload with Old/New Values (for Updates):**

```json
{
  "type": "message",
  "attachments": [{
    "contentType": "application/vnd.microsoft.card.adaptive",
    "content": {
      "$schema": "http://adaptivecards.io/schemas/adaptive-card.json",
      "type": "AdaptiveCard",
      "version": "1.4",
      "body": [
        {
          "type": "TextBlock",
          "size": "Large",
          "weight": "Bolder",
          "text": "{!ObjectName} {!ActionLabel}",
          "color": "{!Color}"
        },
        {
          "type": "TextBlock",
          "text": "{!Name}",
          "size": "Medium"
        },
        {
          "type": "TextBlock",
          "text": "Status changed from {!OLD.Status__c} to {!Status__c}",
          "wrap": true
        },
        {
          "type": "FactSet",
          "facts": [
            {"title": "Previous Industry", "value": "{!OLD.Industry}"},
            {"title": "New Industry", "value": "{!Industry}"},
            {"title": "Previous Stage", "value": "{!OLD.StageName}"},
            {"title": "New Stage", "value": "{!StageName}"}
          ]
        }
      ],
      "actions": [{
        "type": "Action.OpenUrl",
        "title": "View Record",
        "url": "{!RecordUrl}"
      }]
    }
  }]
}
```

### Old/New Value Tracking

For **UPDATE** actions, the notification automatically shows which fields changed and their before/after values:

- **Default Card**: Changed fields display as `oldValue → newValue`
- **Unchanged fields**: Show only the current value
- **Custom Payloads**: Use `{!OLD.FieldName}` to reference previous values

This makes it easy to see at a glance what changed without opening Salesforce.

**How It Works:**

1. When a record is updated, the handler compares old and new field values
2. For each configured field in `Fields_To_Display__c`:
   - If the value changed: displays `previousValue → newValue`
   - If the value is the same: displays just the current value
3. Custom payloads can explicitly reference old values using `{!OLD.FieldName}` syntax

**Example Use Cases:**

- See when Opportunity Stage changes: `Prospecting → Qualification`
- Track Account Industry changes: `Technology → Healthcare`  
- Monitor Lead Status updates: `Open → Working`

### Step 3: Add Trigger to Your Object

Copy the sample trigger and adapt it for your object:

```apex
trigger OpportunityTeamsNotification on Opportunity (after insert, after update, after delete) {
    
    if (Trigger.isAfter && Trigger.isInsert) {
        TeamsNotificationHandler.handleAfterInsert(Trigger.new);
    }
    
    if (Trigger.isAfter && Trigger.isUpdate) {
        TeamsNotificationHandler.handleAfterUpdate(Trigger.new, Trigger.oldMap);
    }
    
    if (Trigger.isAfter && Trigger.isDelete) {
        TeamsNotificationHandler.handleAfterDelete(Trigger.old);
    }
}
```

## Sample Notifications

### Record Created

When an Account is created, Teams will display a card like:

```
┌─────────────────────────────────────────┐
│  🟢 Account Created                     │
│                                         │
│  Acme Corporation                       │
│  2024-01-15 10:30:45 PST               │
│  ─────────────────────────────────────  │
│  Industry:    Technology                │
│  Phone:       (555) 123-4567            │
│  Website:     www.acme.com              │
│                                         │
│  [ View in Salesforce ]                 │
└─────────────────────────────────────────┘
```

### Record Updated (with Old → New Values)

When an Account is updated, Teams will display a card showing what changed:

```
┌─────────────────────────────────────────┐
│  🟡 Account Updated                     │
│                                         │
│  Acme Corporation                       │
│  2024-01-15 14:22:10 PST               │
│  ─────────────────────────────────────  │
│  Industry:    Technology → Healthcare   │
│  Phone:       (555) 123-4567            │
│  Website:     www.acme.com → acme.io    │
│                                         │
│  [ View in Salesforce ]                 │
└─────────────────────────────────────────┘
```

> **Note**: Fields that haven't changed show only their current value. Fields that changed show the format `oldValue → newValue`.

## Components

| File | Description |
|------|-------------|
| `TeamsNotificationService.cls` | Builds Adaptive Card JSON payloads, handles merge fields and old/new value comparison |
| `TeamsNotificationQueueable.cls` | Handles async HTTP callouts and audit logging |
| `TeamsNotificationHandler.cls` | Processes trigger events and coordinates notifications |
| `TeamsConditionEvaluator.cls` | Evaluates conditional logic for when to send notifications |
| `Teams_Notification_Config__mdt` | Custom Metadata Type for configuration |
| `Teams_Notification_Log__c` | Custom Object for audit logging |
| `AccountTeamsNotification.trigger` | Sample trigger template |
| `MS_Teams_Webhook.remoteSite` | Remote Site Setting for callouts |

## Customization

### Adding More Fields

Update the `Fields_To_Display__c` field in your Custom Metadata record with a comma-separated list of field API names.

### Monitoring Additional Objects

1. Create a new trigger for your object (copy from the Account template)
2. Create a new Custom Metadata record with the object's API name
3. Configure the webhook URL and fields

### Custom Colors or Formatting

Modify the `TeamsNotificationService.cls` class to customize:
- `buildAdaptiveCardPayload()` - Main card structure
- `buildCardContent()` - Card body elements
- `getColorForAction()` - Action colors

## Audit Logging

Every notification attempt is automatically logged to the **Teams Notification Log** custom object (`Teams_Notification_Log__c`). This provides complete visibility into notification history.

### Log Fields

| Field | Description |
|-------|-------------|
| **Log Number** | Auto-generated unique identifier (LOG-00001) |
| **Source Record Id** | ID of the record that triggered the notification |
| **Source Object** | API name of the object (Account, Opportunity, etc.) |
| **Config Name** | DeveloperName of the Custom Metadata config used |
| **Action Type** | INSERT, UPDATE, or DELETE |
| **Webhook URL** | The full webhook URL that was called |
| **Request Payload** | The JSON payload sent to Teams |
| **Response Status Code** | HTTP status code (200, 400, 500, etc.) |
| **Response Body** | Response from the webhook service |
| **Is Success** | Checkbox - true if 2xx response |
| **Error Message** | Error details if the call failed |
| **Sent Date/Time** | When the notification was sent |
| **Processing Time (ms)** | How long the callout took |

### Viewing Logs

1. Go to **App Launcher** > **Teams Notification Logs**
2. Create a List View to filter by success/failure, date, object, etc.
3. Create reports for notification analytics

### Sample SOQL Queries

```sql
-- Recent failures
SELECT Name, Source_Object__c, Config_Name__c, Error_Message__c, Sent_DateTime__c
FROM Teams_Notification_Log__c
WHERE Is_Success__c = false
ORDER BY Sent_DateTime__c DESC
LIMIT 100

-- Success rate by config
SELECT Config_Name__c, COUNT(Id), SUM(CASE WHEN Is_Success__c THEN 1 ELSE 0 END)
FROM Teams_Notification_Log__c
GROUP BY Config_Name__c
```

## Troubleshooting

### Notifications not appearing

1. **Check Remote Site Setting**: Ensure `MS_Teams_Webhook` is active in Setup > Remote Site Settings
2. **Verify Webhook URL**: Test the URL directly with a curl command
3. **Check Custom Metadata**: Ensure `Is_Active__c` is checked
4. **Review Debug Logs**: Enable debug logs for the `TeamsNotificationQueueable` class

### Errors in debug logs

- `CALLOUT_NOT_ALLOWED`: Ensure notifications use the Queueable pattern
- `UNABLE_TO_LOCK_ROW`: May occur with high volume; consider batching

## License

MIT License - feel free to use and modify as needed.

