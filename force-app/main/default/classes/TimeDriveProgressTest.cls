// Setup's progress is the admin's; the test that matters (a person without Setup access) runs as that person.
@SuppressWarnings('PMD.ApexUnitTestClassShouldHaveRunAs')
@IsTest
private class TimeDriveProgressTest {
  @IsTest
  static void nothingIsDoneUntilSaid() {
    TimeDriveSetupController.Progress p = TimeDriveSetupController.getProgress();
    System.assertEquals(0, p.steps.size(), 'the org check is not done unless it is recorded');
    System.assertEquals(null, p.report);
  }

  @IsTest
  static void theStepsAndTheReportAreKeptForTheOrg() {
    TimeDriveSetupController.saveProgress(new List<String>{ 'orgcheck', 'views' }, '{"found":1}');
    TimeDriveSetupController.saveProgress(new List<String>{ 'orgcheck' }, null);
    TimeDriveSetupController.Progress p = TimeDriveSetupController.getProgress();
    System.assertEquals(new List<String>{ 'orgcheck' }, p.steps);
    System.assertEquals('{"found":1}', p.report, 'saving the steps left the report alone');
    System.assertEquals(1, [SELECT COUNT() FROM Time_Drive_Setup__c], 'one row for the org');
  }

  @IsTest
  static void onlyAdminsMayReadOrWriteIt() {
    Profile standard = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
    User other = new User(
      Alias = 'plain',
      Email = 'plain@example.com',
      EmailEncodingKey = 'UTF-8',
      LastName = 'Plain',
      LanguageLocaleKey = 'en_US',
      LocaleSidKey = 'en_US',
      ProfileId = standard.Id,
      TimeZoneSidKey = 'America/Los_Angeles',
      Username = 'plain' + System.currentTimeMillis() + '@example.com'
    );
    insert other;
    String refused = 'Only admins (with the Time Drive Setup permission set) can manage timeline sources.';
    System.runAs(other) {
      try {
        TimeDriveSetupController.getProgress();
        Assert.fail('a person without Setup access reads nothing');
      } catch (AuraHandledException e) {
        Assert.areEqual(refused, e.getMessage());
      }
      try {
        TimeDriveSetupController.saveProgress(new List<String>{ 'orgcheck' }, null);
        Assert.fail('a person without Setup access writes nothing');
      } catch (AuraHandledException e) {
        Assert.areEqual(refused, e.getMessage());
      }
    }
    Assert.areEqual(0, [SELECT COUNT() FROM Time_Drive_Setup__c], 'nothing was written');
  }
}
