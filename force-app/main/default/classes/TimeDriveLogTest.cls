/**
 * Time Drive's problem log: one row per distinct problem, repeats counted,
 * old rows removed, a cause in plain words, and Setup's view of it.
 */
// Run as the running user on purpose, except where what an admin may do is the point.
@SuppressWarnings('PMD.ApexUnitTestClassShouldHaveRunAs')
@IsTest
private class TimeDriveLogTest {
  private class SourceBrokeException extends Exception {
  }

  @IsTest
  static void aProblemIsWrittenOnceAndItsRepeatsCounted() {
    TimeDriveLog.recordId = UserInfo.getUserId();
    Exception e = new SourceBrokeException('No such column \'Due__c\' on entity \'Task\'');
    TimeDriveLog.note('Contact_Tasks', 'Tasks', 'access', e);
    TimeDriveLog.note('Contact_Tasks', 'Tasks', 'access', e);
    TimeDriveLog.flush();
    Time_Drive_Log__c row = [
      SELECT Source_Key__c, Source__c, Kind__c, Error_Type__c, Message__c, Count__c, Last_Seen__c, Record_Id__c
      FROM Time_Drive_Log__c
    ];
    Assert.areEqual('Contact_Tasks', row.Source_Key__c);
    Assert.areEqual('Tasks', row.Source__c);
    Assert.areEqual('access', row.Kind__c);
    Assert.isTrue(row.Error_Type__c.endsWith('SourceBrokeException'), row.Error_Type__c);
    Assert.isTrue(row.Message__c.contains('Due__c'));
    Assert.areEqual(2, row.Count__c, 'both, in one row');
    Assert.isNotNull(row.Last_Seen__c);
    Assert.areEqual(String.valueOf(UserInfo.getUserId()), row.Record_Id__c);

    // The same problem in a later request adds to the same row.
    TimeDriveLog.note('Contact_Tasks', 'Tasks', 'access', e);
    TimeDriveLog.flush();
    Assert.areEqual(1, [SELECT COUNT() FROM Time_Drive_Log__c]);
    Assert.areEqual(3, [SELECT Count__c FROM Time_Drive_Log__c].Count__c);

    // Another source's problem is a row of its own.
    TimeDriveLog.note('Contact_Calls', 'Calls', 'busy', e);
    TimeDriveLog.flush();
    Assert.areEqual(2, [SELECT COUNT() FROM Time_Drive_Log__c]);
  }

  @IsTest
  static void aHiddenSourceIsNotedOnceARequest() {
    TimeDriveLog.noteHidden('Contact_Cases', 'Cases', 'Case');
    TimeDriveLog.noteHidden('Contact_Cases', 'Cases', 'Case');
    TimeDriveLog.noteHidden('Contact_Cases', 'Cases', 'Case.Priority');
    TimeDriveLog.flush();
    Assert.areEqual(2, [SELECT COUNT() FROM Time_Drive_Log__c], 'one row per reason');
    Assert.areEqual(1, [SELECT Count__c FROM Time_Drive_Log__c WHERE Location__c = 'Case'].Count__c);
  }

  @IsTest
  static void nothingNotedWritesNothingAndOldRowsGo() {
    TimeDriveLog.flush();
    Assert.areEqual(0, [SELECT COUNT() FROM Time_Drive_Log__c], 'nothing noted, nothing written');

    insert new Time_Drive_Log__c(
      Signature__c = 'old',
      Count__c = 1,
      Last_Seen__c = Datetime.now().addDays(-(TimeDriveLog.KEEP_DAYS + 1))
    );
    TimeDriveLog.note(null, null, 'unknown', new SourceBrokeException('boom'));
    TimeDriveLog.flush();
    Assert.areEqual(0, [SELECT COUNT() FROM Time_Drive_Log__c WHERE Signature__c = 'old'], 'not seen for 30 days');
    Assert.areEqual(1, [SELECT COUNT() FROM Time_Drive_Log__c]);
  }

  @IsTest
  static void saysTheLikelyCauseInPlainWords() {
    Assert.isTrue(
      TimeDriveLog.causeOf('access', 'Entity: TaskRelation is not api accessible').contains('Shared Activities')
    );
    Assert.isTrue(
      TimeDriveLog.causeOf('access', 'sObject type EmailMessage is not supported').contains('Enhanced Email')
    );
    Assert.isTrue(TimeDriveLog.causeOf('access', 'No such column IsPersonAccount').contains('person accounts'));
    Assert.isTrue(TimeDriveLog.causeOf('access', 'No such column \'Due__c\' on entity').contains('field'));
    Assert.isTrue(TimeDriveLog.causeOf('access', 'Insufficient privileges').contains('permission sets'));
    Assert.isTrue(TimeDriveLog.causeOf('busy', 'Apex CPU time limit exceeded').contains('Max Records'));
    Assert.isTrue(TimeDriveLog.causeOf('unknown', null).contains('support'));
    String hidden = TimeDriveLog.causeOf(TimeDriveLog.HIDDEN, 'Case');
    Assert.isTrue(hidden.startsWith('Left out for people who can\'t read Case.'), hidden);
  }

  @IsTest
  static void setupListsTheProblemsNewestFirstAndClearsThem() {
    System.runAs(TimeDriveTestData.setupAdmin()) {
      // Time Drive writes the log in system mode; admins can't create rows.
      List<Time_Drive_Log__c> rows = new List<Time_Drive_Log__c>{
        new Time_Drive_Log__c(
          Signature__c = 'a',
          Source_Key__c = 'Contact_Tasks',
          Source__c = 'Tasks',
          Kind__c = 'access',
          Message__c = 'Entity: TaskRelation is not api accessible',
          Count__c = 4,
          Last_Seen__c = Datetime.now().addHours(-2)
        ),
        new Time_Drive_Log__c(Signature__c = 'b', Kind__c = 'busy', Count__c = 1, Last_Seen__c = Datetime.now())
      };
      Database.insert(rows, AccessLevel.SYSTEM_MODE);
      List<TimeDriveSetupController.ProblemInfo> problems = TimeDriveSetupController.getProblems();
      Assert.areEqual(2, problems.size());
      Assert.areEqual('busy', problems[0].kind, 'newest first');
      Assert.areEqual(1, problems[0].count);
      Assert.areEqual('Tasks', problems[1].source);
      Assert.areEqual('Contact_Tasks', problems[1].sourceKey);
      Assert.areEqual(4, problems[1].count);
      Assert.isTrue(problems[1].cause.contains('Shared Activities'), problems[1].cause);

      TimeDriveSetupController.clearProblems();
      Assert.areEqual(0, [SELECT COUNT() FROM Time_Drive_Log__c]);
    }
  }
}
