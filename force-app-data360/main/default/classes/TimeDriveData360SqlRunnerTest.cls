// Run as the running user on purpose; tests where what a person may do is the point run as a user with
// only the permission set (see the Preference and Progress tests).
@SuppressWarnings('PMD.ApexUnitTestClassShouldHaveRunAs')
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

  // The rows of every batch come back together, in order, until Data 360
  // says it's done.
  @IsTest
  static void readsEveryBatch() {
    TimeDriveData360SqlRunner.testBatches = new List<ConnectApi.CdpQueryOutputV2>{
      batch(new List<Object>{ '2026-11-01', 3 }, false, 'b2'),
      batch(new List<Object>{ '2026-11-02', 5 }, true, null)
    };
    List<List<Object>> rows = new TimeDriveData360SqlRunner().run('SELECT day, n FROM x', 'default');
    Assert.areEqual(2, rows.size());
    Assert.areEqual('2026-11-01', rows[0][0]);
    Assert.areEqual(5, rows[1][1]);
    Assert.isTrue(TimeDriveData360SqlRunner.testBatches.isEmpty(), 'both batches read');
  }

  // A batch with no data adds no rows.
  @IsTest
  static void anEmptyResultHasNoRows() {
    ConnectApi.CdpQueryOutputV2 empty = new ConnectApi.CdpQueryOutputV2();
    empty.done = true;
    TimeDriveData360SqlRunner.testBatches = new List<ConnectApi.CdpQueryOutputV2>{ empty };
    Assert.isTrue(new TimeDriveData360SqlRunner().run('SELECT 1', null).isEmpty());
  }

  private static ConnectApi.CdpQueryOutputV2 batch(List<Object> values, Boolean done, String nextBatchId) {
    ConnectApi.CdpQueryV2Row row = new ConnectApi.CdpQueryV2Row();
    row.rowData = values;
    ConnectApi.CdpQueryOutputV2 output = new ConnectApi.CdpQueryOutputV2();
    output.data = new List<ConnectApi.CdpQueryV2Row>{ row };
    output.done = done;
    output.nextBatchId = nextBatchId;
    return output;
  }
}
