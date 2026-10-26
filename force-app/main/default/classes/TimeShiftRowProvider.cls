/**
 * The common contract for a timeline source: return rows, and the source's
 * Time Trail Source record plots them (date, title and subtitle
 * templates, type, icon, detail fields). The built-in Salesforce and
 * Data 360 sources implement it; so can any Apex class bringing records from
 * elsewhere (an external system, a calculation).
 *
 * Classes that need full control over each event can implement
 * TimeShiftProvider instead and build the events themselves.
 */
public interface TimeShiftRowProvider {
  List<TimeShiftRow> getRows(TimeShiftContext context);
}
