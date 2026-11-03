/**
 * The Diagnostics page in Time Drive Setup: runs a record's timeline the way
 * the card asks for it, once as the first load and once as a scroll to the
 * next days, and reports what it did: every query with its SOQL, binds, rows
 * and time, how long each source took, what the user's permissions allow,
 * and what was left out and why. Admins only (Customize Application).
 */
// The branching follows the platform's cases and the plot's rules; splitting it up would only scatter them.
// Size, parameter lists and field counts follow the platform's entry points, its cases and the data the components exchange;
// splitting them up would only scatter what belongs together.
@SuppressWarnings('PMD.CyclomaticComplexity, PMD.CognitiveComplexity, PMD.ExcessiveParameterList, PMD.NcssCount')
public with sharing class TimeDriveDiagnosticController {
  @TestVisible
  private static Boolean testCanCustomize;

  /** A named fact: a permission found, or something about the record or user. */
  public class Fact {
    @AuraEnabled
    public String label;
    @AuraEnabled
    public String value;
    @AuraEnabled
    public String detail;
    // good, bad or null: whether the page colours it.
    @AuraEnabled
    public String tone;

    Fact(String label, String value, String detail, String tone) {
      this.label = label;
      this.value = value;
      this.detail = detail;
      this.tone = tone;
    }
  }

  /** One configured source, and what became of it in this run. */
  public class SourceRow {
    @AuraEnabled
    public String developerName;
    @AuraEnabled
    public String label;
    @AuraEnabled
    public String kind;
    @AuraEnabled
    public String objectName;
    // used, ignored.
    @AuraEnabled
    public String status;
    @AuraEnabled
    public String reason;
    @AuraEnabled
    public String access;
    @AuraEnabled
    public String missing;
    @AuraEnabled
    public Boolean counted = false;
    @AuraEnabled
    public Integer queries = 0;
    @AuraEnabled
    public Integer queryMs = 0;
    @AuraEnabled
    public Integer rows = 0;
    @AuraEnabled
    public Integer phaseMs = 0;
    @AuraEnabled
    public Decimal sequence;
  }

  /** Overall totals of a diagnostic run. */
  public class Totals {
    @AuraEnabled
    public Integer elapsedMs;
    @AuraEnabled
    public Integer cpuMs;
    @AuraEnabled
    public Integer queries;
    @AuraEnabled
    public Integer queryRows;
    @AuraEnabled
    public Integer heapKb;
    @AuraEnabled
    public Integer payloadKb;
    @AuraEnabled
    public Integer events;
    @AuraEnabled
    public Integer groupedRows;
    @AuraEnabled
    public Integer days;
    @AuraEnabled
    public String unit;
  }

  /** The result of a diagnostic run. */
  public class Report {
    @AuraEnabled
    public String mode;
    @AuraEnabled
    public String what;
    @AuraEnabled
    public Totals totals;
    @AuraEnabled
    public List<Fact> page = new List<Fact>();
    @AuraEnabled
    public List<Fact> permissions = new List<Fact>();
    @AuraEnabled
    public List<SourceRow> sources = new List<SourceRow>();
    @AuraEnabled
    public List<TimeDriveDiagnostics.Query> queries = new List<TimeDriveDiagnostics.Query>();
    @AuraEnabled
    public List<TimeDriveDiagnostics.Phase> phases = new List<TimeDriveDiagnostics.Phase>();
    @AuraEnabled
    public List<TimeDriveDiagnostics.Note> notes = new List<TimeDriveDiagnostics.Note>();
    // What the card handed the server (a scroll): the days, the sources the
    // summary found empty, the busy days it counted.
    @AuraEnabled
    public List<Fact> asked = new List<Fact>();
    @AuraEnabled
    public List<String> warnings = new List<String>();
    @AuraEnabled
    public List<String> problems = new List<String>();
  }

  /**
   * Runs the record's timeline. `mode` is "load" (the first request: the
   * summary and the days it opens on) or "scroll" (the next days, with what
   * the summary found, as the card asks for them). `layout` is "Across" or
   * "Down", as the card's, and History and Future are in years.
   *
   * @param recordId the record to run the timeline for
   * @param mode the load to run, first load or scroll
   * @param layout the timeline's layout
   * @param historyYears how many years of history to read
   * @param futureYears how many years ahead to read
   * @return the report
   */
  @AuraEnabled
  public static Report run(Id recordId, String mode, String layout, String historyYears, String futureYears) {
    if (!userCanCustomize()) {
      throw failure('Only admins (with Customize Application) can run diagnostics.');
    }
    if (recordId == null) {
      throw failure('Enter the Id of a Contact or Account.');
    }
    Boolean across = layout != 'Down';
    Boolean scroll = mode == 'scroll';
    Boolean configOnly = mode == 'config';
    Report report = new Report();
    report.mode = scroll ? 'scroll' : 'load';
    report.what = scroll
      ? 'The next ' + (across ? '12 columns' : '7 days') + ', as a scroll asks for them (getPageDays).'
      : 'The first request: the summary and the days it opens on (getTimeline).';

    // What the page and user are, before anything is measured.
    Schema.DescribeSObjectResult object1 = TimeDriveConfig.describeType(recordId.getSObjectType());
    String parentObject = object1.getName();
    Id personContact = TimeDriveController.personContactOf(recordId);
    if (personContact != null) {
      parentObject = TimeDriveController.PERSON_ACCOUNT;
    }
    describePage(report, recordId, object1, parentObject, historyYears, futureYears, across);
    Set<String> features = TimeDriveSetupController.orgFeatures();
    describePermissions(report, features, object1);

    List<Time_Drive_Source__mdt> used = TimeDriveConfig.sources(parentObject);
    Set<String> usedNames = new Set<String>();
    for (Time_Drive_Source__mdt s : used) {
      usedNames.add(s.DeveloperName);
    }
    if (configOnly) {
      // The setup only: the timing comes from the request the card makes.
      report.what = 'How the timeline is set up for this record.';
      report.sources = describeSources(parentObject, features, usedNames, null);
      return report;
    }

    // The measured call. A scroll first needs the summary (not measured), to
    // find the days and the hints the card would send.
    TimeDriveController.TimelineSummary summary;
    List<String> keys = new List<String>();
    List<String> empty = new List<String>();
    List<String> busy = new List<String>();
    List<TimeDriveController.BusyCount> counts = new List<TimeDriveController.BusyCount>();
    List<String> runs = new List<String>();
    if (scroll) {
      summary = TimeDriveController.getSummary(recordId, null, null, historyYears, futureYears);
      pickScrollDays(summary, across ? 12 : 7, keys, empty, busy, counts);
      runs = TimeDriveController.runsFor(summary, keys, busy);
      report.asked.add(new Fact('Days asked for', String.valueOf(keys.size()), String.join(keys, ', '), null));
      report.asked.add(new Fact('Sources the summary found empty', String.valueOf(empty.size()), String.join(empty, ', '), null));
      report.asked.add(new Fact('Busy days (over ' + TimeDriveController.GROUP_OVER + ')', String.valueOf(busy.size()), String.join(busy, ', '), null));
    }
    Integer queries0 = Limits.getQueries();
    Integer rows0 = Limits.getQueryRows();
    Integer cpu0 = Limits.getCpuTime();
    Integer heap0 = Limits.getHeapSize();
    TimeDriveDiagnostics.begin();
    Long started = System.currentTimeMillis();
    Integer events = 0;
    Integer grouped = 0;
    Integer payload = 0;
    try {
      if (scroll) {
        List<TimeDriveController.EngagementEvent> found = TimeDriveController.getPageDays(
          recordId,
          null,
          null,
          historyYears,
          futureYears,
          keys,
          busy,
          empty,
          busy.isEmpty() ? null : counts,
          runs
        );
        events = found.size();
        for (TimeDriveController.EngagementEvent e : found) {
          grouped += e.grouped ? 1 : 0;
        }
        payload = JSON.serialize(found).length();
      } else {
        TimeDriveController.TimelineLoad load = TimeDriveController.getTimeline(
          recordId,
          null,
          null,
          historyYears,
          futureYears,
          'Today',
          !across,
          across,
          across ? 12 : 7
        );
        summary = load.summary;
        events = load.events.size();
        for (TimeDriveController.EngagementEvent e : load.events) {
          grouped += e.grouped ? 1 : 0;
        }
        payload = JSON.serialize(load).length();
        report.asked.add(new Fact('Days read with the summary', String.valueOf(load.keys.size()), String.join(load.keys, ', '), null));
        if (load.keys.isEmpty() && !summary.days.isEmpty()) {
          TimeDriveDiagnostics.note(
            '(request)',
            'Days left for a request of their own',
            'The summary used more than ' + 45 + ' queries or 5,000 ms of CPU, so the days are asked for separately.'
          );
        }
      }
    } finally {
      TimeDriveDiagnostics.finish();
    }
    Totals totals = new Totals();
    totals.elapsedMs = Integer.valueOf(System.currentTimeMillis() - started);
    totals.cpuMs = Limits.getCpuTime() - cpu0;
    totals.queries = Limits.getQueries() - queries0;
    totals.queryRows = Limits.getQueryRows() - rows0;
    totals.heapKb = (Limits.getHeapSize() - heap0) / 1024;
    totals.payloadKb = payload / 1024;
    totals.events = events;
    totals.groupedRows = grouped;
    totals.days = summary == null ? 0 : summary.days.size();
    totals.unit = summary?.unit;
    report.totals = totals;
    report.queries = TimeDriveDiagnostics.queries;
    report.phases = TimeDriveDiagnostics.phases;
    report.notes = TimeDriveDiagnostics.notes;
    if (summary != null) {
      report.warnings = summary.warnings;
      for (TimeDriveController.Problem p : summary.problems) {
        report.problems.add(p.source + ': ' + p.kind);
      }
    }
    report.sources = describeSources(parentObject, features, usedNames, summary);
    return report;
  }

  // ---- the page and the user ------------------------------------------------

  // UserRecordAccess is a read-only view of the running user's own access.
  @SuppressWarnings('PMD.ApexCRUDViolation')
  private static void describePage(
    Report report,
    Id recordId,
    Schema.DescribeSObjectResult object1,
    String parentObject,
    String historyYears,
    String futureYears,
    Boolean across
  ) {
    String name = '';
    try {
      List<SObject> found = Database.query(
        'SELECT Name FROM ' + object1.getName() + ' WHERE Id = :recordId',
        AccessLevel.USER_MODE
      );
      if (!found.isEmpty()) {
        name = String.valueOf(found[0].get('Name'));
      }
    } catch (Exception e) {
      name = '(the user can\'t read its name)';
    }
    report.page.add(new Fact('Record', name, recordId + ' · ' + object1.getLabel(), null));
    report.page.add(new Fact('Sources used for', parentObject, parentObject == TimeDriveController.PERSON_ACCOUNT ? 'A person account has its own sources.' : 'Sources whose Parent Object is this.', null));
    report.page.add(new Fact('Layout', across ? 'Across (horizontal)' : 'Down (vertical)', across ? 'Opens on the 12 columns around Today.' : 'Opens on the first 7 days.', null));
    report.page.add(new Fact('History / Future', (historyYears ?? '1') + ' / ' + (futureYears ?? 'None') + ' years', null, null));
    try {
      for (UserRecordAccess a : [
        SELECT RecordId, HasReadAccess, HasEditAccess, HasDeleteAccess
        FROM UserRecordAccess
        WHERE UserId = :UserInfo.getUserId() AND RecordId = :recordId
      ]) {
        report.permissions.add(new Fact('This record: read / edit / delete', yes(a.HasReadAccess) + ' / ' + yes(a.HasEditAccess) + ' / ' + yes(a.HasDeleteAccess), 'UserRecordAccess', a.HasReadAccess ? 'good' : 'bad'));
      }
    } catch (Exception e) {
      report.permissions.add(new Fact('This record', 'unknown', e.getMessage(), 'bad'));
    }
  }

  // UserPermissionAccess is a read-only view of the running user's own permissions.
  @SuppressWarnings('PMD.ApexCRUDViolation')
  private static void describePermissions(Report report, Set<String> features, Schema.DescribeSObjectResult parent) {
    report.permissions.add(new Fact('User', UserInfo.getName(), UserInfo.getUserId() + ' · ' + UserInfo.getUserName(), null));
    report.permissions.add(new Fact('Time zone / locale', UserInfo.getTimeZone().getID() + ' / ' + UserInfo.getLocale(), null, null));
    try {
      for (UserPermissionAccess p : [
        SELECT PermissionsModifyAllData, PermissionsViewAllData, PermissionsCustomizeApplication
        FROM UserPermissionAccess
        LIMIT 1
      ]) {
        report.permissions.add(new Fact('Modify All Data', yes(p.PermissionsModifyAllData), 'Edit and Delete need only the object\'s permission.', null));
        report.permissions.add(new Fact('View All Data', yes(p.PermissionsViewAllData), null, null));
        report.permissions.add(new Fact('Customize Application', yes(p.PermissionsCustomizeApplication), 'Needed for Setup and this page.', null));
      }
    } catch (Exception e) {
      report.permissions.add(new Fact('User permissions', 'unknown', e.getMessage(), 'bad'));
    }
    for (String key : new List<String>{ 'SharedActivities', 'ContactsToMultipleAccounts', 'PersonAccounts', 'EnhancedEmail' }) {
      report.permissions.add(new Fact('Org feature: ' + key, yes(features.contains(key)), 'Sources that need it are used only where it is on.', null));
    }
    report.permissions.add(new Fact(parent.getLabel() + ' (the page\'s object)', objectAccess(parent), null, parent.isAccessible() ? 'good' : 'bad'));
  }

  // ---- the sources ----------------------------------------------------------

  private static List<SourceRow> describeSources(
    String parentObject,
    Set<String> features,
    Set<String> usedNames,
    TimeDriveController.TimelineSummary summary
  ) {
    Set<String> counted = new Set<String>(summary == null ? new List<String>() : summary.counted);
    Map<String, SourceRow> byName = new Map<String, SourceRow>();
    List<SourceRow> rows = new List<SourceRow>();
    for (Time_Drive_Source__mdt s : TimeDriveConfig.allSources().values()) {
      if (s.Parent_Object__c != parentObject) {
        continue;
      }
      SourceRow r = new SourceRow();
      r.developerName = s.DeveloperName;
      r.label = s.Label;
      r.kind = String.isBlank(s.Kind__c) ? 'Salesforce' : s.Kind__c;
      r.objectName = s.Object_Name__c;
      r.sequence = s.Sequence__c;
      if (usedNames.contains(s.DeveloperName)) {
        r.status = 'used';
        r.counted = counted.contains(s.DeveloperName);
        r.reason = r.counted ? 'Counted for the summary, then read as rows for the days drawn.' : 'Not counted: read as rows.';
        if (String.isNotBlank(s.Requires__c) && !features.contains(s.Requires__c)) {
          r.reason += ' It needs ' + s.Requires__c + ', which this org does not have: expect its query to fail.';
        }
      } else {
        r.status = 'ignored';
        r.reason = ignoredBecause(s, features);
      }
      if (r.kind == 'Salesforce') {
        checkAccess(s, r);
      }
      byName.put(s.DeveloperName, r);
      rows.add(r);
    }
    for (TimeDriveDiagnostics.Query q : TimeDriveDiagnostics.queries) {
      SourceRow r = byName.get(q.source);
      if (r != null) {
        r.queries++;
        r.queryMs += q.ms;
        r.rows += q.rows == null ? 0 : q.rows;
      }
    }
    for (TimeDriveDiagnostics.Phase p : TimeDriveDiagnostics.phases) {
      SourceRow r = byName.get(p.source);
      if (r != null) {
        r.phaseMs += p.ms;
      }
    }
    rows.sort(new BySequence());
    return rows;
  }

  private static String ignoredBecause(Time_Drive_Source__mdt s, Set<String> features) {
    if (s.Removed__c == true) {
      return 'Removed in Setup.';
    }
    String why = 'Inactive (Active is off).';
    if (String.isNotBlank(s.Variant_Group__c)) {
      why += ' One of the variants of "' + s.Variant_Group__c + '": Fit to your org picks the one that fits.';
    }
    if (s.Org_Fit__c == true && String.isNotBlank(s.Requires__c)) {
      why += ' Fit to your org turns it on where ' + s.Requires__c + ' is in use (this org ' + (features.contains(s.Requires__c) ? 'has' : 'does not have') + ' it).';
    }
    return why;
  }

  // The object and the fields the source names: what the user can read.
  private static void checkAccess(Time_Drive_Source__mdt s, SourceRow r) {
    Schema.SObjectType type = TimeDriveConfig.sObjectType(s.Object_Name__c);
    if (type == null) {
      r.access = 'No such object';
      r.missing = s.Object_Name__c;
      return;
    }
    Schema.DescribeSObjectResult d = type.getDescribe(SObjectDescribeOptions.DEFERRED);
    r.access = objectAccess(d);
    Map<String, Schema.SObjectField> fields = TimeDriveConfig.fieldMap(d.getName());
    Set<String> named = new Set<String>();
    named.add(s.Date_Field__c);
    named.add(s.Parent_Field__c);
    named.addAll(TimeDrivePlotter.tokens(s.Title__c));
    named.addAll(TimeDrivePlotter.tokens(s.Subtitle__c));
    for (Time_Drive_Detail_Field__mdt f : TimeDriveConfig.detailFields(s.DeveloperName)) {
      named.add(f.Field__c);
    }
    List<String> missing = new List<String>();
    for (String field : named) {
      // Paths through a relationship (Who.Name) are checked by the query itself.
      if (String.isBlank(field) || field.contains('.')) {
        continue;
      }
      Schema.SObjectField f = fields.get(field.toLowerCase());
      if (f == null) {
        missing.add(field + ' (no such field)');
      } else if (!f.getDescribe().isAccessible()) {
        missing.add(field + ' (no read access)');
      }
    }
    missing.sort();
    r.missing = missing.isEmpty() ? null : String.join(missing, ', ');
  }

  private static String objectAccess(Schema.DescribeSObjectResult d) {
    return 'read ' + yes(d.isAccessible()) + ' · create ' + yes(d.isCreateable()) + ' · edit ' + yes(d.isUpdateable()) + ' · delete ' + yes(d.isDeletable());
  }

  private class BySequence implements System.Comparator<SourceRow> {
    /**
     * Orders source rows by sequence, used ones first.
     *
     * @param a the first row
     * @param b the second row
     * @return a negative, zero or positive number
     */
    public Integer compare(SourceRow a, SourceRow b) {
      Decimal x = a.sequence == null ? 0 : a.sequence;
      Decimal y = b.sequence == null ? 0 : b.sequence;
      // Used ones first, then by sequence.
      Integer used = (a.status == 'used' ? 0 : 1) - (b.status == 'used' ? 0 : 1);
      if (used != 0) {
        return used;
      }
      return x == y ? 0 : (x < y ? -1 : 1);
    }
  }

  // ---- a scroll's days and hints ---------------------------------------------

  // The days after the first page, newest first, and the hints the card would
  // send for them: the sources the summary found empty, the busy days.
  private static void pickScrollDays(
    TimeDriveController.TimelineSummary summary,
    Integer size,
    List<String> keys,
    List<String> empty,
    List<String> busy,
    List<TimeDriveController.BusyCount> counts
  ) {
    List<String> all = new List<String>();
    for (TimeDriveController.DaySummary d : summary.days) {
      all.add(d.key);
    }
    all.sort();
    for (Integer i = all.size() - 1 - size; i >= 0 && keys.size() < size; i--) {
      keys.add(all[i]);
    }
    Set<String> wanted = new Set<String>(keys);
    Set<Integer> present = new Set<Integer>();
    for (TimeDriveController.DaySummary d : summary.days) {
      if (!wanted.contains(d.key)) {
        continue;
      }
      present.addAll(d.src);
      if (d.count > summary.groupOver && d.n != null) {
        busy.add(d.key);
        for (Integer j = 0; j < d.src.size(); j++) {
          TimeDriveController.BusyCount b = new TimeDriveController.BusyCount();
          b.key = d.key;
          b.source = summary.counted[d.src[j]];
          b.count = d.n[j];
          counts.add(b);
        }
      }
    }
    for (Integer i = 0; i < summary.counted.size(); i++) {
      if (!present.contains(i)) {
        empty.add(summary.counted[i]);
      }
    }
  }

  // ---- shared --------------------------------------------------------------

  private static String yes(Boolean value) {
    return value == true ? 'yes' : 'no';
  }

  // Only the running user's own permission set assignments are read.
  @SuppressWarnings('PMD.ApexCRUDViolation')
  private static Boolean userCanCustomize() {
    if (testCanCustomize != null) {
      return testCanCustomize;
    }
    return ![
      SELECT Id
      FROM PermissionSetAssignment
      WHERE AssigneeId = :UserInfo.getUserId() AND PermissionSet.PermissionsCustomizeApplication = TRUE
      LIMIT 1
    ].isEmpty();
  }

  private static AuraHandledException failure(String message) {
    AuraHandledException e = new AuraHandledException(message);
    e.setMessage(message);
    return e;
  }
}
