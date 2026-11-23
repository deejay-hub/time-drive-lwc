/**
 * The diagnostics drawer's trace (getTimelineTrace): what each source did,
 * for everyone; the SOQL and limits only for admins with Time Drive Setup or
 * a Login As session.
 */
@IsTest
private class TimeDriveTraceTest {
  private static Time_Drive_Source__mdt source(String name, String objectName, String parentField) {
    return new Time_Drive_Source__mdt(
      DeveloperName = name,
      Label = name,
      Active__c = true,
      Kind__c = TimeDriveContext.KIND_SALESFORCE,
      Parent_Object__c = 'Contact',
      Object_Name__c = objectName,
      Date_Field__c = 'CreatedDate',
      Parent_Field__c = parentField,
      Event_Type__c = 'task',
      Title__c = '{Subject}',
      Max_Records__c = 100
    );
  }

  // A Time Drive user (not an admin) who, on Minimum Access, can't read Cases.
  private static User reader() {
    List<Profile> minimum = [SELECT Id FROM Profile WHERE Name = 'Minimum Access - Salesforce' LIMIT 1];
    if (minimum.isEmpty()) {
      return null;
    }
    String name = 'tdtrace' + System.currentTimeMillis() + Math.abs(Crypto.getRandomInteger());
    User u = new User(
      Alias = 'tdtrace',
      Email = name + '@example.com',
      EmailEncodingKey = 'UTF-8',
      LastName = 'Time Drive Reader',
      LanguageLocaleKey = 'en_US',
      LocaleSidKey = 'en_US',
      ProfileId = minimum[0].Id,
      TimeZoneSidKey = 'America/Los_Angeles',
      Username = name + '@example.com'
    );
    System.runAs(new User(Id = UserInfo.getUserId())) {
      insert u;
      insert new PermissionSetAssignment(
        AssigneeId = u.Id,
        PermissionSetId = [
          SELECT Id
          FROM PermissionSet
          WHERE Name = 'Time_Drive' AND NamespacePrefix = :TimeDriveConfig.NAMESPACE
          LIMIT 1
        ]
        .Id
      );
    }
    return u;
  }

  private static TimeDriveController.TimelineLoad trace(Id contactId) {
    return TimeDriveController.getTimelineTrace(contactId, null, null, '1', 'None', null, true, false, 7);
  }

  @IsTest
  static void anAdminSeesEachSourcesSoqlRowsAndLimits() {
    System.runAs(TimeDriveTestData.setupAdmin()) {
      Contact c = new Contact(LastName = 'Traced');
      insert c;
      insert new Task(WhoId = c.Id, Subject = 'Call', ActivityDate = Date.today(), Status = 'Not Started');
      TimeDriveConfig.testSources = new List<Time_Drive_Source__mdt>{ source('Tasks', 'Task', 'WhoId') };
      TimeDriveController.TimelineLoad load = trace(c.Id);
      TimeDriveController.Trace t = load.trace;
      Assert.isTrue(t.full, 'an admin with Time Drive Setup');
      Assert.isNotNull(t.cpuMs);
      Assert.isNotNull(t.queryLimit);
      Assert.isNotNull(t.serverMs);
      TimeDriveQueries.Ran rows;
      for (TimeDriveQueries.Ran line : t.lines) {
        if (line.source == 'Tasks' && line.kind == 'rows') {
          rows = line;
        }
      }
      Assert.isNotNull(rows, JSON.serialize(t.lines));
      Assert.isTrue(rows.soql.contains('FROM Task'), rows.soql);
      Assert.isTrue(rows.soql.contains(':parentId'), 'values as binds, never in the text');
      Assert.isFalse(rows.soql.contains(String.valueOf(c.Id)), rows.soql);
      Assert.areEqual(1, rows.rows);
      // getTimeline itself is never traced.
      Assert.isNull(TimeDriveController.getTimeline(c.Id, null, null, '1', 'None', null, true, false, 7).trace);
    }
  }

  @IsTest
  static void aUserSeesWhatHappenedNotHowItWasSetUpUnlessLoggedInAs() {
    User u = reader();
    if (u == null) {
      return;
    }
    Id contactId;
    System.runAs(TimeDriveTestData.setupAdmin()) {
      Contact c = new Contact(LastName = 'Traced');
      insert c;
      contactId = c.Id;
    }
    TimeDriveConfig.testSources = new List<Time_Drive_Source__mdt>{ source('Cases', 'Case', 'ContactId') };
    System.runAs(u) {
      TimeDriveController.Trace t = trace(contactId).trace;
      Assert.isFalse(t.full);
      Assert.isNull(t.cpuMs, 'no limits');
      Boolean leftOut = false;
      for (TimeDriveQueries.Ran line : t.lines) {
        if (line.kind == TimeDriveQueries.LEFT_OUT) {
          leftOut = true;
          Assert.areEqual('Cases', line.source);
          Assert.areEqual('can\'t read Case', line.soql, 'why it\'s missing, for everyone');
        } else if (line.kind != TimeDriveQueries.FAILED) {
          Assert.isNull(line.soql, 'no SOQL: ' + line.kind);
        }
      }
      Assert.isTrue(leftOut, JSON.serialize(t.lines));

      // An admin logged in as this user sees it all, with the user's access.
      TimeDriveController.loggedInAsForTest = true;
      TimeDriveController.Trace asUser = trace(contactId).trace;
      Assert.isTrue(asUser.full);
      Assert.isNotNull(asUser.cpuMs);
    }
  }

  // A page of days whose source fails: not thrown, but traced: the kind for
  // the card, and (for an admin) the exception's own type and message.
  @IsTest
  static void aTracedPageThatFailsSaysWhyInsteadOfThrowing() {
    System.runAs(TimeDriveTestData.setupAdmin()) {
      Contact c = new Contact(LastName = 'Traced');
      insert c;
      insert new Task(WhoId = c.Id, Subject = 'Order 1', ActivityDate = Date.today(), Status = 'Not Started');
      TimeDriveConfig.testSources = new List<Time_Drive_Source__mdt>{
        new Time_Drive_Source__mdt(
          DeveloperName = 'Points',
          Label = 'Points',
          Active__c = true,
          Parent_Object__c = 'Contact',
          Kind__c = 'Apex',
          Provider_Class__c = 'TimeDriveControllerTest.CountsButRowsFail',
          Event_Type__c = 'loyalty',
          Event_Label__c = 'Loyalty points'
        )
      };
      String today = Datetime.now().format('yyyy-MM-dd');
      TimeDriveController.DaysLoad page = TimeDriveController.getPageDaysTrace(
        c.Id,
        null,
        null,
        null,
        null,
        new List<String>{ today },
        new List<String>(),
        null,
        null,
        null
      );
      Assert.isNotNull(page.trace.failedKind, 'the card still learns it failed');
      Assert.isTrue(page.events.isEmpty());
      TimeDriveQueries.Ran failed;
      for (TimeDriveQueries.Ran line : page.trace.lines) {
        if (line.kind == TimeDriveQueries.FAILED && line.source == 'Points') {
          failed = line;
        }
      }
      Assert.isNotNull(failed, JSON.serialize(page.trace.lines));
      Assert.isTrue(failed.error.contains('RowsBrokeException'), 'its own type, for an admin: ' + failed.error);
      Assert.isTrue(failed.error.contains('the rows could not be read'), failed.error);
      Assert.isNotNull(page.trace.sourcesFrom);
    }
  }

  // Without a full trace, the error's own words are left out (its kind stays).
  @IsTest
  static void aUsersTraceKeepsTheKindNotTheError() {
    User u = reader();
    if (u == null) {
      return;
    }
    TimeDriveConfig.testSources = new List<Time_Drive_Source__mdt>{
      new Time_Drive_Source__mdt(
        DeveloperName = 'Points',
        Label = 'Points',
        Active__c = true,
        Parent_Object__c = 'Contact',
        Kind__c = 'Apex',
        Provider_Class__c = 'TimeDriveControllerTest.CountsButRowsFail',
        Event_Type__c = 'loyalty',
        Event_Label__c = 'Loyalty points'
      )
    };
    Id contactId;
    System.runAs(TimeDriveTestData.setupAdmin()) {
      Contact c = new Contact(LastName = 'Traced');
      insert c;
      contactId = c.Id;
    }
    System.runAs(u) {
      TimeDriveController.DaysLoad page = TimeDriveController.getPageDaysTrace(
        contactId,
        null,
        null,
        null,
        null,
        new List<String>{ Datetime.now().format('yyyy-MM-dd') },
        new List<String>(),
        null,
        null,
        null
      );
      Assert.isFalse(page.trace.full);
      for (TimeDriveQueries.Ran line : page.trace.lines) {
        Assert.isNull(line.error, 'no error text without a full trace');
      }
    }
  }
}
