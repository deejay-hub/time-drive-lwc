/**
 * The SOQL a request ran, kept only while tests run, so they can check a
 * query's shape (its date ranges, its filter, the object it reads). Outside
 * tests nothing is kept, and nothing here reaches the client.
 */
public with sharing class TimeDriveQueries {
  /** One query as it ran: the source it was for, what it was, and its SOQL. */
  public class Ran {
    public String source;
    public String kind;
    public String soql;

    Ran(String source, String kind, String soql) {
      this.source = source;
      this.kind = kind;
      this.soql = soql;
    }
  }

  @TestVisible
  private static List<Ran> ran = new List<Ran>();

  /**
   * Keeps a query's SOQL, in tests only.
   * @param source the source it was for
   * @param kind what it was (rows, count, probe ...)
   * @param soql the query as it ran
   */
  public static void record(String source, String kind, String soql) {
    if (Test.isRunningTest()) {
      ran.add(new Ran(source, kind, soql));
    }
  }
}
