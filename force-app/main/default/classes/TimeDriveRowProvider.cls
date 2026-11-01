/**
 * What every source's provider does: return rows, and the source's Time
 * Drive Source record plots them (date, title and subtitle templates, type,
 * icon, detail fields). The built-in Salesforce and Data 360 providers
 * implement it; an Apex source extends TimeDriveApexSource, which does.
 */
public interface TimeDriveRowProvider {
  /**
   * Builds the rows for one source.
   *
   * @param context the request context
   * @return the rows
   */
  List<TimeDriveRow> getRows(TimeDriveContext context);
}
