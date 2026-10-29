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
    System.runAs(other) {
      try {
        TimeDriveSetupController.getProgress();
        System.assert(false, 'a person without Setup access reads nothing');
      } catch (AuraHandledException e) {
        System.assert(true);
      }
      try {
        TimeDriveSetupController.saveProgress(new List<String>{ 'orgcheck' }, null);
        System.assert(false, 'a person without Setup access writes nothing');
      } catch (AuraHandledException e) {
        System.assert(true);
      }
    }
  }
}
