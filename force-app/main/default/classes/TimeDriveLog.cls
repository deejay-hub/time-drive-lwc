/**
 * Time Drive's problem log, for admins (the Setup dashboard's Problems) and
 * for whoever supports the org: what failed, how often, when it was last
 * seen, and its likely cause.
 *
 * Problems are noted as they're caught (note) and written once, at the end
 * of the request (flush), after every source has been read. One row per
 * distinct problem: a repeat adds to its count and moves its Last Seen.
 * Rows not seen for 30 days are removed as new ones are written.
 *
 * Only requests that may write call flush (getTimeline, getPageDays,
 * getGroupPage); cacheable ones can't, so what they note is dropped, and the
 * next full load logs it. Logging never breaks the timeline: any failure of
 * its own is swallowed.
 */
// Without sharing on purpose: the log is the org's, written for every user
// (who has no access to it) and read only by admins with View All. Every DML
// and query here is system mode for the same reason.
@SuppressWarnings('PMD.ApexCRUDViolation')
public without sharing class TimeDriveLog {
  // Rows not seen for this many days are removed.
  @TestVisible
  private static final Integer KEEP_DAYS = 30;
  // The most a message keeps (the field's length).
  private static final Integer MESSAGE_CHARS = 2000;

  // What this request has noted, by signature.
  private static Map<String, Entry> pending = new Map<String, Entry>();

  /** The record page the request is for, kept with what it notes. */
  public static Id recordId;

  private class Entry {
    String sourceKey;
    String source;
    String kind;
    String errorType;
    String message;
    String location;
    Integer count = 0;
  }

  /**
   * Notes a problem, to be written when the request ends.
   *
   * @param sourceKey the source's API name, or null for a whole request
   * @param source the source's name as people see it, or null
   * @param kind access, busy or unknown
   * @param e what was caught
   */
  public static void note(String sourceKey, String source, String kind, Exception e) {
    try {
      String errorType = e == null ? null : e.getTypeName();
      String location = e == null ? null : firstLine(e.getStackTraceString());
      String signature = String.join(
          new List<String>{ sourceKey ?? '', kind ?? '', errorType ?? '', location ?? '' },
          '|'
        )
        .left(255);
      Entry entry = pending.get(signature);
      if (entry == null) {
        entry = new Entry();
        entry.sourceKey = sourceKey;
        entry.source = source;
        entry.kind = kind;
        entry.errorType = errorType;
        entry.location = location;
        pending.put(signature, entry);
      }
      entry.message = e == null ? null : String.valueOf(e.getMessage()).left(MESSAGE_CHARS);
      entry.count++;
    } catch (Exception ignored) {
      // Noting must never break the request it's in.
      return;
    }
  }

  /** Writes what the request noted, then removes rows not seen for KEEP_DAYS days. */
  public static void flush() {
    if (pending.isEmpty()) {
      return;
    }
    Map<String, Entry> toWrite = pending;
    pending = new Map<String, Entry>();
    try {
      Map<String, Time_Drive_Log__c> seen = new Map<String, Time_Drive_Log__c>();
      for (Time_Drive_Log__c row : [
        SELECT Id, Signature__c, Count__c
        FROM Time_Drive_Log__c
        WHERE Signature__c IN :toWrite.keySet()
        WITH SYSTEM_MODE
        ORDER BY Last_Seen__c DESC
        LIMIT 200
      ]) {
        if (!seen.containsKey(row.Signature__c)) {
          seen.put(row.Signature__c, row);
        }
      }
      List<Time_Drive_Log__c> rows = new List<Time_Drive_Log__c>();
      for (String signature : toWrite.keySet()) {
        Entry entry = toWrite.get(signature);
        Time_Drive_Log__c row = seen.get(signature);
        Decimal before = row?.Count__c ?? 0;
        if (row == null) {
          row = new Time_Drive_Log__c(
            Signature__c = signature,
            Source_Key__c = entry.sourceKey?.left(80),
            Source__c = entry.source?.left(255),
            Kind__c = entry.kind?.left(40),
            Error_Type__c = entry.errorType?.left(255),
            Location__c = entry.location?.left(255)
          );
        }
        row.Count__c = before + entry.count;
        row.Last_Seen__c = Datetime.now();
        row.Message__c = entry.message;
        row.Record_Id__c = recordId == null ? null : String.valueOf(recordId);
        rows.add(row);
      }
      Database.upsert(rows, false, AccessLevel.SYSTEM_MODE);
      Datetime cutoff = Datetime.now().addDays(-KEEP_DAYS);
      List<Time_Drive_Log__c> stale = [
        SELECT Id
        FROM Time_Drive_Log__c
        WHERE Last_Seen__c < :cutoff
        WITH SYSTEM_MODE
        LIMIT 200
      ];
      if (!stale.isEmpty()) {
        Database.delete(stale, false, AccessLevel.SYSTEM_MODE);
      }
    } catch (Exception ignored) {
      // The log is a help, never a reason for the timeline to fail.
      return;
    }
  }

  /**
   * The likely cause of a problem and what to do, in plain words, from its
   * kind and message.
   *
   * @param kind access, busy or unknown
   * @param message the exception's message
   * @return the cause, for the Setup dashboard
   */
  public static String causeOf(String kind, String message) {
    String text = (message ?? '').toLowerCase();
    if (text.contains('taskrelation') || text.contains('eventrelation')) {
      return 'Needs Shared Activities, which this org doesn\'t use. Switch this source off, or use its variant without "every contact".';
    }
    if (text.contains('emailmessage')) {
      return 'Needs Enhanced Email, which this org doesn\'t use. Switch this source off.';
    }
    if (text.contains('personaccount') || text.contains('ispersonaccount')) {
      return 'Needs person accounts, which this org doesn\'t use. Switch this source off.';
    }
    if (text.contains('no such column') || text.contains('invalid field')) {
      return 'A field this source uses doesn\'t exist, or the user can\'t see it. Check the source\'s fields, and the user\'s field access.';
    }
    if (kind == 'access') {
      return 'The user can\'t read an object or field this source uses. Check their permission sets.';
    }
    if (kind == 'busy') {
      return 'Too much to read, or the server was busy. A shorter history or a lower Max Records helps if it keeps happening.';
    }
    return 'Something unexpected went wrong. If it keeps happening, send the details to Time Drive support.';
  }

  private static String firstLine(String trace) {
    if (String.isBlank(trace)) {
      return null;
    }
    return trace.split('\n')[0].trim();
  }
}
