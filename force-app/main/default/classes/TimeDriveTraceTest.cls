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
}
