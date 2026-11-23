/**
 * The Overdue button's check (TimeDriveController.getOverdue): yes when
 * the lens's sources have an item, no otherwise; once per object, not per
 * source; nothing when the lens is switched off. Runs as users west and east
 * of Greenwich, as the Overdue field's TODAY() is the user's day. Also the
 * field as a highlight, and the templates' highlights: overdue Tasks,
 * escalated Cases.
 */
@IsTest
private class TimeDriveOverdueTest {
  // The Overdue lens's filter: Time Drive's own formula checkbox on Activity.
  private static final String OVERDUE_FILTER = 'Overdue__c = true';

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
      n += q.kind == 'any' ? q.times : 0;
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
      TimeDriveQueries.clear();
      // Nothing anywhere: every object asked, once each (Task, then Case).
      Assert.isFalse(TimeDriveController.getOverdue(c.Id, '1', null));
      Assert.areEqual(2, anyQueries(), 'one query for the three Task sources, one for Cases: ' + anyQueries());

      // An overdue call: found by the first query, so Cases aren't asked.
      insert new Task(
        WhoId = c.Id,
        Subject = 'Call back',
        TaskSubtype = 'Call',
        ActivityDate = Date.today().addDays(-2),
        Status = 'Not Started'
      );
      TimeDriveQueries.clear();
      Assert.isTrue(TimeDriveController.getOverdue(c.Id, '1', null));
      Assert.areEqual(1, anyQueries(), 'it stops at the first that has one');
    }
  }

  @IsTest
  static void aJunctionSourceIsAskedOnItsOwnBesideAnother() {
    // A sub-select can't sit inside OR: with a TaskRelation source in the lens
    // beside another Task source, a merged query would fail and say nothing
    // is overdue. Orgs without Shared Activities have no TaskRelation.
    if (TimeDriveConfig.sObjectType('TaskRelation') == null) {
      return;
    }
    System.runAs(TimeDriveTestData.adminIn('America/Los_Angeles')) {
      lenses();
      Time_Drive_Source__mdt every = source('Overdue_Every', 'Task', 'ActivityDate', null, OVERDUE_FILTER, 'Overdue');
      every.Junction_Object__c = 'TaskRelation';
      every.Junction_Parent_Field__c = 'RelationId';
      every.Junction_Record_Field__c = 'TaskId';
      TimeDriveConfig.testSources = new List<Time_Drive_Source__mdt>{
        every,
        source(
          'Overdue_Calls',
          'Task',
          'ActivityDate',
          'WhoId',
          OVERDUE_FILTER + ' AND TaskSubtype = \'Call\'',
          'Overdue'
        )
      };
      Contact c = new Contact(LastName = 'Shared');
      insert c;
      insert new Task(WhoId = c.Id, Subject = 'Late', ActivityDate = Date.today().addDays(-2), Status = 'Not Started');
      TimeDriveQueries.clear();
      Assert.isTrue(TimeDriveController.getOverdue(c.Id, '1', null), 'found through the junction');
      for (TimeDriveQueries.Ran q : TimeDriveQueries.ran) {
        if (q.kind == 'any') {
          Assert.isFalse(
            q.soql.containsIgnoreCase('(SELECT') && q.soql.contains(') OR ('),
            'no sub-select inside OR: ' + q.soql
          );
        }
      }
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
      TimeDriveQueries.clear();
      Assert.isFalse(TimeDriveController.getOverdue(c.Id, '1', null), 'switched off: no button');
      Assert.areEqual(0, anyQueries(), 'and nothing is asked');
      Assert.isFalse(TimeDriveController.getOverdue(null, '1', null), 'no record, no button');
    }
  }

  @IsTest
  static void anOverdueTemplatesCopyIsInTheOverdueLensOnly() {
    System.runAs(TimeDriveTestData.setupAdmin()) {
      String key = TimeDriveSetupController.useTemplate('Contact_Overdue_Tasks').developerName;
      Time_Drive_Record__c copy = [
        SELECT Lenses__c, Filter__c, Highlight_Field__c, Highlight_Icon__c
        FROM Time_Drive_Record__c
        WHERE Key__c = :key
      ];
      Assert.areEqual('Overdue', copy.Lenses__c, 'not All too: its tasks are in All already');
      Assert.areEqual(OVERDUE_FILTER, copy.Filter__c);
      // The same highlight as the Tasks templates, so overdue tasks look alike in every lens.
      Assert.areEqual('Overdue__c', copy.Highlight_Field__c);
      Assert.areEqual('utility:clock', copy.Highlight_Icon__c);
    }
  }

  private static Map<String, TimeDriveController.EngagementEvent> plotted(Id who, Time_Drive_Source__mdt s) {
    Map<String, TimeDriveController.EngagementEvent> byTitle = new Map<String, TimeDriveController.EngagementEvent>();
    for (
      TimeDriveController.EngagementEvent e : TimeDrivePlotter.run(
        new TimeDriveSoqlProvider(),
        new TimeDriveContext(who, 'Contact', Datetime.now().addDays(-30), s, null, null)
      )
    ) {
      byTitle.put(e.title, e);
    }
    return byTitle;
  }

  @IsTest
  static void theOverdueFieldMarksOpenTasksDueBeforeTodayInEveryTimeZone() {
    for (String zone : new List<String>{ 'America/Los_Angeles', 'Pacific/Tongatapu' }) {
      System.runAs(TimeDriveTestData.adminIn(zone)) {
        Contact c = new Contact(LastName = 'Flags ' + zone);
        insert c;
        insert new List<Task>{
          new Task(WhoId = c.Id, Subject = 'Late', ActivityDate = Date.today().addDays(-1), Status = 'Not Started'),
          new Task(WhoId = c.Id, Subject = 'Today', ActivityDate = Date.today(), Status = 'Not Started'),
          new Task(WhoId = c.Id, Subject = 'Done late', ActivityDate = Date.today().addDays(-3), Status = 'Completed')
        };
        // A checkbox highlight like any other: Time Drive's own field, by its short name.
        TimeDriveConfig.testHighlights = new Map<String, List<Time_Drive_Highlight__mdt>>{
          'Tasks' => new List<Time_Drive_Highlight__mdt>{
            new Time_Drive_Highlight__mdt(Field__c = 'Overdue__c', Icon__c = 'utility:clock', Colour__c = '#C23934')
          }
        };
        Map<String, TimeDriveController.EngagementEvent> byTitle = plotted(
          c.Id,
          source('Tasks', 'Task', 'ActivityDate', 'WhoId', null, 'All')
        );
        TimeDriveController.EngagementEvent late = byTitle.get('Late');
        Assert.areEqual(1, late?.flags?.size(), zone + ': open and due yesterday is overdue');
        Assert.areEqual('utility:clock', late.flags[0].icon);
        Assert.areEqual(
          TimeDriveConfig.fieldDescribe('Task', 'Overdue__c').getLabel(),
          late.flags[0].text,
          'it says the field\'s label'
        );
        Assert.isNull(byTitle.get('Today').flags, zone + ': due today is not overdue');
        Assert.isNull(byTitle.get('Done late').flags, zone + ': a closed task never is');
      }
    }
  }

  @IsTest
  static void theTaskAndCaseTemplatesBringTheirHighlights() {
    System.runAs(TimeDriveTestData.setupAdmin()) {
      String tasks = TimeDriveSetupController.useTemplate('Contact_Tasks').developerName;
      String cases = TimeDriveSetupController.useTemplate('Contact_Cases').developerName;
      Map<String, Time_Drive_Record__c> byKey = new Map<String, Time_Drive_Record__c>();
      for (Time_Drive_Record__c r : [
        SELECT Key__c, Highlight_Field__c, Highlight_Icon__c
        FROM Time_Drive_Record__c
        WHERE Key__c IN :new List<String>{ tasks, cases }
      ]) {
        byKey.put(r.Key__c, r);
      }
      Assert.areEqual('Overdue__c', byKey.get(tasks).Highlight_Field__c, 'Tasks: overdue, by the field');
      Assert.areEqual('utility:clock', byKey.get(tasks).Highlight_Icon__c);
      Assert.areEqual('IsEscalated', byKey.get(cases).Highlight_Field__c, 'Cases: escalated');
    }
  }
}
