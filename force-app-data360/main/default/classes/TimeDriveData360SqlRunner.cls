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
    ConnectApi.CdpQueryInput input = new ConnectApi.CdpQueryInput();
    input.sql = sql;
    ConnectApi.CdpQueryOutputV2 output = String.isBlank(dataSpace)
      ? ConnectApi.CdpQuery.queryAnsiSqlV2(input)
      : ConnectApi.CdpQuery.queryAnsiSqlV2(input, dataSpace);
    List<List<Object>> rows = new List<List<Object>>();
    add(rows, output);
    while (output.done != true && String.isNotBlank(output.nextBatchId)) {
      output = ConnectApi.CdpQuery.nextBatchAnsiSqlV2(output.nextBatchId);
      add(rows, output);
    }
    return rows;
  }

  private static void add(List<List<Object>> rows, ConnectApi.CdpQueryOutputV2 output) {
    for (ConnectApi.CdpQueryV2Row row : output.data == null ? new List<ConnectApi.CdpQueryV2Row>() : output.data) {
      rows.add(row.rowData);
    }
  }
}
