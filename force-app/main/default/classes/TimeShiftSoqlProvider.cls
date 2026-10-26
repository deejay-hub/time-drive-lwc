/**
 * The generic Salesforce provider: rows of any standard or custom object from
 * a Time Trail Source record, no code needed. It queries Object Name,
 * linked to the page's record directly (Parent Field) or through a junction
 * (e.g. Opportunity via OpportunityContactRole), from the Date Field (date or
 * date/time) within the timeline's window, plus the optional Filter, in user
 * mode. TimeShiftPlotter turns the rows into events.
 *
 * It also counts: COUNT(Id) grouped by day, week or month costs one query
 * row per group, not per record, so the summary covers any amount of
 * history. (MIN, MAX and SUM cost a row per record aggregated, so they're
 * never used.)
 */
public with sharing class TimeShiftSoqlProvider implements TimeShiftRowProvider, TimeShiftCountProvider {
  // Objects whose old records Salesforce archives (Activity archiving).
  public static final Set<String> ARCHIVED_OBJECTS = new Set<String>{ 'Task', 'Event' };

  // An aggregate query returns at most 2,000 groups.
  @TestVisible
  private static final Integer MAX_GROUPS = 2000;

  public List<TimeShiftRow> getRows(TimeShiftContext context) {
    Time_Shift_Source__mdt s = context.source;
    List<TimeShiftRow> events = new List<TimeShiftRow>();
    Query q = new Query(context);
    if (q.link == null) {
      return events;
    }

    Set<String> fields = new Set<String>{ 'Id', s.Date_Field__c };
    fields.addAll(TimeShiftPlotter.tokens(s.Title__c));
    fields.addAll(TimeShiftPlotter.tokens(s.Subtitle__c));
    for (String extra : new List<String>{ s.Id_Field__c, s.Record_Id_Field__c, context.detailsRecordFieldIfSet() }) {
      if (String.isNotBlank(extra)) {
        fields.add(extra);
      }
    }
    for (Time_Shift_Detail_Field__mdt d : context.detailFields()) {
      fields.add(d.Field__c);
    }
    if (context.columnPaths != null) {
      fields.addAll(context.columnPaths.values());
    }
    // What the highlights read.
    fields.addAll(TimeShiftHighlights.fieldsOf(context.highlightRules()));
    // Events say whether they're all day (shown instead of a time).
    if (s.Object_Name__c == 'Event') {
      fields.add('IsAllDayEvent');
    }

    String conditions = q.conditions(context.spans());
    // A page (View all): newest first by date then Id, after the last one
    // shown, so a page never skips or repeats an item, however many share
    // a moment.
    Boolean paging = context.pageSize != null;
    if (paging && context.pageAt != null) {
      q.binds.put('pageAt', q.dateOnly ? (Object) context.pageAt.date() : context.pageAt);
      q.binds.put('pageId', context.pageId);
      conditions += ' AND (' + s.Date_Field__c + ' < :pageAt OR (' + s.Date_Field__c + ' = :pageAt AND Id < :pageId))';
    }
    String soql =
      'SELECT ' +
      String.join(unique(fields), ', ') +
      ' FROM ' +
      s.Object_Name__c +
      ' WHERE ' +
      conditions +
      ' ORDER BY ' +
      s.Date_Field__c +
      ' DESC NULLS LAST' +
      (paging ? ', Id DESC' : '') +
      ' LIMIT ' +
      (paging ? context.pageSize : context.maxRecords()) +
      q.allRows();

    List<SObject> rows;
    Long startedAt = TimeShiftDiagnostics.clock();
    try {
      rows = Database.queryWithBinds(soql, q.binds, AccessLevel.USER_MODE);
      TimeShiftDiagnostics.query(s.DeveloperName, paging ? 'rows (page)' : 'rows', soql, q.binds, rows.size(), startedAt, null);
    } catch (Exception e) {
      TimeShiftDiagnostics.query(s.DeveloperName, 'rows', soql, q.binds, 0, startedAt, e.getMessage());
      context.fail(s.Label, e);
      return events;
    }
    for (SObject row : rows) {
      events.add(new TimeShiftRow(row));
    }
    return events;
  }

  /**
   * Items per hour, day, week or month in the context's spans. Spans are
   * batched so no query can return more than 2,000 groups; before a batch
   * that could use more query rows than are left, a COUNT() (one row) checks
   * how many records there really are.
   */
  public List<TimeShiftContext.DayCount> countDays(TimeShiftContext context, String unit) {
    List<TimeShiftContext.DayCount> counts = new List<TimeShiftContext.DayCount>();
    Query q = new Query(context);
    if (q.link == null) {
      return counts;
    }
    Time_Shift_Source__mdt s = context.source;
    // Date-only fields have no hour, and no time zone to convert from. Some
    // (Task and Event ActivityDate) take no date functions either, so they're
    // grouped by the date itself and rolled up into weeks or months here.
    String grain = q.dateOnly && unit == TimeShiftContext.UNIT_HOUR ? TimeShiftContext.UNIT_DAY : unit;
    // A date field that takes no date functions is counted by the day and
    // rolled up here; one that does (most do) is grouped by the week or month.
    String rollUp = q.dateOnly && grain != TimeShiftContext.UNIT_DAY && !acceptsDateFunctions(s) ? grain : null;
    if (rollUp != null) {
      grain = TimeShiftContext.UNIT_DAY;
    }
    Map<String, TimeShiftContext.DayCount> rolled = new Map<String, TimeShiftContext.DayCount>();
    String local = q.dateOnly ? s.Date_Field__c : 'convertTimezone(' + s.Date_Field__c + ')';
    String day = q.dateOnly ? s.Date_Field__c : 'DAY_ONLY(' + local + ')';
    List<String> groups = new List<String>();
    if (grain == TimeShiftContext.UNIT_WEEK) {
      groups.addAll(new List<String>{ 'CALENDAR_YEAR(' + local + ')', 'WEEK_IN_YEAR(' + local + ')' });
    } else if (grain == TimeShiftContext.UNIT_MONTH) {
      groups.addAll(new List<String>{ 'CALENDAR_YEAR(' + local + ')', 'CALENDAR_MONTH(' + local + ')' });
    } else {
      groups.add(day);
      if (grain == TimeShiftContext.UNIT_HOUR) {
        groups.add('HOUR_IN_DAY(' + local + ')');
      }
    }
    List<String> selected = new List<String>();
    for (Integer i = 0; i < groups.size(); i++) {
      selected.add(groups[i] + ' g' + i);
    }

    for (List<TimeShiftController.TimeWindow> batch : batches(context.spans(), daysPerBatch(grain))) {
      String conditions = q.conditions(batch);
      Integer most = 0;
      for (TimeShiftController.TimeWindow span : batch) {
        most += TimeShiftContext.periods(span.since.date(), lastDay(span), grain);
      }
      if (Limits.getQueryRows() + most > Limits.getLimitQueryRows()) {
        String checkSoql = 'SELECT COUNT() FROM ' + s.Object_Name__c + ' WHERE ' + conditions + q.allRows();
        Long checkStart = TimeShiftDiagnostics.clock();
        Integer total = Database.countQueryWithBinds(checkSoql, q.binds, AccessLevel.USER_MODE);
        TimeShiftDiagnostics.query(s.DeveloperName, 'count check', checkSoql, q.binds, 1, checkStart, null);
        most = Math.min(most, total);
        if (Limits.getQueryRows() + most > Limits.getLimitQueryRows()) {
          throw new CountException('Counting ' + s.Label + ' would pass the query row limit.');
        }
      }
      String groupSoql =
        'SELECT ' +
        String.join(selected, ', ') +
        ', COUNT(Id) n FROM ' +
        s.Object_Name__c +
        ' WHERE ' +
        conditions +
        ' GROUP BY ' +
        String.join(groups, ', ') +
        q.allRows();
      Long groupStart = TimeShiftDiagnostics.clock();
      List<SObject> grouped;
      try {
        grouped = Database.queryWithBinds(groupSoql, q.binds, AccessLevel.USER_MODE);
      } catch (Exception e) {
        TimeShiftDiagnostics.query(s.DeveloperName, 'count', groupSoql, q.binds, 0, groupStart, e.getMessage());
        throw e;
      }
      TimeShiftDiagnostics.query(s.DeveloperName, 'count', groupSoql, q.binds, grouped.size(), groupStart, null);
      for (SObject row : grouped) {
        if (rollUp != null) {
          String key = TimeShiftContext.periodKey(firstDay(row, grain), rollUp);
          TimeShiftContext.DayCount c = rolled.get(key);
          if (c == null) {
            rolled.put(key, new TimeShiftContext.DayCount(key, null, (Integer) row.get('n')));
          } else {
            c.count += (Integer) row.get('n');
          }
          continue;
        }
        counts.add(
          new TimeShiftContext.DayCount(
            String.valueOf(firstDay(row, grain)),
            grain == TimeShiftContext.UNIT_HOUR ? (Integer) row.get('g1') : null,
            (Integer) row.get('n')
          )
        );
      }
    }
    counts.addAll(rolled.values());
    return counts;
  }

  // Date fields known to refuse CALENDAR_MONTH() and the like.
  private static final Set<String> NO_DATE_FUNCTIONS = new Set<String>{ 'task.activitydate', 'event.activitydate' };
  private static Map<String, Boolean> acceptsFunctions = new Map<String, Boolean>();

  /**
   * Whether a date (not date/time) field can be grouped by its week or month.
   * Task and Event ActivityDate can't; for any other, a query that matches
   * no row tries the function, and a refusal means it is counted by day as
   * before. The answer is kept for the rest of the request.
   */
  private static Boolean acceptsDateFunctions(Time_Shift_Source__mdt s) {
    String key = (s.Object_Name__c + '.' + s.Date_Field__c).toLowerCase();
    if (NO_DATE_FUNCTIONS.contains(key)) {
      return false;
    }
    Boolean known = acceptsFunctions.get(key);
    if (known != null) {
      return known;
    }
    Boolean accepts;
    String probe =
      'SELECT CALENDAR_YEAR(' +
      s.Date_Field__c +
      ') y, COUNT(Id) n FROM ' +
      s.Object_Name__c +
      ' WHERE Id = null GROUP BY CALENDAR_YEAR(' +
      s.Date_Field__c +
      ')';
    Long probeStart = TimeShiftDiagnostics.clock();
    try {
      // The shape the count uses, matching no row: only the function is tried.
      Database.query(probe, AccessLevel.USER_MODE);
      TimeShiftDiagnostics.query(s.DeveloperName, 'probe', probe, null, 0, probeStart, null);
      accepts = true;
    } catch (Exception e) {
      TimeShiftDiagnostics.query(s.DeveloperName, 'probe', probe, null, 0, probeStart, e.getMessage());
      // Not accepted, or not readable: the day-by-day count as before.
      accepts = false;
    }
    acceptsFunctions.put(key, accepts);
    return accepts;
  }

  // A group's first day: the day itself, or its week's or month's first.
  private static Date firstDay(SObject row, String grain) {
    if (grain == TimeShiftContext.UNIT_WEEK) {
      return Date.newInstance((Integer) row.get('g0'), 1, 1).addDays(((Integer) row.get('g1') - 1) * 7);
    }
    if (grain == TimeShiftContext.UNIT_MONTH) {
      return Date.newInstance((Integer) row.get('g0'), (Integer) row.get('g1'), 1);
    }
    return (Date) row.get('g0');
  }

  // Days a batch can cover and still return at most 2,000 groups.
  private static Integer daysPerBatch(String grain) {
    if (grain == TimeShiftContext.UNIT_HOUR) {
      return MAX_GROUPS / 24;
    }
    if (grain == TimeShiftContext.UNIT_WEEK) {
      // Over 6 days a group, with each year's partial last week.
      return MAX_GROUPS * 6;
    }
    if (grain == TimeShiftContext.UNIT_MONTH) {
      return MAX_GROUPS * 28;
    }
    return MAX_GROUPS;
  }

  private static Date lastDay(TimeShiftController.TimeWindow span) {
    return span.until == null ? Date.today() : span.until.date();
  }

  // Spans in batches of at most maxDays days, long spans split to fit.
  @TestVisible
  private static List<List<TimeShiftController.TimeWindow>> batches(
    List<TimeShiftController.TimeWindow> spans,
    Integer maxDays
  ) {
    List<List<TimeShiftController.TimeWindow>> result = new List<List<TimeShiftController.TimeWindow>>();
    List<TimeShiftController.TimeWindow> batch = new List<TimeShiftController.TimeWindow>();
    Integer used = 0;
    for (TimeShiftController.TimeWindow span : spans) {
      Date first = span.since.date();
      Date last = span.until == null ? Date.today() : span.until.date();
      while (first <= last) {
        if (used >= maxDays) {
          result.add(batch);
          batch = new List<TimeShiftController.TimeWindow>();
          used = 0;
        }
        Date stop = first.addDays(maxDays - used - 1);
        if (stop > last) {
          stop = last;
        }
        batch.add(
          new TimeShiftController.TimeWindow(
            first == span.since.date() ? span.since : Datetime.newInstance(first, Time.newInstance(0, 0, 0, 0)),
            stop == last ? span.until : Datetime.newInstance(stop, Time.newInstance(23, 59, 59, 999))
          )
        );
        used += first.daysBetween(stop) + 1;
        first = stop.addDays(1);
      }
    }
    if (!batch.isEmpty()) {
      result.add(batch);
    }
    return result;
  }

  // Field names once each, whatever their case (SOQL rejects duplicates).
  public static List<String> unique(Set<String> fields) {
    Map<String, String> byKey = new Map<String, String>();
    for (String f : fields) {
      if (String.isNotBlank(f) && !byKey.containsKey(f.toLowerCase())) {
        byKey.put(f.toLowerCase(), f);
      }
    }
    return byKey.values();
  }

  public class CountException extends Exception {
  }

  /**
   * What reading and counting share: the source checked against the org,
   * the link to the page's record, the Filter, and the binds. Link stays
   * null, with a warning, when the source can't be queried.
   */
  /**
   * Whether a source links through its junction: when it names one. (A
   * source names one link; Guided setup chooses tasks' and events'.)
   */
  @TestVisible
  private static Boolean useJunction(Time_Shift_Source__mdt s) {
    return String.isNotBlank(s.Junction_Object__c);
  }

  private class Query {
    Time_Shift_Source__mdt s;
    Boolean dateOnly;
    // Whether the object's own metadata lets the date be empty (Task and
    // Event ActivityDate can be); such a record can never be plotted.
    Boolean dateNullable = false;
    // Tasks and Events over a year old are archived, and only ALL ROWS
    // (with deleted ones left out) returns them.
    Boolean archivable = false;
    String link;
    Map<String, Object> binds = new Map<String, Object>();

    Query(TimeShiftContext context) {
      s = context.source;
      Schema.DescribeSObjectResult objectDescribe;
      try {
        objectDescribe = TimeShiftConfig.describeObject(s.Object_Name__c);
      } catch (Exception e) {
        context.warn(String.format(Label.Time_Shift_Server_No_Object, new List<String>{ s.Label, s.Object_Name__c }));
        return;
      }
      Schema.DescribeFieldResult dateDescribe = TimeShiftConfig.fieldDescribe(s.Object_Name__c, s.Date_Field__c);
      if (dateDescribe == null) {
        context.warn(String.format(Label.Time_Shift_Server_No_Field, new List<String>{ s.Label, s.Object_Name__c, s.Date_Field__c }));
        return;
      }
      dateOnly = dateDescribe.getType() == Schema.DisplayType.DATE;
      dateNullable = dateDescribe.isNillable();
      archivable = ARCHIVED_OBJECTS.contains(objectDescribe.getName());

      Schema.DescribeFieldResult linkField;
      if (!useJunction(s) && String.isNotBlank(s.Parent_Field__c)) {
        link = s.Parent_Field__c + ' = :parentId';
        linkField = TimeShiftConfig.fieldDescribe(s.Object_Name__c, s.Parent_Field__c);
      } else if (String.isNotBlank(s.Junction_Object__c)) {
        Schema.SObjectType junction = TimeShiftConfig.sObjectType(s.Junction_Object__c);
        linkField = junction == null
          ? null
          : TimeShiftConfig.fieldDescribe(TimeShiftConfig.describeType(junction).getName(), s.Junction_Parent_Field__c);
        link =
          'Id IN (SELECT ' +
          s.Junction_Record_Field__c +
          ' FROM ' +
          s.Junction_Object__c +
          ' WHERE ' +
          s.Junction_Parent_Field__c +
          ' = :parentId)';
      } else {
        context.warn(String.format(Label.Time_Shift_Server_No_Link, new List<String>{ s.Label }));
        return;
      }
      binds.put('parentId', context.parentIdFor(linkField));
      context.sourceObject = s.Object_Name__c;
      context.sourceLabel = 'Salesforce' + TimeShiftPlotter.SEPARATOR + objectDescribe.getLabel();
    }

    // Archived activities too, for Tasks and Events.
    String allRows() {
      return archivable ? ' ALL ROWS' : '';
    }

    // The link, the dates (any of the spans) and the Filter, binding each
    // span's ends as since0/until0, since1/until1 ...
    String conditions(List<TimeShiftController.TimeWindow> spans) {
      List<String> dates = new List<String>();
      for (TimeShiftController.TimeWindow span : spans) {
        Integer i = binds.size();
        String clause = s.Date_Field__c + ' >= :since' + i;
        binds.put('since' + i, dateOnly ? (Object) span.since.date() : span.since);
        if (span.until != null) {
          clause += ' AND ' + s.Date_Field__c + ' <= :until' + i;
          binds.put('until' + i, dateOnly ? (Object) span.until.date() : span.until);
        }
        dates.add('(' + clause + ')');
      }
      return (archivable ? 'IsDeleted = false AND ' : '') +
        link +
        // Only what has a date: the metadata says which fields can be empty.
        (dateNullable ? ' AND ' + s.Date_Field__c + ' != null' : '') +
        ' AND (' +
        String.join(dates, ' OR ') +
        ')' +
        (String.isBlank(s.Filter__c) ? '' : ' AND (' + s.Filter__c + ')');
    }
  }
}
