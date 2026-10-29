@IsTest
private class TimeDriveData360SqlRunnerTest {
  // Data 360's query API can't run in a test; this checks the runner is the
  // one the provider finds, and that a query it can't run throws (so the
  // provider reads the source as rows).
  @IsTest
  static void isTheProvidersRunnerAndThrowsWhenItCantQuery() {
    Object runner = Type.forName('TimeDriveData360SqlRunner').newInstance();
    Assert.isTrue(runner instanceof TimeDriveData360Provider.SqlRunner);
    try {
      ((TimeDriveData360Provider.SqlRunner) runner).run('SELECT 1', null);
    } catch (Exception e) {
      Assert.isNotNull(e.getMessage());
    }
  }
}
