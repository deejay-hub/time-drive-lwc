/**
 * What a request did with each source: the SOQL it ran (with how many rows
 * came back), the sources left out for the user and why, and the ones that
 * failed. Kept while tests run (so they can check a query's shape) and while
 * a request is traced (the timeline's diagnostics drawer, see
 * TimeDriveController.getTimelineTrace); otherwise nothing is kept.
 *
 * Never record values: queries pass them as binds (:parentId), so their text
 * holds only objects, fields and the admin's filters.
 */
public with sharing class TimeDriveQueries {
  /** Kinds of line that aren't queries. */
  public static final String LEFT_OUT = 'left out';
  public static final String FAILED = 'failed';

  /** One line as it ran: the source it was for, what it was, and its SOQL. */
  public class Ran {
    @AuraEnabled
    public String source;
    @AuraEnabled
    public String kind;
    @AuraEnabled
    public String soql;
    // Rows returned (queries), or null when not known.
    @AuraEnabled
    public Integer rows;
    // How many times the same line happened in the request.
    @AuraEnabled
    public Integer times = 1;

    Ran(String source, String kind, String soql) {
      this.source = source;
      this.kind = kind;
      this.soql = soql;
    }
  }

  @TestVisible
  private static List<Ran> ran = new List<Ran>();
  private static Map<String, Ran> byKey = new Map<String, Ran>();

  /** Whether this request is traced (the diagnostics drawer asked). */
  public static Boolean tracing = false;

  /** The lines this request kept, in the order they first happened. */
  public static List<Ran> lines() {
    return ran;
  }

  /**
   * Keeps a query's SOQL, in tests or while tracing.
   * @param source the source it was for
   * @param kind what it was (rows, count, probe ...)
   * @param soql the query as it ran
   */
  public static void record(String source, String kind, String soql) {
    record(source, kind, soql, null);
  }

  /**
   * Keeps a line, in tests or while tracing: a query with the rows it
   * returned, or (kind LEFT_OUT or FAILED) why a source has nothing.
   * @param source the source it was for
   * @param kind what it was
   * @param soql the query, or the reason
   * @param rows the rows returned, or null
   */
  public static void record(String source, String kind, String soql, Integer rows) {
    if (!tracing && !Test.isRunningTest()) {
      return;
    }
    String key = source + '|' + kind + '|' + soql;
    Ran same = byKey.get(key);
    if (same != null) {
      same.times++;
      if (rows != null) {
        same.rows = (same.rows ?? 0) + rows;
      }
      return;
    }
    Ran line = new Ran(source, kind, soql);
    line.rows = rows;
    ran.add(line);
    byKey.put(key, line);
  }

  /** Starts afresh (tests clear it between steps). */
  @TestVisible
  private static void clear() {
    ran.clear();
    byKey.clear();
  }
}
