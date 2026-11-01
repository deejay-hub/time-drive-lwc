/**
 * What an Apex source extends. Time Drive asks it two things, and it answers
 * each its own way:
 *
 * - rows: the items on the days asked for (context.spans()). A source that
 *   counts is only asked for the days on screen, a few at a time.
 * - counts (optional): how many items each period of the timeline's window
 *   has, for the summary (the day list, overview and counts). A busy day then
 *   shows as one grouped row from its count, so a source that counts covers
 *   any amount of history. Leave it out, or return null, and the summary
 *   reads the rows of the whole window instead, up to the source's Max
 *   Records.
 *
 * Counts can be by any period up to the one asked for: daily totals when
 * asked by month are added up here, and a day's total when asked by hour
 * makes a busy day one grouped row. Counts outside the days asked for are
 * left out. context.countBy (a query) and context.counter (items one at a
 * time) build them.
 *
 * Methods added here later come with a default, so a class written today
 * keeps working.
 */
public abstract with sharing class TimeDriveApexSource implements TimeDriveRowProvider, TimeDriveCountProvider {
  /**
   * The items on the days asked for: context.spans(), checked with
   * context.wants(...) or context.dateCondition(...).
   *
   * @param context the request context
   * @return a row for each item
   */
  public abstract List<TimeDriveRow> rows(TimeDriveContext context);

  /**
   * How many items each period has, in the days asked for.
   *
   * @param context the request context
   * @param unit the period asked for: TimeDriveContext.UNIT_HOUR, _DAY, _WEEK or _MONTH
   * @return the counts, or null when this source doesn't count
   */
  public virtual List<TimeDriveContext.DayCount> counts(TimeDriveContext context, String unit) {
    return null;
  }

  /**
   * Time Drive's side of rows.
   *
   * @param context the request context
   * @return the rows
   */
  public List<TimeDriveRow> getRows(TimeDriveContext context) {
    return rows(context);
  }

  /**
   * Time Drive's side of counts: added up into the periods asked for, only
   * those in the days asked for.
   *
   * @param context the request context
   * @param unit the period to count by
   * @return the counts, or null when the source doesn't count
   */
  public List<TimeDriveContext.DayCount> countDays(TimeDriveContext context, String unit) {
    List<TimeDriveContext.DayCount> given = counts(context, unit);
    if (given == null) {
      return null;
    }
    List<TimeDriveController.TimeWindow> spans = context.spans();
    Map<String, TimeDriveContext.DayCount> byPeriod = new Map<String, TimeDriveContext.DayCount>();
    for (TimeDriveContext.DayCount c : given) {
      if (c?.dayKey == null || c.count == null || c.count <= 0) {
        continue;
      }
      Date first = TimeDriveContext.periodStart(Date.valueOf(c.dayKey), unit);
      if (!overlaps(first, TimeDriveContext.periodEnd(first, unit), spans)) {
        continue;
      }
      Integer hour = unit == TimeDriveContext.UNIT_HOUR ? c.hour : null;
      String key = String.valueOf(first) + '|' + hour;
      TimeDriveContext.DayCount same = byPeriod.get(key);
      if (same == null) {
        byPeriod.put(key, new TimeDriveContext.DayCount(String.valueOf(first), hour, c.count));
      } else {
        same.count += c.count;
      }
    }
    return byPeriod.values();
  }

  private static Boolean overlaps(Date first, Date last, List<TimeDriveController.TimeWindow> spans) {
    for (TimeDriveController.TimeWindow w : spans) {
      if ((w.since == null || last >= w.since.date()) && (w.until == null || first <= w.until.date())) {
        return true;
      }
    }
    return false;
  }
}
