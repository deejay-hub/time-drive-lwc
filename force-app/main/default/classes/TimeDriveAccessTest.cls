/**
 * What someone sees follows what they can read: a source on an object they
 * can't read is simply left out of their timeline (no error page, nothing
 * logged), as their access is meant to work.
 */
@IsTest
private class TimeDriveAccessTest {
  // A user who can see the timeline (the Time Drive permission set) but, on
  // the Minimum Access profile, can't read Cases. Null where the org has no
  // such profile.
  private static User caselessUser() {
    List<Profile> minimum = [SELECT Id FROM Profile WHERE Name = 'Minimum Access - Salesforce' LIMIT 1];
    if (minimum.isEmpty()) {
      return null;
    }
    String name = 'tdcaseless' + System.currentTimeMillis() + Math.abs(Crypto.getRandomInteger());
    User u = new User(
      Alias = 'tdmin',
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

  @IsTest
  static void aSourceOnAnObjectTheUserCantReadIsLeftOutNotAnError() {
    User reader = caselessUser();
    if (reader == null) {
      return;
    }
    Id contactId;
    System.runAs(TimeDriveTestData.setupAdmin()) {
      Contact c = new Contact(LastName = 'Access');
      insert c;
      contactId = c.Id;
    }
    TimeDriveConfig.testSources = new List<Time_Drive_Source__mdt>{
      new Time_Drive_Source__mdt(
        DeveloperName = 'Contact_Cases',
        Label = 'Cases',
        Active__c = true,
        Kind__c = TimeDriveContext.KIND_SALESFORCE,
        Parent_Object__c = 'Contact',
        Object_Name__c = 'Case',
        Date_Field__c = 'CreatedDate',
        Parent_Field__c = 'ContactId',
        Event_Type__c = 'case',
        Title__c = '{Subject}',
        Max_Records__c = 100
      )
    };
    System.runAs(reader) {
      Assert.isFalse(TimeDriveConfig.canRead('Case'), 'the profile can\'t read Cases');
      TimeDriveController.TimelineLoad load = TimeDriveController.getTimeline(
        contactId,
        null,
        null,
        null,
        null,
        null,
        true,
        false,
        7
      );
      Assert.isTrue(load.summary.problems.isEmpty(), 'not theirs to see, so not a problem');
      Assert.areEqual(0, load.summary.total);
    }
    Assert.areEqual(0, [SELECT COUNT() FROM Time_Drive_Log__c], 'and nothing logged');
  }

  @IsTest
  static void readsAFieldOnlyWhenEveryStepToItCanBeRead() {
    Assert.isTrue(TimeDriveConfig.canRead('Contact', 'LastName'));
    Assert.isTrue(TimeDriveConfig.canRead('Contact', 'Account.Name'), 'a lookup, then a field');
    Assert.isTrue(TimeDriveConfig.canRead('Task', 'What.Name'), 'polymorphic: left to the query');
    Assert.isTrue(TimeDriveConfig.canRead('Contact', 'No_Such_Field__c'), 'unknown: left to the query to report');
    Assert.isTrue(TimeDriveConfig.canRead(null, 'Name'));
    User reader = caselessUser();
    if (reader == null) {
      return;
    }
    System.runAs(reader) {
      Assert.isFalse(TimeDriveConfig.canRead('Case'));
      Assert.isFalse(TimeDriveConfig.canRead('Case', 'Subject'), 'a field on an object they can\'t read');
    }
  }
}
