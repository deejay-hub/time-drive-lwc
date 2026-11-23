/**
 * Runs the Data 360 provider's count SQL through Data 360's query API
 * (ConnectApi.CdpQuery), every batch of the result. Only orgs with Data 360
 * can compile it, so it's in force-app-data360 and the provider finds it by
 * name; without it, Data 360 sources are read as rows.
 */
// Namespace accessible: the core package makes one by name (Type.forName) and runs SQL through SqlRunner.
@NamespaceAccessible
public with sharing class TimeDriveData360SqlRunner implements TimeDriveData360Provider.SqlRunner {
  /** Makes the runner; the core package does, by name. */
  @NamespaceAccessible
  public TimeDriveData360SqlRunner() {
    // Nothing to set up.
    return;
  }

  /**
   * Runs a Data 360 SQL query.
   *
   * @param sql the SQL to run
   * @param dataSpace the data space, blank for the default one
   * @return the result rows
   */
  @NamespaceAccessible
  public List<List<Object>> run(String sql, String dataSpace) {
    ConnectApi.CdpQueryOutputV2 output = firstBatch(sql, dataSpace);
    List<List<Object>> rows = new List<List<Object>>();
    add(rows, output);
    while (output.done != true && String.isNotBlank(output.nextBatchId)) {
      output = nextBatch(output.nextBatchId);
      add(rows, output);
    }
    return rows;
  }

  // Data 360's query API can't run in a test, so a test hands over the
  // batches it would return.
  @TestVisible
  private static List<ConnectApi.CdpQueryOutputV2> testBatches;

  private static ConnectApi.CdpQueryOutputV2 firstBatch(String sql, String dataSpace) {
    if (testBatches != null) {
      return testBatches.remove(0);
    }
    ConnectApi.CdpQueryInput input = new ConnectApi.CdpQueryInput();
    input.sql = sql;
    return String.isBlank(dataSpace)
      ? ConnectApi.CdpQuery.queryAnsiSqlV2(input)
      : ConnectApi.CdpQuery.queryAnsiSqlV2(input, dataSpace);
  }

  private static ConnectApi.CdpQueryOutputV2 nextBatch(String batchId) {
    if (testBatches != null) {
      return testBatches.remove(0);
    }
    return ConnectApi.CdpQuery.nextBatchAnsiSqlV2(batchId);
  }

  private static void add(List<List<Object>> rows, ConnectApi.CdpQueryOutputV2 output) {
    for (ConnectApi.CdpQueryV2Row row : output.data == null ? new List<ConnectApi.CdpQueryV2Row>() : output.data) {
      rows.add(row.rowData);
    }
  }
}
