/**
 * What one request ran, for the Diagnostics page in Time Drive Setup: each
 * query (its SOQL, binds, rows and time), how long each source took to count
 * or read and plot, and what was left out and why. Off unless the page turns
 * it on for its own request, so a timeline costs nothing for it.
 */
// Parameter lists follow the platform's entry points and the data the components exchange;
// splitting them up would only scatter what belongs together.
@SuppressWarnings('PMD.ExcessiveParameterList')
public with sharing class TimeDriveDiagnostics {
  public static Boolean active = false;
  private static Long startedAt;
  public static List<Query> queries = new List<Query>();
  public static List<Phase> phases = new List<Phase>();
  public static List<Note> notes = new List<Note>();

  /** One SOQL statement. */
  public class Query {
    @AuraEnabled
    public Integer seq;
    // The source (its DeveloperName), or what else asked.
    @AuraEnabled
    public String source;
    // rows, count, count check, probe, lookup, rights.
    @AuraEnabled
    public String kind;
    @AuraEnabled
    public String soql;
    @AuraEnabled
    public String binds;
    @AuraEnabled
    public Integer rows;
    // How long it ran, and when it started (ms into the request).
    @AuraEnabled
    public Integer ms;
    @AuraEnabled
    public Integer startedMs;
    @AuraEnabled
    public String error;
  }

  /** How long a source took to count, or to read and plot. */
  public class Phase {
    @AuraEnabled
    public String source;
    @AuraEnabled
    public String name;
    @AuraEnabled
    public Integer ms;
    @AuraEnabled
    public Integer startedMs;
    // Rows, groups or events it came to.
    @AuraEnabled
    public Integer items;
  }

  /** Something the request left out, or did differently, and why. */
  public class Note {
    @AuraEnabled
    public String source;
    @AuraEnabled
    public String what;
    @AuraEnabled
    public String reason;
  }

  /** Starts collecting diagnostics and clears what was collected. */
  public static void begin() {
    active = true;
    startedAt = System.currentTimeMillis();
    queries = new List<Query>();
    phases = new List<Phase>();
    notes = new List<Note>();
  }

  /** Stops collecting diagnostics. */
  public static void finish() {
    active = false;
  }

  /**
   * The time to hand back to query() or phase(); null when off.
   *
   * @return the start time in milliseconds, or null
   */
  public static Long clock() {
    return active ? System.currentTimeMillis() : null;
  }

  /**
   * Records a query with its binds, row count and time.
   *
   * @param source the source it was run for
   * @param kind the kind of query
   * @param soql the query text
   * @param binds the bind values by name
   * @param rows the number of rows returned
   * @param t0 the start time from clock()
   * @param error the error message, if it failed
   */
  public static void query(
    String source,
    String kind,
    String soql,
    Map<String, Object> binds,
    Integer rows,
    Long t0,
    String error
  ) {
    if (!active || t0 == null) {
      return;
    }
    Query q = new Query();
    q.seq = queries.size() + 1;
    q.source = source;
    q.kind = kind;
    q.soql = soql;
    q.binds = describe(binds);
    q.rows = rows;
    q.ms = Integer.valueOf(System.currentTimeMillis() - t0);
    q.startedMs = Integer.valueOf(t0 - startedAt);
    q.error = error;
    queries.add(q);
  }

  /**
   * Records how long a phase of a source took.
   *
   * @param source the source it was run for
   * @param name the phase's name
   * @param t0 the start time from clock()
   * @param items the number of items it came to
   */
  public static void phase(String source, String name, Long t0, Integer items) {
    if (!active || t0 == null) {
      return;
    }
    Phase p = new Phase();
    p.source = source;
    p.name = name;
    p.ms = Integer.valueOf(System.currentTimeMillis() - t0);
    p.startedMs = Integer.valueOf(t0 - startedAt);
    p.items = items;
    phases.add(p);
  }

  /**
   * Records something the request left out or did differently.
   *
   * @param source the source it concerns
   * @param what what was left out or changed
   * @param reason why
   */
  public static void note(String source, String what, String reason) {
    if (!active) {
      return;
    }
    Note n = new Note();
    n.source = source;
    n.what = what;
    n.reason = reason;
    notes.add(n);
  }

  // :name = value, lists cut to a few so the page stays readable.
  private static String describe(Map<String, Object> binds) {
    if (binds == null || binds.isEmpty()) {
      return '';
    }
    List<String> keys = new List<String>(binds.keySet());
    keys.sort();
    List<String> parts = new List<String>();
    for (String key : keys) {
      Object value = binds.get(key);
      String text;
      if (value instanceof List<Object>) {
        List<Object> items = (List<Object>) value;
        text = '[' + String.valueOf(items.size()) + ' values' + (items.isEmpty() ? '' : ': ' + String.valueOf(items[0]) + (items.size() > 1 ? ', …' : '')) + ']';
      } else {
        text = String.valueOf(value);
      }
      parts.add(':' + key + ' = ' + text);
    }
    return String.join(parts, '; ');
  }
}
