/**
 * The generic Salesforce provider: rows of any standard or custom object from
 * a Time Drive Source record, no code needed. It queries Object Name,
 * linked to the page's record directly (Parent Field) or through a junction
 * (e.g. Opportunity via OpportunityContactRole), from the Date Field (date or
 * date/time) within the timeline's window, plus the optional Filter, in user
 * mode. TimeDrivePlotter turns the rows into events.
 *
 * It also counts: COUNT(Id) grouped by day, week or month costs one query
 * row per group, not per record, so the summary covers any amount of
 * history. (MIN, MAX and SUM cost a row per record aggregated, so they're
 * never used.)
 */
// The branching follows the platform's cases and the plot's rules; splitting it up would only scatter them.
// Size, parameter lists and field counts follow the platform's entry points, its cases and the data the components exchange;
// splitting them up would only scatter what belongs together.
@SuppressWarnings('PMD.CyclomaticComplexity, PMD.CognitiveComplexity, PMD.NcssCount')
public with sharing class TimeDriveSoqlProvider implements TimeDriveRowProvider, TimeDriveCountProvider {
  // Objects whose old records Salesforce archives (Activity archiving).
  public static final Set<String> ARCHIVED_OBJECTS = new Set<String>{ 'Task', 'Event' };

  // An aggregate query returns at most 2,000 groups.
  @TestVisible
  private static final Integer MAX_GROUPS = 2000;

  // Date fields known to refuse CALENDAR_MONTH() and the like.
  private static final Set<String> NO_DATE_FUNCTIONS = new Set<String>{ 'task.activitydate', 'event.activitydate' };
  private static Map<String, Boolean> acceptsFunctions = new Map<String, Boolean>();

  // Words a filter may use that aren't fields.
  private static final Set<String> FILTER_WORDS = new Set<String>{
    'and',
    'or',
    'not',
    'in',
    'like',
    'null',
    'true',
    'false',
    'includes',
    'excludes',
    'today',
    'yesterday',
    'tomorrow'
  };

  /**
   * Reads the source's records for the context's window.
   *
   * @param context the request context
   * @return the rows read
   */
  public List<TimeDriveRow> getRows(TimeDriveContext context) {
    Time_Drive_Source__mdt s = context.source;
    List<TimeDriveRow> events = new List<TimeDriveRow>();
    Query q = new Query(context);
    if (q.link == null) {
      return events;
    }

    Set<String> fields = new Set<String>{ 'Id', s.Date_Field__c };
    // Each way an item can be dated, and what decides which applies.
    fields.addAll(q.caseFields(q.datePrefix));
    fields.addAll(TimeDrivePlotter.tokens(s.Title__c));
    fields.addAll(TimeDrivePlotter.tokens(s.Subtitle__c));
    for (String extra : new List<String>{ s.Id_Field__c, s.Record_Id_Field__c }) {
      if (String.isNotBlank(extra)) {
        fields.add(extra);
      }
    }
    for (Time_Drive_Detail_Field__mdt d : context.detailFields()) {
      fields.add(d.Field__c);
      // The record a detail through a lookup names, for the card to link to.
      String link = TimeDrivePlotter.linkPathOf(s.Object_Name__c, d.Field__c);
      if (link != null) {
        fields.add(link);
      }
    }
    // Where the org has several currencies, each record's own, so its money shows in it.
    if (
      UserInfo.isMultiCurrencyOrganization() &&
      TimeDriveConfig.fieldDescribe(s.Object_Name__c, 'CurrencyIsoCode') != null
    ) {
      fields.add('CurrencyIsoCode');
    }
    // What the highlights read.
    fields.addAll(TimeDriveHighlights.fieldsOf(context.highlightRules()));
    // Events say whether they're all day (shown instead of a time).
    if (TimeDriveConfig.dateOwner(s) == 'Event') {
      fields.add(TimeDriveConfig.datePrefix(s) + 'IsAllDayEvent');
    }

    // A page (View all): newest first by date then Id, after the last one
    // shown, so a page never skips or repeats an item, however many share
    // a moment.
    Boolean paging = context.pageSize != null;
    // A source dated more than one way (open and completed tasks): one keyset
    // query for each way, merged by the moment each item plots at.
    if (paging && q.cases.size() > 1) {
      return pagedByCase(context, q, fields);
    }
    String conditions = q.conditions(context.spans());
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
    try {
      rows = Database.queryWithBinds(soql, q.binds, AccessLevel.USER_MODE);
      TimeDriveQueries.record(s.DeveloperName, paging ? 'rows (page)' : 'rows', soql);
    } catch (Exception e) {
      TimeDriveQueries.record(s.DeveloperName, 'rows', soql);
      context.fail(s.Label, e);
      return events;
    }
    for (SObject row : rows) {
      events.add(new TimeDriveRow(row));
    }
    q.plotDates(events, context);
    return events;
  }

  // One page of a source with several date cases: each case read by its own
  // keyset (its date, then Id, after the cursor), the reads merged newest
  // first (by the moment each plots at, then Id) and cut to the page.
  // The names are checked field paths; values are bound; user mode.
  @SuppressWarnings('PMD.ApexSOQLInjection')
  private List<TimeDriveRow> pagedByCase(TimeDriveContext context, Query q, Set<String> fields) {
    Time_Drive_Source__mdt s = context.source;
    List<RowOrder> merged = new List<RowOrder>();
    for (Integer k = 0; k < q.cases.size(); k++) {
      DateCase dc = q.cases[k];
      String ref = q.datePrefix + dc.field;
      String soql =
        'SELECT ' +
        String.join(unique(fields), ', ') +
        ' FROM ' +
        s.Object_Name__c +
        ' WHERE ' +
        q.conditions(context.spans(), false, k) +
        q.pageAfter(dc, ref, context) +
        ' ORDER BY ' +
        ref +
        ' DESC NULLS LAST, Id DESC LIMIT ' +
        context.pageSize +
        q.allRows();
      List<SObject> read;
      try {
        read = Database.queryWithBinds(soql, q.binds, AccessLevel.USER_MODE);
        TimeDriveQueries.record(s.DeveloperName, 'rows (page)', soql);
      } catch (Exception e) {
        TimeDriveQueries.record(s.DeveloperName, 'rows (page)', soql);
        context.fail(s.Label, e);
        return new List<TimeDriveRow>();
      }
      List<TimeDriveRow> rows = new List<TimeDriveRow>();
      for (SObject row : read) {
        rows.add(new TimeDriveRow(row));
      }
      q.plotDates(rows, context);
      for (TimeDriveRow row : rows) {
        merged.add(new RowOrder(row, TimeDrivePlotter.instant(row.get(PLOT_KEY)), String.valueOf(row.get('Id'))));
      }
    }
    merged.sort();
    List<TimeDriveRow> out = new List<TimeDriveRow>();
    for (Integer i = 0; i < merged.size() && i < context.pageSize; i++) {
      out.add(merged[i].row);
    }
    return out;
  }

  // Rows newest first by the moment they plot at, then by Id (the keyset's order).
  private class RowOrder implements Comparable {
    TimeDriveRow row;
    Datetime at;
    String id;

    RowOrder(TimeDriveRow row, Datetime at, String id) {
      this.row = row;
      this.at = at;
      this.id = id;
    }

    public Integer compareTo(Object other) {
      RowOrder that = (RowOrder) other;
      if (at != that.at) {
        return at == null ? 1 : (that.at == null ? -1 : (at > that.at ? -1 : 1));
      }
      return id == that.id ? 0 : (id > that.id ? -1 : 1);
    }
  }

  // The key each row's date is given to the plotter under, when the source
  // has several date cases (not a field name, so it can't clash with one).
  @TestVisible
  private static final String PLOT_KEY = 'timedrive:when';

  /**
   * One way a source's items are dated: a field, and when it applies (a flag,
   * and whether another field is set). Event has two: a timed event by its
   * start and an all-day one by its date (its start is midnight GMT, the day
   * before west of it). A task is always dated by its due date (ActivityDate),
   * open or done: when it was completed is only when it was saved so, which
   * for logged or imported history is the day it was entered.
   * Rows, counts and pages all use the same cases, so a count and its items
   * always fall on the same day.
   */
  @TestVisible
  private class DateCase {
    String field;
    Boolean dateOnly;
    Boolean nullable;
    String flag;
    Boolean flagIs;
    String present;
    Boolean presentIs;

    DateCase(String field, Boolean dateOnly, Boolean nullable) {
      this.field = field;
      this.dateOnly = dateOnly;
      this.nullable = nullable;
    }

    DateCase onlyWhen(String flag, Boolean flagIs) {
      this.flag = flag;
      this.flagIs = flagIs;
      return this;
    }

    DateCase onlyIfSet(String present, Boolean presentIs) {
      this.present = present;
      this.presentIs = presentIs;
      return this;
    }

    // The case's own condition, its fields under the prefix; blank when it
    // has none (a source dated one way, whose field can't be empty).
    String clause(String prefix) {
      List<String> parts = new List<String>();
      if (flag != null) {
        parts.add(prefix + flag + ' = ' + flagIs);
      }
      if (present != null) {
        parts.add(prefix + present + (presentIs ? ' != null' : ' = null'));
      }
      if (nullable) {
        parts.add(prefix + field + ' != null');
      }
      return String.join(parts, ' AND ');
    }

    // Whether a row read is this case's (the same test as the clause).
    Boolean matches(TimeDriveRow row, String prefix) {
      if (flag != null && (row.get(prefix + flag) == true) != flagIs) {
        return false;
      }
      return present == null || (row.get(prefix + present) != null) == presentIs;
    }
  }

  /**
   * How a source's items are dated, by its date field and the object it
   * belongs to: Event StartDateTime (or ActivityDateTime) has its own cases
   * (see DateCase); any other field is just itself.
   */
  @TestVisible
  private static List<DateCase> dateCases(String dateOwner, String ownField, Boolean dateOnly, Boolean nullable) {
    String f = ownField.toLowerCase();
    if (dateOwner == 'Event' && (f == 'startdatetime' || f == 'activitydatetime')) {
      return new List<DateCase>{
        new DateCase(ownField, false, nullable).onlyWhen('IsAllDayEvent', false),
        new DateCase('ActivityDate', true, true).onlyWhen('IsAllDayEvent', true)
      };
    }
    return new List<DateCase>{ new DateCase(ownField, dateOnly, nullable) };
  }

  /**
   * Whether any of these sources has an item in its context's window, for a
   * button that only needs yes or no. Sources on the same object are asked in
   * one query (their conditions joined with OR, LIMIT 1), each object in turn,
   * stopping at the first that has one: one query per object, except that a
   * source linked through a junction (Id IN (SELECT ...)) is asked on its own,
   * as SOQL allows no sub-select inside OR.
   *
   * @param contexts the sources' contexts
   * @return true when one has an item
   */
  // The names are checked field paths and object names; values are bound
  // (each source's binds renamed apart); the query runs in user mode.
  @SuppressWarnings('PMD.ApexSOQLInjection, PMD.OperationWithLimitsInLoop')
  public static Boolean anyOf(List<TimeDriveContext> contexts) {
    Map<String, List<String>> conditions = new Map<String, List<String>>();
    Map<String, String> objects = new Map<String, String>();
    Map<String, String> endings = new Map<String, String>();
    Map<String, Object> binds = new Map<String, Object>();
    Integer k = 0;
    for (TimeDriveContext context : contexts) {
      // One source that can't be asked (its junction isn't in this org, a
      // field gone) leaves the others to answer.
      Query q;
      String condition;
      try {
        q = new Query(context);
        if (q.link == null) {
          continue;
        }
        condition = q.conditions(context.spans());
      } catch (Exception e) {
        continue;
      }
      // Each source's binds under a name of its own (s0_parentId, s1_since0 ...).
      String prefix = 's' + k + '_';
      for (String key : q.binds.keySet()) {
        condition = condition.replaceAll(':' + key + '\\b', ':' + prefix + key);
        binds.put(prefix + key, q.binds.get(key));
      }
      String objectName = context.source.Object_Name__c;
      // A sub-select can't sit inside OR: that source is a query of its own.
      Boolean alone = condition.containsIgnoreCase('(SELECT ');
      String bucket = objectName + q.allRows() + (alone ? '#' + k : '');
      if (!conditions.containsKey(bucket)) {
        conditions.put(bucket, new List<String>());
        objects.put(bucket, objectName);
        endings.put(bucket, q.allRows());
      }
      conditions.get(bucket).add(condition);
      k++;
    }
    for (String bucket : conditions.keySet()) {
      String soql =
        'SELECT Id FROM ' +
        objects.get(bucket) +
        ' WHERE (' +
        String.join(conditions.get(bucket), ') OR (') +
        ') LIMIT 1' +
        endings.get(bucket);
      try {
        List<SObject> found = Database.queryWithBinds(soql, binds, AccessLevel.USER_MODE);
        TimeDriveQueries.record(objects.get(bucket), 'any', soql);
        if (!found.isEmpty()) {
          return true;
        }
      } catch (Exception e) {
        // One object that can't be asked doesn't stop the others.
        TimeDriveQueries.record(objects.get(bucket), 'any', soql);
      }
    }
    return false;
  }

  /**
   * Items per hour, day, week or month in the context's spans (see
   * countGrouped).
   *
   * @param context the request context
   * @param unit the period to count by
   * @return the count for each period that has records
   */
  public List<TimeDriveContext.DayCount> countDays(TimeDriveContext context, String unit) {
    Query q = new Query(context);
    if (q.link == null) {
      return new List<TimeDriveContext.DayCount>();
    }
    Time_Drive_Source__mdt s = context.source;
    // Dated more than one way: each case counted by its own date, added up.
    if (q.cases.size() > 1) {
      return countByCase(context, q, unit);
    }
    // Through the junction when the source has one (see Query.countsViaJunction).
    SourceCount counted = new SourceCount(q, null);
    counted.label = s.Label;
    counted.sourceName = s.DeveloperName;
    counted.objectName = q.countsViaJunction ? q.countObject : s.Object_Name__c;
    counted.dateRef = (q.countsViaJunction ? q.countPrefix : '') + s.Date_Field__c;
    counted.dateOnly = q.dateOnly;
    // Probed only when it matters: a date-only field counted by week or month.
    counted.groupsByPeriod =
      !q.dateOnly ||
      unit == TimeDriveContext.UNIT_DAY ||
      unit == TimeDriveContext.UNIT_HOUR ||
      acceptsDateFunctions(s.Object_Name__c, s.Date_Field__c, TimeDriveConfig.dateOwner(s));
    counted.binds = q.binds;
    counted.allRows = q.allRows();
    return countGrouped(counted, context.spans(), unit);
  }

  /**
   * What a grouped count needs: the object and date to count by, and how to
   * write the condition for some spans (binding their ends in binds).
   */
  public abstract class CountedQuery {
    public String label;
    public String sourceName;
    public String objectName;
    // The date as the query reaches it (a path through lookups is fine).
    public String dateRef;
    public Boolean dateOnly = false;
    // Whether the date can be grouped by CALENDAR_MONTH() and the like (a
    // Date/Time always can; Task and Event ActivityDate can't).
    public Boolean groupsByPeriod = true;
    public Map<String, Object> binds = new Map<String, Object>();
    public String allRows = '';

    /**
     * The WHERE condition for these spans.
     *
     * @param spans the spans to count in
     * @return the condition, without WHERE
     */
    public abstract String conditions(List<TimeDriveContext.Span> spans);
  }

  // A source's own query, through its junction when it counts through one;
  // one of its date cases only, when caseIndex is set.
  private class SourceCount extends CountedQuery {
    private Query q;
    private Integer caseIndex;

    SourceCount(Query q, Integer caseIndex) {
      this.q = q;
      this.caseIndex = caseIndex;
    }

    public override String conditions(List<TimeDriveContext.Span> spans) {
      return q.conditions(spans, q.countsViaJunction, caseIndex);
    }
  }

  // A source dated more than one way, counted case by case and added up by
  // period, so each item is counted on the day it plots on.
  private List<TimeDriveContext.DayCount> countByCase(TimeDriveContext context, Query q, String unit) {
    Time_Drive_Source__mdt s = context.source;
    String owner = TimeDriveConfig.dateOwner(s);
    Map<String, TimeDriveContext.DayCount> byPeriod = new Map<String, TimeDriveContext.DayCount>();
    for (Integer k = 0; k < q.cases.size(); k++) {
      DateCase dc = q.cases[k];
      SourceCount counted = new SourceCount(q, k);
      counted.label = s.Label;
      counted.sourceName = s.DeveloperName;
      counted.objectName = q.countsViaJunction ? q.countObject : s.Object_Name__c;
      counted.dateRef = (q.countsViaJunction ? q.countPrefix : '') + q.datePrefix + dc.field;
      counted.dateOnly = dc.dateOnly;
      counted.groupsByPeriod =
        !dc.dateOnly ||
        unit == TimeDriveContext.UNIT_DAY ||
        unit == TimeDriveContext.UNIT_HOUR ||
        acceptsDateFunctions(s.Object_Name__c, q.datePrefix + dc.field, owner);
      counted.binds = q.binds;
      counted.allRows = q.allRows();
      for (TimeDriveContext.DayCount c : countGrouped(counted, context.spans(), unit)) {
        String key = c.dayKey + '|' + c.hour;
        TimeDriveContext.DayCount same = byPeriod.get(key);
        if (same == null) {
          byPeriod.put(key, c);
        } else {
          same.count += c.count;
        }
      }
    }
    return byPeriod.values();
  }

  /**
   * Items per hour, day, week or month in some spans: COUNT(Id) grouped by
   * the period, in the user's time zone. Spans are batched so no query can
   * return more than 2,000 groups; before a batch that could use more query
   * rows than are left, a COUNT() (one row) checks how many records there
   * really are. Date-only fields have no hour, and one that takes no date
   * functions is grouped by the date itself and rolled up here.
   *
   * @param q the object, date and condition to count
   * @param spans the spans to count in
   * @param unit the period to count by
   * @return the count for each period that has records
   */
  // One count query for each batch of periods, on purpose: a grouped query returns at most 2,000 groups,
  // and each batch is checked against the query-row limit before it runs. The names in it are checked
  // field paths and object names; values are bound; the query runs in user mode.
  @SuppressWarnings('PMD.OperationWithLimitsInLoop, PMD.ApexSOQLInjection')
  public static List<TimeDriveContext.DayCount> countGrouped(
    CountedQuery q,
    List<TimeDriveContext.Span> spans,
    String unit
  ) {
    List<TimeDriveContext.DayCount> counts = new List<TimeDriveContext.DayCount>();
    String grain = q.dateOnly && unit == TimeDriveContext.UNIT_HOUR ? TimeDriveContext.UNIT_DAY : unit;
    String rollUp = q.dateOnly && grain != TimeDriveContext.UNIT_DAY && !q.groupsByPeriod ? grain : null;
    if (rollUp != null) {
      grain = TimeDriveContext.UNIT_DAY;
    }
    Map<String, TimeDriveContext.DayCount> rolled = new Map<String, TimeDriveContext.DayCount>();
    String local = q.dateOnly ? q.dateRef : 'convertTimezone(' + q.dateRef + ')';
    String day = q.dateOnly ? q.dateRef : 'DAY_ONLY(' + local + ')';
    List<String> groups = new List<String>();
    if (grain == TimeDriveContext.UNIT_WEEK) {
      groups.addAll(new List<String>{ 'CALENDAR_YEAR(' + local + ')', 'WEEK_IN_YEAR(' + local + ')' });
    } else if (grain == TimeDriveContext.UNIT_MONTH) {
      groups.addAll(new List<String>{ 'CALENDAR_YEAR(' + local + ')', 'CALENDAR_MONTH(' + local + ')' });
    } else {
      groups.add(day);
      if (grain == TimeDriveContext.UNIT_HOUR) {
        groups.add('HOUR_IN_DAY(' + local + ')');
      }
    }
    List<String> selected = new List<String>();
    for (Integer i = 0; i < groups.size(); i++) {
      selected.add(groups[i] + ' g' + i);
    }

    for (List<TimeDriveContext.Span> batch : batches(spans, daysPerBatch(grain))) {
      String conditions = q.conditions(batch);
      Integer most = 0;
      for (TimeDriveContext.Span span : batch) {
        most += TimeDriveContext.periods(span.since.date(), lastDay(span), grain);
      }
      if (Limits.getQueryRows() + most > Limits.getLimitQueryRows()) {
        String checkSoql = 'SELECT COUNT() FROM ' + q.objectName + ' WHERE ' + conditions + q.allRows;
        Integer total = Database.countQueryWithBinds(checkSoql, q.binds, AccessLevel.USER_MODE);
        TimeDriveQueries.record(q.sourceName, 'count check', checkSoql);
        most = Math.min(most, total);
        if (Limits.getQueryRows() + most > Limits.getLimitQueryRows()) {
          throw new CountException('Counting ' + q.label + ' would pass the query row limit.');
        }
      }
      String groupSoql =
        'SELECT ' +
        String.join(selected, ', ') +
        ', COUNT(Id) n FROM ' +
        q.objectName +
        ' WHERE ' +
        conditions +
        ' GROUP BY ' +
        String.join(groups, ', ') +
        q.allRows;
      List<SObject> grouped;
      try {
        grouped = Database.queryWithBinds(groupSoql, q.binds, AccessLevel.USER_MODE);
      } catch (Exception e) {
        TimeDriveQueries.record(q.sourceName, 'count', groupSoql);
        throw e;
      }
      TimeDriveQueries.record(q.sourceName, 'count', groupSoql);
      for (SObject row : grouped) {
        if (rollUp != null) {
          String key = TimeDriveContext.periodKey(firstDay(row, grain), rollUp);
          TimeDriveContext.DayCount c = rolled.get(key);
          if (c == null) {
            rolled.put(key, new TimeDriveContext.DayCount(key, null, (Integer) row.get('n')));
          } else {
            c.count += (Integer) row.get('n');
          }
          continue;
        }
        counts.add(
          new TimeDriveContext.DayCount(
            String.valueOf(firstDay(row, grain)),
            grain == TimeDriveContext.UNIT_HOUR ? (Integer) row.get('g1') : null,
            (Integer) row.get('n')
          )
        );
      }
    }
    counts.addAll(rolled.values());
    return counts;
  }

  /**
   * Whether a date (not date/time) field can be grouped by its week or month.
   * Task and Event ActivityDate can't; for any other, a query that matches
   * no row tries the function, and a refusal means it is counted by day as
   * before. The answer is kept for the rest of the request.
   *
   * @param objectName the object queried
   * @param dateField the date field (a path through lookups is fine)
   * @param dateOwner the object the date belongs to, or null when unknown
   * @return true when the field can be grouped by week or month
   */
  // The names go into the probe as written, so they must be plain identifiers or paths (checked below);
  // the query runs in user mode.
  @SuppressWarnings('PMD.ApexSOQLInjection')
  public static Boolean acceptsDateFunctions(String objectName, String dateField, String dateOwner) {
    String key = (objectName + '.' + dateField).toLowerCase();
    // A date reached through a junction is the date of the object it leads to.
    String ownKey = (dateOwner + '.' + dateField.substringAfterLast('.')).toLowerCase();
    if (NO_DATE_FUNCTIONS.contains(key) || NO_DATE_FUNCTIONS.contains(ownKey)) {
      return false;
    }
    Boolean known = acceptsFunctions.get(key);
    if (known != null) {
      return known;
    }
    if (
      !Pattern.matches('[A-Za-z0-9_.]+', String.valueOf(dateField)) ||
      !Pattern.matches('[A-Za-z0-9_]+', String.valueOf(objectName))
    ) {
      return false;
    }
    Boolean accepts;
    String probe =
      'SELECT CALENDAR_YEAR(' +
      dateField +
      ') y, COUNT(Id) n FROM ' +
      objectName +
      ' WHERE Id = null GROUP BY CALENDAR_YEAR(' +
      dateField +
      ')';
    try {
      // The shape the count uses, matching no row: only the function is tried.
      Database.query(probe, AccessLevel.USER_MODE);
      TimeDriveQueries.record(objectName, 'probe', probe);
      accepts = true;
    } catch (Exception e) {
      TimeDriveQueries.record(objectName, 'probe', probe);
      // Not accepted, or not readable: the day-by-day count as before.
      accepts = false;
    }
    acceptsFunctions.put(key, accepts);
    return accepts;
  }

  // A group's first day: the day itself, or its week's or month's first.
  private static Date firstDay(SObject row, String grain) {
    if (grain == TimeDriveContext.UNIT_WEEK) {
      return Date.newInstance((Integer) row.get('g0'), 1, 1).addDays(((Integer) row.get('g1') - 1) * 7);
    }
    if (grain == TimeDriveContext.UNIT_MONTH) {
      return Date.newInstance((Integer) row.get('g0'), (Integer) row.get('g1'), 1);
    }
    return (Date) row.get('g0');
  }

  // Days a batch can cover and still return at most 2,000 groups.
  private static Integer daysPerBatch(String grain) {
    if (grain == TimeDriveContext.UNIT_HOUR) {
      return MAX_GROUPS / 24;
    }
    if (grain == TimeDriveContext.UNIT_WEEK) {
      // Over 6 days a group, with each year's partial last week.
      return MAX_GROUPS * 6;
    }
    if (grain == TimeDriveContext.UNIT_MONTH) {
      return MAX_GROUPS * 28;
    }
    return MAX_GROUPS;
  }

  private static Date lastDay(TimeDriveContext.Span span) {
    return span.until == null ? Date.today() : span.until.date();
  }

  // Spans in batches of at most maxDays days, long spans split to fit.
  @TestVisible
  private static List<List<TimeDriveContext.Span>> batches(
    List<TimeDriveContext.Span> spans,
    Integer maxDays
  ) {
    List<List<TimeDriveContext.Span>> result = new List<List<TimeDriveContext.Span>>();
    List<TimeDriveContext.Span> batch = new List<TimeDriveContext.Span>();
    Integer used = 0;
    for (TimeDriveContext.Span span : spans) {
      Date first = span.since.date();
      Date last = span.until == null ? Date.today() : span.until.date();
      while (first <= last) {
        if (used >= maxDays) {
          result.add(batch);
          batch = new List<TimeDriveContext.Span>();
          used = 0;
        }
        Date stop = first.addDays(maxDays - used - 1);
        if (stop > last) {
          stop = last;
        }
        batch.add(
          new TimeDriveContext.Span(
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

  /**
   * A filter written against an object, rewritten to reach its fields across
   * a relationship (TaskSubtype = 'Call' as Task.TaskSubtype = 'Call'), for a
   * query on the junction. Only field names are changed: text in quotes,
   * numbers, dates, :binds, date literals (LAST_N_DAYS:30) and functions are
   * left as written. Null when that can't be done with certainty (a subquery,
   * or a word that is neither a field nor a known keyword), so the caller can
   * use the filter on the object itself.
   *
   * @param filter the source's filter
   * @param objectName API name of the source's object
   * @param prefix relationship path to prefix field names with
   * @return the filter, prefixed when it applies to a related object
   */
  @TestVisible
  private static String prefixed(String filter, String objectName, String prefix) {
    String out = '';
    Integer i = 0;
    Integer n = filter.length();
    while (i < n) {
      String c = filter.substring(i, i + 1);
      if (c == '\'') {
        Integer j = i + 1;
        while (j < n && filter.substring(j, j + 1) != '\'') {
          j += filter.substring(j, j + 1) == '\\' ? 2 : 1;
        }
        if (j >= n) {
          return null;
        }
        out += filter.substring(i, j + 1);
        i = j + 1;
      } else if (c == ':') {
        // A bind or a date literal's number: not a field.
        Integer j = i + 1;
        while (j < n && (filter.substring(j, j + 1).isAlphanumeric() || filter.substring(j, j + 1) == '_')) {
          j++;
        }
        out += filter.substring(i, j);
        i = j;
      } else if (c.isNumeric()) {
        // A number or a date or date/time (2026-01-31, 2026-01-31T10:00:00Z).
        Integer j = i;
        while (j < n && !' ,)'.contains(filter.substring(j, j + 1))) {
          j++;
        }
        out += filter.substring(i, j);
        i = j;
      } else if (c.isAlpha() || c == '_') {
        Integer j = i;
        while (j < n && (filter.substring(j, j + 1).isAlphanumeric() || '_.'.contains(filter.substring(j, j + 1)))) {
          j++;
        }
        String word = filter.substring(i, j);
        String lower = word.toLowerCase();
        Integer k = j;
        while (k < n && filter.substring(k, k + 1).isWhitespace()) {
          k++;
        }
        Boolean isFunction = k < n && filter.substring(k, k + 1) == '(';
        if (lower == 'select' || lower == 'from') {
          return null;
        } else if (FILTER_WORDS.contains(lower) || isFunction) {
          out += word;
        } else if (TimeDriveConfig.pathField(objectName, word) != null) {
          out += prefix + word;
        } else if (
          word == word.toUpperCase() &&
          (lower.startsWith('last_') ||
          lower.startsWith('this_') ||
          lower.startsWith('next_'))
        ) {
          out += word;
        } else {
          return null;
        }
        i = j;
      } else {
        out += c;
        i++;
      }
    }
    return out;
  }

  /**
   * Field names once each, whatever their case.
   *
   * @param fields the field names
   * @return the unique field names
   */
  public static List<String> unique(Set<String> fields) {
    Map<String, String> byKey = new Map<String, String>();
    for (String f : fields) {
      if (String.isNotBlank(f) && !byKey.containsKey(f.toLowerCase())) {
        byKey.put(f.toLowerCase(), f);
      }
    }
    return byKey.values();
  }

  /** Thrown when a count cannot be run. */
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
   *
   * @param s the source
   * @return true when the source reads through a junction object
   */
  @TestVisible
  private static Boolean useJunction(Time_Drive_Source__mdt s) {
    return String.isNotBlank(s.Junction_Object__c);
  }

  private class Query {
    Time_Drive_Source__mdt s;
    Boolean dateOnly;
    // Whether the object's own metadata lets the date be empty (Task and
    // Event ActivityDate can be); such a record can never be plotted.
    Boolean dateNullable = false;
    // Tasks and Events over a year old are archived, and only ALL ROWS
    // (with deleted ones left out) returns them.
    Boolean archivable = false;
    // The object the date belongs to, and the path to it with its dot: the
    // source's own object and blank, or a junction's (Task. on TaskRelation).
    String dateOwner;
    String datePrefix = '';
    // Whether the source's own records can be deleted (so ALL ROWS, which
    // returns them, needs them left out; a junction row is removed with it).
    Boolean ownDeletable = false;
    // Counting through a junction (TaskRelation) instead of probing it from
    // the object: the junction is filtered on its indexed lookup to the page's
    // record, and the object's fields are read across the relationship
    // (Task.ActivityDate). Several times faster for a record with many
    // relations; null when the source isn't a junction or its filter can't be
    // safely written across the relationship.
    String countObject;
    String countPrefix = '';
    String countLink;
    String countFilter;
    Boolean countDeletable = false;
    Boolean countsViaJunction = false;
    String link;
    Map<String, Object> binds = new Map<String, Object>();
    // How its items are dated (see DateCase): one case for most sources.
    List<DateCase> cases = new List<DateCase>();

    Query(TimeDriveContext context) {
      s = context.source;
      Schema.DescribeSObjectResult objectDescribe;
      try {
        objectDescribe = TimeDriveConfig.describeObject(s.Object_Name__c);
      } catch (Exception e) {
        context.warn(String.format(Label.Time_Drive_Server_No_Object, new List<String>{ s.Label, s.Object_Name__c }));
        return;
      }
      Schema.DescribeFieldResult dateDescribe = TimeDriveConfig.fieldDescribe(s.Object_Name__c, s.Date_Field__c);
      if (dateDescribe == null) {
        context.warn(
          String.format(
            Label.Time_Drive_Server_No_Field,
            new List<String>{ s.Label, s.Object_Name__c, s.Date_Field__c }
          )
        );
        return;
      }
      dateOnly = dateDescribe.getType() == Schema.DisplayType.DATE;
      dateNullable = dateDescribe.isNillable();
      dateOwner = TimeDriveConfig.dateOwner(s);
      datePrefix = TimeDriveConfig.datePrefix(s);
      archivable = ARCHIVED_OBJECTS.contains(dateOwner);
      ownDeletable = TimeDriveConfig.fieldMap(s.Object_Name__c).containsKey('isdeleted');
      // The date's own name on its object (Task.ActivityDate is ActivityDate on Task).
      String ownField = s.Date_Field__c.contains('.') ? s.Date_Field__c.substringAfterLast('.') : s.Date_Field__c;
      cases = dateCases(dateOwner, ownField, dateOnly, dateNullable);

      Schema.DescribeFieldResult linkField;
      if (!useJunction(s) && String.isNotBlank(s.Parent_Field__c)) {
        link = s.Parent_Field__c + ' = :parentId';
        linkField = TimeDriveConfig.fieldDescribe(s.Object_Name__c, s.Parent_Field__c);
      } else if (String.isNotBlank(s.Junction_Object__c)) {
        Schema.SObjectType junction = TimeDriveConfig.sObjectType(s.Junction_Object__c);
        linkField = junction == null
          ? null
          : TimeDriveConfig.fieldDescribe(TimeDriveConfig.describeType(junction).getName(), s.Junction_Parent_Field__c);
        link =
          'Id IN (SELECT ' +
          s.Junction_Record_Field__c +
          ' FROM ' +
          s.Junction_Object__c +
          ' WHERE ' +
          s.Junction_Parent_Field__c +
          ' = :parentId)';
      } else {
        context.warn(String.format(Label.Time_Drive_Server_No_Link, new List<String>{ s.Label }));
        return;
      }
      if (useJunction(s)) {
        prepareJunctionCount();
      }
      binds.put('parentId', context.parentIdFor(linkField));
      // The record an item opens is the date's: a Task for a TaskRelation.
      context.sourceObject = datePrefix == '' ? s.Object_Name__c : dateOwner;
      context.sourceLabel = 'Salesforce' + TimeDrivePlotter.SEPARATOR + objectDescribe.getLabel();
    }

    private void prepareJunctionCount() {
      if (
        datePrefix != '' ||
        String.isBlank(s.Junction_Parent_Field__c) ||
        String.isBlank(s.Junction_Record_Field__c)
      ) {
        return;
      }
      Schema.DescribeFieldResult record = TimeDriveConfig.fieldDescribe(
        s.Junction_Object__c,
        s.Junction_Record_Field__c
      );
      Schema.DescribeFieldResult parent = TimeDriveConfig.fieldDescribe(
        s.Junction_Object__c,
        s.Junction_Parent_Field__c
      );
      if (
        record == null ||
        parent == null ||
        String.isBlank(record.getRelationshipName()) ||
        record.getReferenceTo().size() != 1 ||
        TimeDriveConfig.describeType(record.getReferenceTo()[0]).getName() !=
        TimeDriveConfig.describeObject(s.Object_Name__c).getName()
      ) {
        return;
      }
      String prefix = record.getRelationshipName() + '.';
      String filter = String.isBlank(s.Filter__c) ? '' : prefixed(s.Filter__c, s.Object_Name__c, prefix);
      if (filter == null) {
        return;
      }
      countObject = s.Junction_Object__c;
      countPrefix = prefix;
      countLink = s.Junction_Parent_Field__c + ' = :parentId';
      countFilter = filter;
      countDeletable = TimeDriveConfig.fieldMap(s.Junction_Object__c).containsKey('isdeleted');
      countsViaJunction = true;
    }

    // Archived activities too, for Tasks and Events.
    String allRows() {
      return archivable ? ' ALL ROWS' : '';
    }

    // The link, the dates (any of the spans) and the Filter, binding each
    // span's ends as since0/until0, since1/until1 ...
    String conditions(List<TimeDriveContext.Span> spans) {
      return conditions(spans, false);
    }

    // The same written for the junction (see countsViaJunction) when asked.
    String conditions(List<TimeDriveContext.Span> spans, Boolean viaJunction) {
      return conditions(spans, viaJunction, null);
    }

    // Every date case's dates (any of them), or just one case's when only is set.
    String conditions(List<TimeDriveContext.Span> spans, Boolean viaJunction, Integer only) {
      String p = viaJunction ? countPrefix : '';
      String base = p + datePrefix;
      List<String> dates = new List<String>();
      for (Integer k = 0; k < cases.size(); k++) {
        if (only != null && only != k) {
          continue;
        }
        DateCase dc = cases[k];
        String dateRef = base + dc.field;
        String own = dc.clause(base);
        for (TimeDriveContext.Span span : spans) {
          Integer i = binds.size();
          String clause = dateRef + ' >= :since' + i;
          binds.put('since' + i, dc.dateOnly ? (Object) span.since.date() : span.since);
          if (span.until != null) {
            clause += ' AND ' + dateRef + ' <= :until' + i;
            binds.put('until' + i, dc.dateOnly ? (Object) span.until.date() : span.until);
          }
          dates.add('(' + (String.isBlank(own) ? '' : own + ' AND ') + clause + ')');
        }
      }
      String deleted = '';
      if (archivable) {
        // A junction row's own IsDeleted too: ALL ROWS would return it.
        deleted =
          ((viaJunction && countDeletable) || (!viaJunction && datePrefix != '' && ownDeletable)
            ? 'IsDeleted = false AND '
            : '') +
          p +
          datePrefix +
          'IsDeleted = false AND ';
      }
      // Only what has a date: each case leaves out the empty ones (see DateCase.clause).
      return deleted +
        (viaJunction ? countLink : link) +
        ' AND (' +
        String.join(dates, ' OR ') +
        ')' +
        (String.isBlank(s.Filter__c) ? '' : ' AND (' + (viaJunction ? countFilter : s.Filter__c) + ')');
    }

    // What the date cases read: their dates, and the flags that choose between them.
    Set<String> caseFields(String prefix) {
      Set<String> out = new Set<String>();
      for (DateCase dc : cases) {
        out.add(prefix + dc.field);
        if (dc.flag != null) {
          out.add(prefix + dc.flag);
        }
        if (dc.present != null) {
          out.add(prefix + dc.present);
        }
      }
      return out;
    }

    // Each row's date, from the case it falls in, for the plotter (a source
    // dated one way plots by its field, as it always has).
    void plotDates(List<TimeDriveRow> rows, TimeDriveContext context) {
      if (cases.size() < 2) {
        return;
      }
      context.plotDateKey = PLOT_KEY;
      for (TimeDriveRow row : rows) {
        for (DateCase dc : cases) {
          if (dc.matches(row, datePrefix)) {
            row.put(PLOT_KEY, row.get(datePrefix + dc.field));
            break;
          }
        }
      }
    }

    // After a View all page's cursor, for one date case: items that plot
    // before it, or at it with a smaller Id. A date-only case plots at midday
    // on its day, so its whole day is before, after or at the cursor.
    String pageAfter(DateCase dc, String ref, TimeDriveContext context) {
      if (context.pageAt == null) {
        return '';
      }
      binds.put('pageId', context.pageId);
      if (!dc.dateOnly) {
        binds.put('pageAt', context.pageAt);
        return ' AND (' + ref + ' < :pageAt OR (' + ref + ' = :pageAt AND Id < :pageId))';
      }
      Date day = context.pageAt.date();
      Datetime midday = Datetime.newInstance(day, Time.newInstance(12, 0, 0, 0));
      binds.put('pageDay', day);
      if (context.pageAt > midday) {
        return ' AND ' + ref + ' <= :pageDay';
      }
      if (context.pageAt < midday) {
        return ' AND ' + ref + ' < :pageDay';
      }
      return ' AND (' + ref + ' < :pageDay OR (' + ref + ' = :pageDay AND Id < :pageId))';
    }
  }
}
