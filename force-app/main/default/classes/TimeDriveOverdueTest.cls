/**
 * The Overdue lens's banner check (TimeDriveController.getOverdue): yes when
 * the lens's sources have an item, no otherwise; once per object, not per
 * source; nothing when the lens is switched off. Runs as users west and east
 * of Greenwich, as the lens's filter (ActivityDate < TODAY) is the user's day.
 */
@IsTest
private class TimeDriveOverdueTest {
  private static final String OVERDUE_FILTER = 'IsClosed = false AND ActivityDate < TODAY';

  private static Time_Drive_Source__mdt source(
    String name,
    String objectName,
    String dateField,
    String parentField,
    String filter,
    String lenses
  ) {
    return new Time_Drive_Source__mdt(
      DeveloperName = name,
      Label = name,
      Active__c = true,
      Sequence__c = 1,
      Kind__c = TimeDriveContext.KIND_SALESFORCE,
      Parent_Object__c = 'Contact',
      Object_Name__c = objectName,
      Date_Field__c = dateField,
      Parent_Field__c = parentField,
      Filter__c = filter,
      Lenses__c = lenses,
      Category__c = lenses.substringBefore(';'),
      Event_Type__c = name.toLowerCase(),
      Title__c = '{Subject}',
      Max_Records__c = 100
    );
  }

  // The lenses as shipped: All, Sales and Overdue.
  private static void lenses() {
    TimeDriveConfig.testViews = new List<Time_Drive_View__mdt>{
      new Time_Drive_View__mdt(DeveloperName = 'All', Label = 'All', Sequence__c = 1),
      new Time_Drive_View__mdt(DeveloperName = 'Sales', Label = 'Sales', Sequence__c = 10),
      new Time_Drive_View__mdt(DeveloperName = 'Overdue', Label = 'Overdue', Sequence__c = 90)
    };
  }

  private static Integer anyQueries() {
    Integer n = 0;
    for (TimeDriveQueries.Ran q : TimeDriveQueries.ran) {
      n += q.kind == 'any' ? 1 : 0;
    }
    return n;
  }

  @IsTest
  static void saysWhetherTheOverdueLensHasItemsInEveryTimeZone() {
    for (String zone : new List<String>{ 'America/Los_Angeles', 'Pacific/Tongatapu' }) {
      System.runAs(TimeDriveTestData.adminIn(zone)) {
        lenses();
        TimeDriveConfig.testSources = new List<Time_Drive_Source__mdt>{
          source('Tasks', 'Task', 'ActivityDate', 'WhoId', null, 'All;Sales'),
          source('Overdue_Tasks', 'Task', 'ActivityDate', 'WhoId', OVERDUE_FILTER, 'Overdue')
        };
        Contact c = new Contact(LastName = 'Late ' + zone);
        insert c;
        // Done, or not due yet: nothing overdue.
        insert new List<Task>{
          new Task(WhoId = c.Id, Subject = 'Done', ActivityDate = Date.today().addDays(-5), Status = 'Completed'),
          new Task(WhoId = c.Id, Subject = 'Today', ActivityDate = Date.today(), Status = 'Not Started'),
          new Task(WhoId = c.Id, Subject = 'Later', ActivityDate = Date.today().addDays(3), Status = 'Not Started')
        };
        Assert.isFalse(TimeDriveController.getOverdue(c.Id, '1', null), zone + ': due today is not overdue');

        insert new Task(
          WhoId = c.Id,
          Subject = 'Late',
          ActivityDate = Date.today().addDays(-1),
          Status = 'Not Started'
        );
        Assert.isTrue(TimeDriveController.getOverdue(c.Id, '1', null), zone + ': due yesterday and open is');
      }
    }
  }

  @IsTest
  static void asksEachObjectOnceNotEachSource() {
    System.runAs(TimeDriveTestData.adminIn('America/Los_Angeles')) {
      lenses();
      TimeDriveConfig.testSources = new List<Time_Drive_Source__mdt>{
        source(
          'Overdue_Calls',
          'Task',
          'ActivityDate',
          'WhoId',
          OVERDUE_FILTER + ' AND TaskSubtype = \'Call\'',
          'Overdue'
        ),
        source(
          'Overdue_Tasks',
          'Task',
          'ActivityDate',
          'WhoId',
          OVERDUE_FILTER + ' AND TaskSubtype = \'Task\'',
          'Overdue'
        ),
        source(
          'Overdue_Emails',
          'Task',
          'ActivityDate',
          'WhoId',
          OVERDUE_FILTER + ' AND TaskSubtype = \'Email\'',
          'Overdue'
        ),
        source('Open_Cases', 'Case', 'CreatedDate', 'ContactId', 'IsClosed = false', 'Overdue'),
        // Not in the Overdue lens: never asked.
        source('Tasks', 'Task', 'ActivityDate', 'WhoId', null, 'All')
      };
      Contact c = new Contact(LastName = 'Quiet');
      insert c;
      TimeDriveQueries.ran.clear();
      // Nothing anywhere: every object asked, once each (Task, then Case).
      Assert.isFalse(TimeDriveController.getOverdue(c.Id, '1', null));
      Assert.areEqual(
        2,
        anyQueries(),
        'one query for the three Task sources, one for Cases: ' + TimeDriveQueries.ran.size()
      );

      // An overdue call: found by the first query, so Cases aren't asked.
      insert new Task(
        WhoId = c.Id,
        Subject = 'Call back',
        TaskSubtype = 'Call',
        ActivityDate = Date.today().addDays(-2),
        Status = 'Not Started'
      );
      TimeDriveQueries.ran.clear();
      Assert.isTrue(TimeDriveController.getOverdue(c.Id, '1', null));
      Assert.areEqual(1, anyQueries(), 'it stops at the first that has one');
    }
  }

  @IsTest
  static void nothingWhenTheOverdueLensIsOff() {
    System.runAs(TimeDriveTestData.adminIn('America/Los_Angeles')) {
      lenses();
      TimeDriveConfig.testSources = new List<Time_Drive_Source__mdt>{
        source('Overdue_Tasks', 'Task', 'ActivityDate', 'WhoId', OVERDUE_FILTER, 'Overdue')
      };
      Contact c = new Contact(LastName = 'Off');
      insert c;
      insert new Task(WhoId = c.Id, Subject = 'Late', ActivityDate = Date.today().addDays(-1), Status = 'Not Started');
      Assert.isTrue(TimeDriveController.getOverdue(c.Id, '1', null));
      insert new Time_Drive_Setup__c(Name = 'Org', Hidden_Views__c = 'Overdue');
      TimeDriveConfig.forgetHiddenViews();
      TimeDriveQueries.ran.clear();
      Assert.isFalse(TimeDriveController.getOverdue(c.Id, '1', null), 'switched off: no banner');
      Assert.areEqual(0, anyQueries(), 'and nothing is asked');
      Assert.isFalse(TimeDriveController.getOverdue(null, '1', null), 'no record, no banner');
    }
  }

  @IsTest
  static void anOverdueTemplatesCopyIsInTheOverdueLensOnly() {
    System.runAs(TimeDriveTestData.setupAdmin()) {
      String key = TimeDriveSetupController.useTemplate('Overdue_Tasks').developerName;
      Time_Drive_Record__c copy = [SELECT Lenses__c, Filter__c FROM Time_Drive_Record__c WHERE Key__c = :key];
      Assert.areEqual('Overdue', copy.Lenses__c, 'not All too: its tasks are in All already');
      Assert.areEqual(OVERDUE_FILTER, copy.Filter__c);
    }
  }
}
