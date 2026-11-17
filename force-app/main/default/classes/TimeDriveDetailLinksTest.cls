/**
 * An opened item's details link to the records they name: a path through a
 * lookup (What.Name) to that lookup's record, a lookup chosen as itself to
 * the record it holds, and for an Apex source whatever key it names with
 * Plot.links. Plain values, and text that only looks like an Id, aren't links.
 */
@IsTest
private class TimeDriveDetailLinksTest {
  private static Time_Drive_Detail_Field__mdt detail(String field) {
    return new Time_Drive_Detail_Field__mdt(Label = field, Field__c = field);
  }

  @IsTest
  static void aDetailThroughALookupLinksToItsRecord() {
    System.runAs(TimeDriveTestData.adminIn('America/Los_Angeles')) {
      Account acme = new Account(Name = 'Acme Ltd');
      insert acme;
      Contact c = new Contact(LastName = 'Linked', AccountId = acme.Id);
      insert c;
      insert new Task(
        WhoId = c.Id,
        WhatId = acme.Id,
        Subject = 'Send quote',
        Status = 'Not Started',
        ActivityDate = Date.today()
      );
      Time_Drive_Source__mdt s = new Time_Drive_Source__mdt(
        DeveloperName = 'Tasks',
        Label = 'Tasks',
        Active__c = true,
        Kind__c = TimeDriveContext.KIND_SALESFORCE,
        Parent_Object__c = 'Contact',
        Object_Name__c = 'Task',
        Date_Field__c = 'ActivityDate',
        Parent_Field__c = 'WhoId',
        Event_Type__c = 'task',
        Title__c = '{Subject}',
        Max_Records__c = 100
      );
      TimeDriveContext context = new TimeDriveContext(c.Id, 'Contact', Datetime.now().addDays(-30), s, null, null);
      context.draftDetailFields = new List<Time_Drive_Detail_Field__mdt>{
        detail('What.Name'),
        detail('Status'),
        detail('WhatId')
      };
      List<TimeDriveController.EngagementEvent> events = TimeDrivePlotter.run(new TimeDriveSoqlProvider(), context);
      Assert.areEqual(1, events.size());
      // In the order chosen (their labels are the fields' own, in the user's language).
      List<TimeDriveController.Detail> details = events[0].details;
      Assert.areEqual('Acme Ltd', details[0].value);
      Assert.areEqual(acme.Id, details[0].recordId, 'Related To links to its record (What.Id)');
      Assert.isNull(details[1].recordId, 'a plain value (Status) is no link');
      Assert.areEqual(acme.Id, details[2].recordId, 'a lookup chosen as itself links to what it holds');
    }
  }

  @IsTest
  static void anApexSourceSaysWhichKeyHoldsADetailsRecord() {
    Account acme = new Account(Name = 'Acme Ltd');
    insert acme;
    TimeDriveContext context = new TimeDriveContext(acme.Id, Datetime.now().addDays(-30), Datetime.now());
    context.plotBy('Day').title('{Summary}').links('Customer', 'CustomerId');
    context.draftDetailFields = new List<Time_Drive_Detail_Field__mdt>{
      detail('Customer'),
      detail('Summary'),
      detail('Ref')
    };
    List<TimeDriveController.EngagementEvent> events = TimeDrivePlotter.plot(
      context,
      new List<TimeDriveRow>{
        new TimeDriveRow(
          new Map<String, Object>{
            'Id' => 'r1',
            'Day' => Date.today(),
            'Summary' => 'Visited',
            'Customer' => 'Acme Ltd',
            'CustomerId' => String.valueOf(acme.Id),
            // Text that parses as an Id isn't taken for one.
            'Ref' => 'abcdefghijklmno'
          }
        )
      }
    );
    List<TimeDriveController.Detail> details = events[0].details;
    Assert.areEqual(acme.Id, details[0].recordId, 'the key it named');
    Assert.isNull(details[1].recordId);
    Assert.isNull(details[2].recordId, 'text is never a link on its own');
  }

  @IsTest
  static void aLinkPathIsTheLookupsId() {
    Assert.areEqual('What.Id', TimeDrivePlotter.linkPathOf('What.Name'));
    Assert.areEqual('Opportunity.Account.Id', TimeDrivePlotter.linkPathOf('Opportunity.Account.Name'));
    Assert.isNull(TimeDrivePlotter.linkPathOf('Status'), 'the row\'s own field names no other record');
    Assert.isNull(TimeDrivePlotter.linkPathOf(null));
  }
}
