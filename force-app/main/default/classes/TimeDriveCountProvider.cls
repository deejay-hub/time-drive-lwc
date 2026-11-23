/**
 * A source that can count its items without reading them. The timeline's
 * summary (the day list, minimap and counts) asks for counts only, so it
 * covers any amount of history; full rows are read only for the days on
 * screen, and a busy day's counts become grouped rows instead.
 *
 * The generic SOQL provider (an aggregate query) and the Data 360 provider
 * (SQL run in Data 360) implement it, and so does TimeDriveApexSource, for
 * an Apex source's counts. A provider that can't count (returns null) or
 * whose count fails is read as rows (up to its Max Records).
 */
public interface TimeDriveCountProvider {
  /**
   * Items per period in the context's window (or its ranges, when set), in
   * the user's time zone. Unit is TimeDriveContext.UNIT_HOUR, _DAY,
   * _WEEK or _MONTH; each count's dayKey is its period's first day, and by
   * hour, its hour too (null for date-only fields).
   *
   * @param context the request context
   * @param unit the period to count by
   * @return the count for each period that has records
   */
  List<TimeDriveContext.DayCount> countDays(TimeDriveContext context, String unit);
}
