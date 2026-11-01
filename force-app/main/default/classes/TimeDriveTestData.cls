/**
 * The sources the timeline once shipped with (orders, cases, opportunities,
 * reviews and Data 360 engagement), kept for
 * the tests: they stand in for custom metadata records, so the tests don't
 * depend on what an org has configured. Orders and reviews are Tasks here
 * (the timeline needs only standard objects): "Order …" tasks are orders,
 * Completed ones delivered and Deferred ones canceled; "Review …" tasks are
 * reviews.
 */
@IsTest
public class TimeDriveTestData {
  /**
   * Inserts a test's records, unless the org's own automation won't take
   * them (a flow, process or validation rule an org adds, such as one that
   * needs a setting tests can't see). Then nothing is kept and the answer is
   * false: a test that needs those records has nothing of ours to test there.
   *
   * @param records the records to insert
   * @return true when they were inserted
   */
  public static Boolean tryInsert(List<SObject> records) {
    Savepoint before = Database.setSavepoint();
    try {
      insert records;
      return true;
    } catch (DmlException e) {
      Database.rollback(before);
      System.debug(LoggingLevel.WARN, 'Time Drive test: this org won\'t take the records. ' + e.getMessage());
      return false;
    }
  }

  /**
   * Inserts one record, unless the org's own automation won't take it.
   *
   * @param record the record to insert
   * @return true when it was inserted
   */
  public static Boolean tryInsert(SObject record) {
    return tryInsert(new List<SObject>{ record });
  }

  /** Puts the sources and their detail fields in place of the org's. */
  public static void useShipped() {
    TimeDriveConfig.testSources = sources();
    TimeDriveConfig.testDetailFields = detailFields();
  }

  /**
   * A stand-in source by developer name.
   *
   * @param developerName the source's developer name
   * @return the source, or null when there is none
   */
  public static Time_Drive_Source__mdt source(String developerName) {
    for (Time_Drive_Source__mdt s : sources()) {
      if (s.DeveloperName == developerName) {
        return s;
      }
    }
    return null;
  }

  /**
   * The stand-in sources.
   *
   * @return the sources
   */
  public static List<Time_Drive_Source__mdt> sources() {
    return new List<Time_Drive_Source__mdt>{
      new Time_Drive_Source__mdt(
        DeveloperName = 'Case_Closed',
        Label = 'Case closed',
        Active__c = true,
        Sequence__c = 31,
        Parent_Object__c = 'Contact',
        Object_Name__c = 'Case',
        Parent_Field__c = 'ContactId',
        Date_Field__c = 'ClosedDate',
        Filter__c = 'IsClosed = true',
        Title__c = 'Case closed',
        Subtitle__c = '{Subject} · {CaseNumber}',
        Event_Type__c = 'case',
        Event_Label__c = 'Case updates',
        Category__c = 'Service',
        Icon__c = 'utility:case',
        Icon_Colour__c = '#1F7A8C',
        Max_Records__c = 1000,
        Kind__c = 'Salesforce'
      ),
      new Time_Drive_Source__mdt(
        DeveloperName = 'Case_Opened',
        Label = 'Case opened',
        Active__c = true,
        Sequence__c = 30,
        Parent_Object__c = 'Contact',
        Object_Name__c = 'Case',
        Parent_Field__c = 'ContactId',
        Date_Field__c = 'CreatedDate',
        Title__c = 'Case opened',
        Subtitle__c = '{Subject} · {CaseNumber}',
        Event_Type__c = 'case',
        Event_Label__c = 'Case updates',
        Category__c = 'Service',
        Icon__c = 'utility:case',
        Icon_Colour__c = '#1F7A8C',
        Max_Records__c = 1000,
        Kind__c = 'Salesforce'
      ),
      new Time_Drive_Source__mdt(
        DeveloperName = 'Data_360_App',
        Label = 'App',
        Active__c = true,
        Sequence__c = 95,
        Parent_Object__c = 'Contact',
        Kind__c = 'Data 360',
        Object_Name__c = 'ssot__DeviceApplicationEngagement__dlm',
        Individual_Field__c = 'ssot__IndividualId__c',
        Data_Space__c = 'default',
        Date_Field__c = 'ssot__EngagementDateTm__c',
        Id_Field__c = 'ssot__Id__c',
        Title__c = 'App {Action}',
        Subtitle__c = '{ssot__Name__c}',
        Event_Type__c = 'app',
        Event_Label__c = 'App events',
        Category__c = 'Digital',
        Icon__c = 'utility:phone_portrait',
        Max_Records__c = 500
      ),
      new Time_Drive_Source__mdt(
        DeveloperName = 'Data_360_Cart',
        Label = 'Cart',
        Active__c = true,
        Sequence__c = 96,
        Parent_Object__c = 'Contact',
        Kind__c = 'Data 360',
        Object_Name__c = 'ssot__ShoppingCartEngagement__dlm',
        Individual_Field__c = 'ssot__IndividualId__c',
        Data_Space__c = 'default',
        Date_Field__c = 'ssot__EngagementDateTm__c',
        Id_Field__c = 'ssot__Id__c',
        Title__c = 'Cart {Action}',
        Subtitle__c = '{ssot__Name__c}',
        Event_Type__c = 'cart',
        Event_Label__c = 'Cart events',
        Category__c = 'Commerce',
        Icon__c = 'utility:cart',
        Max_Records__c = 500
      ),
      new Time_Drive_Source__mdt(
        DeveloperName = 'Data_360_Email',
        Label = 'Email',
        Active__c = true,
        Sequence__c = 91,
        Parent_Object__c = 'Contact',
        Kind__c = 'Data 360',
        Object_Name__c = 'ssot__EmailEngagement__dlm',
        Individual_Field__c = 'ssot__IndividualId__c',
        Data_Space__c = 'default',
        Date_Field__c = 'ssot__EngagementDateTm__c',
        Id_Field__c = 'ssot__Id__c',
        Title__c = 'Email {Action}',
        Subtitle__c = '{ssot__EmailName__c}',
        Event_Type__c = 'email',
        Event_Label__c = 'Email events',
        Category__c = 'Marketing',
        Icon__c = 'utility:email',
        Max_Records__c = 500
      ),
      new Time_Drive_Source__mdt(
        DeveloperName = 'Data_360_Message',
        Label = 'Message',
        Active__c = true,
        Sequence__c = 92,
        Parent_Object__c = 'Contact',
        Kind__c = 'Data 360',
        Object_Name__c = 'ssot__MessageEngagement__dlm',
        Individual_Field__c = 'ssot__IndividualId__c',
        Data_Space__c = 'default',
        Date_Field__c = 'ssot__EngagementDateTm__c',
        Id_Field__c = 'ssot__Id__c',
        Title__c = 'Message {Action}',
        Subtitle__c = '{ssot__Name__c}',
        Event_Type__c = 'message',
        Event_Label__c = 'Push and SMS messages',
        Category__c = 'Marketing',
        Icon__c = 'utility:notification',
        Max_Records__c = 500
      ),
      new Time_Drive_Source__mdt(
        DeveloperName = 'Data_360_Web_Search',
        Label = 'Web search',
        Active__c = true,
        Sequence__c = 94,
        Parent_Object__c = 'Contact',
        Kind__c = 'Data 360',
        Object_Name__c = 'ssot__WebSearchEngagement__dlm',
        Individual_Field__c = 'ssot__IndividualId__c',
        Data_Space__c = 'default',
        Date_Field__c = 'ssot__EngagementDateTm__c',
        Id_Field__c = 'ssot__Id__c',
        Title__c = 'Web search {Action}',
        Subtitle__c = '{ssot__Name__c}',
        Event_Type__c = 'search',
        Event_Label__c = 'Web searches',
        Category__c = 'Digital',
        Icon__c = 'utility:search',
        Max_Records__c = 500
      ),
      new Time_Drive_Source__mdt(
        DeveloperName = 'Data_360_Website',
        Label = 'Website',
        Active__c = true,
        Sequence__c = 93,
        Parent_Object__c = 'Contact',
        Kind__c = 'Data 360',
        Object_Name__c = 'ssot__WebsiteEngagement__dlm',
        Individual_Field__c = 'ssot__IndividualId__c',
        Data_Space__c = 'default',
        Date_Field__c = 'ssot__EngagementDateTm__c',
        Id_Field__c = 'ssot__Id__c',
        Title__c = 'Website {Action}',
        Subtitle__c = '{ssot__Name__c}',
        Event_Type__c = 'web',
        Event_Label__c = 'Page views',
        Category__c = 'Digital',
        Icon__c = 'utility:world',
        Max_Records__c = 500
      ),
      new Time_Drive_Source__mdt(
        DeveloperName = 'Opportunity_Lost',
        Label = 'Opportunity lost',
        Active__c = true,
        Sequence__c = 42,
        Parent_Object__c = 'Contact',
        Object_Name__c = 'Opportunity',
        Date_Field__c = 'CloseDate',
        Filter__c = 'IsClosed = true AND IsWon = false',
        Title__c = 'Opportunity lost',
        Subtitle__c = '{Name} · {Amount}',
        Event_Type__c = 'opportunity_lost',
        Event_Label__c = 'Opportunities lost',
        Category__c = 'Sales',
        Icon__c = 'utility:close',
        Icon_Colour__c = '#C62F2F',
        Max_Records__c = 1000,
        Junction_Object__c = 'OpportunityContactRole',
        Junction_Parent_Field__c = 'ContactId',
        Junction_Record_Field__c = 'OpportunityId',
        Kind__c = 'Salesforce'
      ),
      new Time_Drive_Source__mdt(
        DeveloperName = 'Opportunity_Opened',
        Label = 'Opportunity opened',
        Active__c = true,
        Sequence__c = 40,
        Parent_Object__c = 'Contact',
        Object_Name__c = 'Opportunity',
        Date_Field__c = 'CreatedDate',
        Title__c = 'Opportunity opened',
        Subtitle__c = '{Name} · {Amount}',
        Event_Type__c = 'opportunity',
        Event_Label__c = 'Opportunity updates',
        Category__c = 'Sales',
        Icon__c = 'utility:opportunity',
        Icon_Colour__c = '#2F6FB0',
        Max_Records__c = 1000,
        Junction_Object__c = 'OpportunityContactRole',
        Junction_Parent_Field__c = 'ContactId',
        Junction_Record_Field__c = 'OpportunityId',
        Kind__c = 'Salesforce'
      ),
      new Time_Drive_Source__mdt(
        DeveloperName = 'Opportunity_Won',
        Label = 'Opportunity won',
        Active__c = true,
        Sequence__c = 41,
        Parent_Object__c = 'Contact',
        Object_Name__c = 'Opportunity',
        Date_Field__c = 'CloseDate',
        Filter__c = 'IsWon = true',
        Title__c = 'Opportunity won',
        Subtitle__c = '{Name} · {Amount}',
        Event_Type__c = 'opportunity_won',
        Event_Label__c = 'Opportunities won',
        Category__c = 'Sales',
        Icon__c = 'utility:check',
        Icon_Colour__c = '#2F6FB0',
        Max_Records__c = 1000,
        Junction_Object__c = 'OpportunityContactRole',
        Junction_Parent_Field__c = 'ContactId',
        Junction_Record_Field__c = 'OpportunityId',
        Kind__c = 'Salesforce'
      ),
      new Time_Drive_Source__mdt(
        DeveloperName = 'Order_Canceled',
        Label = 'Order canceled',
        Active__c = true,
        Sequence__c = 12,
        Parent_Object__c = 'Contact',
        Object_Name__c = 'Task',
        Parent_Field__c = 'WhoId',
        Date_Field__c = 'LastModifiedDate',
        Filter__c = 'Subject LIKE \'Order%\' AND Status = \'Deferred\'',
        Title__c = 'Order canceled',
        Subtitle__c = '{Subject} · {Description}',
        Event_Type__c = 'canceled',
        Event_Label__c = 'Orders canceled',
        Category__c = 'Commerce',
        Icon__c = 'utility:close',
        Icon_Colour__c = '#C62F2F',
        Max_Records__c = 1000,
        Kind__c = 'Salesforce'
      ),
      new Time_Drive_Source__mdt(
        DeveloperName = 'Order_Delivered',
        Label = 'Order delivered',
        Active__c = true,
        Sequence__c = 11,
        Parent_Object__c = 'Contact',
        Object_Name__c = 'Task',
        Parent_Field__c = 'WhoId',
        Date_Field__c = 'ActivityDate',
        Filter__c = 'Subject LIKE \'Order%\' AND Status = \'Completed\'',
        Title__c = 'Order delivered',
        Subtitle__c = '{Subject} · {Account.Name}',
        Event_Type__c = 'delivered',
        Event_Label__c = 'Orders delivered',
        Category__c = 'Commerce',
        Icon__c = 'utility:check',
        Icon_Colour__c = '#2F7D4F',
        Max_Records__c = 1000,
        Kind__c = 'Salesforce'
      ),
      new Time_Drive_Source__mdt(
        DeveloperName = 'Order_Placed',
        Label = 'Order placed',
        Active__c = true,
        Sequence__c = 10,
        Parent_Object__c = 'Contact',
        Object_Name__c = 'Task',
        Parent_Field__c = 'WhoId',
        Date_Field__c = 'ActivityDate',
        Filter__c = 'Subject LIKE \'Order%\'',
        Title__c = 'Order placed',
        Subtitle__c = '{Subject} · {Account.Name}',
        Event_Type__c = 'purchase',
        Event_Label__c = 'Orders placed',
        Category__c = 'Commerce',
        Icon__c = 'utility:clock',
        Icon_Colour__c = '#2F7D4F',
        Max_Records__c = 1000,
        Kind__c = 'Salesforce'
      ),
      new Time_Drive_Source__mdt(
        DeveloperName = 'Review',
        Label = 'Review',
        Active__c = true,
        Sequence__c = 20,
        Parent_Object__c = 'Contact',
        Object_Name__c = 'Task',
        Parent_Field__c = 'WhoId',
        Date_Field__c = 'CreatedDate',
        Filter__c = 'Subject LIKE \'Review%\'',
        Title__c = '{Subject}',
        Subtitle__c = '{Description}',
        Event_Type__c = 'review',
        Event_Label__c = 'Reviews',
        Category__c = 'Service',
        Icon__c = 'utility:favorite',
        Icon_Colour__c = '#B07A0C',
        Max_Records__c = 1000,
        Kind__c = 'Salesforce'
      )
    };
  }

  /**
   * The stand-in detail fields by source developer name.
   *
   * @return the detail fields
   */
  public static Map<String, List<Time_Drive_Detail_Field__mdt>> detailFields() {
    Map<String, List<Time_Drive_Detail_Field__mdt>> out = new Map<String, List<Time_Drive_Detail_Field__mdt>>();
    add(
      out,
      'Data_360_App',
      new Time_Drive_Detail_Field__mdt(
        DeveloperName = 'Data_360_App_Action',
        Label = 'Channel action',
        Field__c = 'ssot__EngagementChannelActionId__c',
        Sequence__c = 10,
        Format__c = 'Text'
      )
    );
    add(
      out,
      'Data_360_Cart',
      new Time_Drive_Detail_Field__mdt(
        DeveloperName = 'Data_360_Cart_Action',
        Label = 'Channel action',
        Field__c = 'ssot__EngagementChannelActionId__c',
        Sequence__c = 10,
        Format__c = 'Text'
      )
    );
    add(
      out,
      'Data_360_Email',
      new Time_Drive_Detail_Field__mdt(
        DeveloperName = 'Data_360_Email_Action',
        Label = 'Channel action',
        Field__c = 'ssot__EngagementChannelActionId__c',
        Sequence__c = 10,
        Format__c = 'Text'
      )
    );
    add(
      out,
      'Data_360_Message',
      new Time_Drive_Detail_Field__mdt(
        DeveloperName = 'Data_360_Message_Action',
        Label = 'Channel action',
        Field__c = 'ssot__EngagementChannelActionId__c',
        Sequence__c = 10,
        Format__c = 'Text'
      )
    );
    add(
      out,
      'Data_360_Web_Search',
      new Time_Drive_Detail_Field__mdt(
        DeveloperName = 'Data_360_Web_Search_Action',
        Label = 'Channel action',
        Field__c = 'ssot__EngagementChannelActionId__c',
        Sequence__c = 10,
        Format__c = 'Text'
      )
    );
    add(
      out,
      'Data_360_Website',
      new Time_Drive_Detail_Field__mdt(
        DeveloperName = 'Data_360_Website_Action',
        Label = 'Channel action',
        Field__c = 'ssot__EngagementChannelActionId__c',
        Sequence__c = 10,
        Format__c = 'Text'
      )
    );
    return out;
  }

  private static void add(
    Map<String, List<Time_Drive_Detail_Field__mdt>> out,
    String source,
    Time_Drive_Detail_Field__mdt field
  ) {
    if (!out.containsKey(source)) {
      out.put(source, new List<Time_Drive_Detail_Field__mdt>());
    }
    out.get(source).add(field);
  }
}
