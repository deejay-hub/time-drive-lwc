@IsTest
private class TimeDrivePreferenceTest {
  @IsTest
  static void nothingIsKeptUntilSomethingIsChosen() {
    TimeDriveController.Preference p = TimeDriveController.getPreference();
    System.assertEquals(null, p.lens);
    System.assertEquals(null, p.itemDetail);
  }

  @IsTest
  static void theLensAndTheLabelChoiceAreKeptApart() {
    TimeDriveController.savePreference('Activity', null);
    TimeDriveController.savePreference(null, 'lite');
    TimeDriveController.Preference p = TimeDriveController.getPreference();
    System.assertEquals('Activity', p.lens, 'saving the labels left the lens alone');
    System.assertEquals('Lite', p.itemDetail);

    TimeDriveController.savePreference('All', 'max');
    p = TimeDriveController.getPreference();
    System.assertEquals('All', p.lens);
    System.assertEquals('Max', p.itemDetail);
    System.assertEquals(1, [SELECT COUNT() FROM Time_Drive_Preference__c], 'one row for the user');
  }

  @IsTest
  static void anotherUsersChoiceIsNotMine() {
    Profile standard = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
    User other = new User(
      Alias = 'other',
      Email = 'other@example.com',
      EmailEncodingKey = 'UTF-8',
      LastName = 'Other',
      LanguageLocaleKey = 'en_US',
      LocaleSidKey = 'en_US',
      ProfileId = standard.Id,
      TimeZoneSidKey = 'America/Los_Angeles',
      Username = 'other' + System.currentTimeMillis() + '@example.com'
    );
    insert other;
    insert new Time_Drive_Preference__c(SetupOwnerId = other.Id, Last_Lens__c = 'Email', Item_Detail__c = 'Lite');
    TimeDriveController.Preference p = TimeDriveController.getPreference();
    System.assertEquals(null, p.lens, 'someone else\'s lens is not mine');
    System.assertEquals(null, p.itemDetail);
  }
}
