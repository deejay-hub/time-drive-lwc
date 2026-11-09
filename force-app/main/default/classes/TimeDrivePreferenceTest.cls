@IsTest
private class TimeDrivePreferenceTest {
  // A person with the Time Drive permission set and nothing else (any setup access a test needs is theirs only).
  private static User person(String alias, Boolean withPermissionSet) {
    Profile standard = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
    User u = new User(
      Alias = alias,
      Email = alias + '@example.com',
      EmailEncodingKey = 'UTF-8',
      LastName = alias,
      LanguageLocaleKey = 'en_US',
      LocaleSidKey = 'en_US',
      ProfileId = standard.Id,
      TimeZoneSidKey = 'America/Los_Angeles',
      Username = alias + System.currentTimeMillis() + '@example.com'
    );
    insert u;
    if (withPermissionSet) {
      insert new PermissionSetAssignment(
        AssigneeId = u.Id,
        PermissionSetId = [SELECT Id FROM PermissionSet WHERE Name = 'Time_Drive' LIMIT 1].Id
      );
    }
    return u;
  }

  @IsTest
  static void nothingIsKeptUntilSomethingIsChosen() {
    User u = person('fresh', true);
    System.runAs(u) {
      TimeDriveController.Preference p = TimeDriveController.getPreference();
      Assert.isNull(p.lens);
      Assert.isNull(p.itemDetail);
    }
  }

  @IsTest
  static void theLensAndTheLabelChoiceAreKeptApart() {
    User u = person('keeper', true);
    System.runAs(u) {
      TimeDriveController.savePreference('Activity', null);
      TimeDriveController.savePreference(null, 'lite');
      TimeDriveController.Preference p = TimeDriveController.getPreference();
      Assert.areEqual('Activity', p.lens, 'saving the labels left the lens alone');
      Assert.areEqual('Lite', p.itemDetail);

      TimeDriveController.savePreference('All', 'max');
      p = TimeDriveController.getPreference();
      Assert.areEqual('All', p.lens);
      Assert.areEqual('Max', p.itemDetail);
    }
  }

  @IsTest
  static void theDateRangeIsKeptUntilItIsCleared() {
    User u = person('ranger', true);
    System.runAs(u) {
      // Clearing a range never chosen keeps nothing.
      TimeDriveController.saveDateRange('');
    }
    Assert.areEqual(0, [SELECT COUNT() FROM Time_Drive_Preference__c WHERE SetupOwnerId = :u.Id]);
    System.runAs(u) {
      TimeDriveController.saveDateRange('next-1m');
      TimeDriveController.savePreference('Activity', null);
      TimeDriveController.Preference p = TimeDriveController.getPreference();
      Assert.areEqual('next-1m', p.dateRange);
      Assert.areEqual('Activity', p.lens, 'the range and the lens are kept apart');

      TimeDriveController.saveDateRange(null);
      p = TimeDriveController.getPreference();
      Assert.isNull(p.dateRange, 'cleared: the page\'s own range');
      Assert.areEqual('Activity', p.lens);
    }
  }

  @IsTest
  static void anotherUsersChoiceIsNotMine() {
    User other;
    User me;
    // Users and a custom setting are both setup data: kept in separate transactions.
    System.runAs(new User(Id = UserInfo.getUserId())) {
      other = person('other', true);
      me = person('me', true);
    }
    System.runAs(new User(Id = UserInfo.getUserId())) {
      insert new Time_Drive_Preference__c(SetupOwnerId = other.Id, Last_Lens__c = 'Email', Item_Detail__c = 'Lite');
    }
    System.runAs(me) {
      TimeDriveController.Preference p = TimeDriveController.getPreference();
      Assert.isNull(p.lens, 'someone else\'s lens is not mine');
      Assert.isNull(p.itemDetail);
    }
  }
}
