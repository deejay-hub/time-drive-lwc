/**
 * What a provider gets: the record the timeline is on, how far back to
 * look, its own Time Drive Source record, the events earlier sources
 * returned (a provider can build on them), and somewhere to
 * report what it couldn't read.
 */
// The branching follows the platform's cases and the plot's rules; splitting it up would only scatter them.
// Size, parameter lists and field counts follow the platform's entry points, its cases and the data the components exchange;
// splitting them up would only scatter what belongs together.
@SuppressWarnings(
  'PMD.CyclomaticComplexity, PMD.CognitiveComplexity, PMD.ExcessiveParameterList, PMD.ExcessivePublicCount, PMD.TooManyFields'
)
// Global: customers' own Apex sources (TimeDriveApexSource) are handed one. Only what the
// Config Guide documents for them is global; everything else stays the package's own.
global with sharing class TimeDriveContext {
  public static final Integer DEFAULT_MAX_RECORDS = 1000;
  public static final String KIND_SALESFORCE = 'Salesforce';
  public static final String KIND_DATA_360 = 'Data 360';
  public static final String KIND_APEX = 'Apex';
  // What a count is per: an hour of a day, a day, a week (from 1 January:
  // the 1st-7th, 8th-14th ... as SOQL's WEEK_IN_YEAR) or a calendar month.
  global static final String UNIT_HOUR = 'hour';
  global static final String UNIT_DAY = 'day';
  global static final String UNIT_WEEK = 'week';
  global static final String UNIT_MONTH = 'month';
  // A field a source names, as a field path and nothing else.
  private static final Pattern FIELD_PATH = Pattern.compile('[A-Za-z][A-Za-z0-9_]*(\\.[A-Za-z][A-Za-z0-9_]*)*');

  global Id recordId;
  public String parentObject;
  global Datetime since;
  // The end of the timeline's window, or null for up to now. Events after it
  // are dropped anyway; queries can skip them.
  global Datetime until;
  // Just these spans of the window, when set: the days on screen.
  public List<Span> ranges;
  public Time_Drive_Source__mdt source;
  // A page of the source's items (View all), when set: at most pageSize,
  // newest first, after pageAt (and, at that same moment, before pageId).
  public Integer pageSize;
  public Datetime pageAt;
  // The key each row's date is under when the provider chose it (a Task's due
  // date or completion, an all-day event's date); blank for the date field.
  public String plotDateKey;
  public Id pageId;
  /** The earlier sources' events, loaded on the first read. */
  public List<TimeDriveController.EngagementEvent> priorEvents {
    get {
      if (priorLoader != null) {
        PriorEvents loader = priorLoader;
        priorLoader = null;
        priorEvents = loader.load();
      }
      return priorEvents;
    }
    set;
  }
  public PriorEvents priorLoader;
  public List<String> warnings;
  // Sources that couldn't be read, by name and kind of failure (shared by
  // every source's context; never the raw exception, which can carry query text).
  public List<TimeDriveController.Problem> problems = new List<TimeDriveController.Problem>();
  // A person account's own Contact: links to Contact (Task.WhoId,
  // Case.ContactId) match it, links to Account match the account.
  public Id personContactId;

  // Where the events say they come from (the expanded event's footer).
  // Defaults to Object Name and the record's label; providers may set them.
  public String sourceObject;
  public String sourceLabel;

  // A draft source's detail fields (the setup wizard's preview), in place
  // of the saved ones.
  public List<Time_Drive_Detail_Field__mdt> draftDetailFields;

  // A draft source's highlights (the setup wizard's preview), in place of the
  // saved ones.
  public List<Time_Drive_Highlight__mdt> draftHighlights;
  private List<TimeDriveHighlights.Rule> highlightRulesCache;

  /**
   * The Contact a Contact-based source reads for: the page's, or a person account's own.
   * @return the Contact Id
   */
  public Id contactId() {
    return personContactId != null ? personContactId : recordId;
  }

  /**
   * The Id a link field matches: a person account's Contact when the field points at Contact, else
   * the page's record.
   * @param link the lookup field being matched, or null
   * @return the Id to match
   */
  public Id parentIdFor(Schema.DescribeFieldResult link) {
    // A file is linked to the record it was added on: a person account's are on the account.
    if (link?.getName() == 'LinkedEntityId') {
      return recordId;
    }
    if (personContactId != null && link != null && link.getReferenceTo().contains(Contact.SObjectType)) {
      return personContactId;
    }
    return recordId;
  }

  /**
   * Builds the context for one source.
   * @param recordId the record the timeline is on
   * @param parentObject the API name of that record's object
   * @param since the start of the window, or null
   * @param source the source's Time Drive Source record
   * @param priorEvents events earlier sources returned, or null
   * @param warnings the shared list to add warnings to, or null
   */
  public TimeDriveContext(
    Id recordId,
    String parentObject,
    Datetime since,
    Time_Drive_Source__mdt source,
    List<TimeDriveController.EngagementEvent> priorEvents,
    List<String> warnings
  ) {
    this.recordId = recordId;
    this.parentObject = parentObject;
    // A source can look back less far than the timeline does (read only
    // when set: a source queried without the field has none).
    Decimal months = source != null && source.isSet(Time_Drive_Source__mdt.History_Months__c)
      ? source.History_Months__c
      : null;
    Datetime own = months == null
      ? null
      : Datetime.newInstance(Date.today().addMonths(-months.intValue()), Time.newInstance(0, 0, 0, 0));
    this.since = since != null && own != null && own > since ? own : since;
    this.source = source;
    this.priorEvents = priorEvents == null ? new List<TimeDriveController.EngagementEvent>() : priorEvents;
    this.warnings = warnings == null ? new List<String>() : warnings;
    this.sourceObject = source?.Object_Name__c;
    // Where an opened item says it's from: Salesforce and Data 360 sources set
    // theirs (with the object's label); an Apex source shows its own name.
    this.sourceLabel = source != null &&
      kind() == KIND_APEX
      ? KIND_APEX + TimeDrivePlotter.SEPARATOR + source.Label
      : source?.Label;
  }

  /**
   * A context for testing an Apex source: the record, and the window the
   * timeline asks for. It has no source record, so the source's caps and
   * fields are the defaults.
   * @param recordId the record the timeline is on
   * @param since the start of the window, or null
   * @param until the end of the window, or null for up to now
   */
  global TimeDriveContext(Id recordId, Datetime since, Datetime until) {
    this(
      recordId,
      recordId == null ? null : String.valueOf(recordId.getSObjectType()),
      since,
      new Time_Drive_Source__mdt(Kind__c = KIND_APEX),
      null,
      null
    );
    this.until = until;
  }

  /**
   * The windows a provider should read: its ranges, or the whole window.
   * @return the time windows to read
   */
  global List<Span> spans() {
    if (ranges != null) {
      // Clipped to the source's own history, when it has one.
      List<Span> out = new List<Span>();
      for (Span r : ranges) {
        if (since == null || r.until == null || r.until >= since) {
          out.add(r.since == null || since == null || r.since >= since ? r : new Span(since, r.until));
        }
      }
      return out;
    }
    return new List<Span>{ new Span(since, until) };
  }

  /**
   * Salesforce, Data 360 or Apex. Records from before Kind default from their provider class.
   * @return the source's kind
   */
  public String kind() {
    if (String.isNotBlank(source?.Kind__c)) {
      return source.Kind__c;
    }
    return String.isBlank(source?.Provider_Class__c) ? KIND_SALESFORCE : KIND_APEX;
  }

  /**
   * The source's record cap, newest first.
   * @return the most records to read
   */
  global Integer maxRecords() {
    return source?.Max_Records__c == null ? DEFAULT_MAX_RECORDS : source.Max_Records__c.intValue();
  }

  /**
   * The source's date field, defaulting for Data 360 sources.
   * @return the date field API name, or null
   */
  public String dateField() {
    if (String.isNotBlank(source?.Date_Field__c)) {
      return source.Date_Field__c;
    }
    return kind() == KIND_DATA_360 ? 'ssot__EngagementDateTm__c' : null;
  }

  /**
   * The source's Id field, defaulting for Data 360 sources.
   * @return the Id field API name
   */
  public String idField() {
    if (String.isNotBlank(source?.Id_Field__c)) {
      return source.Id_Field__c;
    }
    return kind() == KIND_DATA_360 ? 'ssot__Id__c' : 'Id';
  }

  /**
   * The field holding the Id of the record an event stands for.
   * @return the field API name, or null
   */
  public String recordIdField() {
    if (String.isNotBlank(source?.Record_Id_Field__c)) {
      return source.Record_Id_Field__c;
    }
    // A file's link stands for its document, which is what a click opens.
    if (kind() == KIND_SALESFORCE && 'ContentDocumentLink'.equalsIgnoreCase(source?.Object_Name__c)) {
      return 'ContentDocumentId';
    }
    return kind() == KIND_SALESFORCE ? 'Id' : null;
  }

  /**
   * The detail fields to show for the source: the draft ones when set, else the saved ones.
   * @return the detail field records
   */
  public List<Time_Drive_Detail_Field__mdt> detailFields() {
    if (draftDetailFields != null) {
      return draftDetailFields;
    }
    return TimeDriveConfig.detailFields(source?.DeveloperName);
  }

  // ---- for Apex sources ------------------------------------------------------

  // An Apex source's keys holding the records its details name (Plot.links), by detail key.
  public Map<String, String> detailLinks = new Map<String, String>();

  /**
   * How an Apex source's rows are plotted, said in getRows before anything
   * else (Setup asks an Apex source for none of it): the row key holding each
   * item's date, then its title, subtitle and the record a click opens, as
   * context.plotBy('EarnedAt').title('Earned {Points} points').subtitle('{Reason}').
   * A key is a map key, or a field path for record rows. Without a date,
   * nothing is plotted.
   * @param dateKey the key holding each item's Date or Datetime
   * @return the plot, to add its title, subtitle and click to
   */
  global Plot plotBy(String dateKey) {
    source = source == null ? new Time_Drive_Source__mdt() : source.clone(true);
    if (String.isBlank(source.Date_Field__c)) {
      source.Date_Field__c = dateKey;
    }
    return new Plot(this);
  }

  /** The rest of how an Apex source's rows are plotted (see plotBy). */
  global class Plot {
    private TimeDriveContext context;

    private Plot(TimeDriveContext context) {
      this.context = context;
    }

    /**
     * The title, with {Key} filled from each row, as '{Product2.Name}'.
     * @param template the title
     * @return this plot
     */
    global Plot title(String template) {
      if (String.isBlank(context.source.Title__c)) {
        context.source.Title__c = template;
      }
      return this;
    }

    /**
     * The line under the title, with {Key} filled from each row.
     * @param template the subtitle
     * @return this plot
     */
    global Plot subtitle(String template) {
      if (String.isBlank(context.source.Subtitle__c)) {
        context.source.Subtitle__c = template;
      }
      return this;
    }

    /**
     * The key holding the Salesforce record a click opens (left out: the
     * title isn't a link).
     * @param recordIdKey the key holding a Salesforce Id
     * @return this plot
     */
    global Plot opens(String recordIdKey) {
      if (String.isBlank(context.source.Record_Id_Field__c)) {
        context.source.Record_Id_Field__c = recordIdKey;
      }
      return this;
    }

    /**
     * The key holding the Salesforce record a detail names, so the opened
     * item links it: links('Account', 'AccountId') for a row whose Account
     * key is a name. Record rows don't need it for a path through a lookup
     * (Product2.Name links to Product2.Id by itself, as fieldsToQuery asks
     * for it).
     * @param detailKey the detail field's key, as chosen in Setup
     * @param recordIdKey the key holding that record's Salesforce Id
     * @return this plot
     */
    global Plot links(String detailKey, String recordIdKey) {
      if (String.isNotBlank(detailKey) && String.isNotBlank(recordIdKey)) {
        context.detailLinks.put(detailKey.toLowerCase(), recordIdKey);
      }
      return this;
    }
  }

  /**
   * For record rows: the days the timeline asks for as a SOQL condition on a
   * date field, its bounds bound (never written in): ' AND (...)', or blank
   * for the whole history. A Date field is compared with days, a Date/Time
   * with instants, as the field itself says.
   * @param objectType the object queried
   * @param field the date field (a path through lookups is fine)
   * @param binds the query's binds, which the bounds are added to
   * @return the condition to append after WHERE ..., or blank
   */
  global String dateCondition(Schema.SObjectType objectType, String field, Map<String, Object> binds) {
    Schema.DescribeFieldResult d = TimeDriveConfig.fieldDescribe(String.valueOf(objectType), field);
    Boolean byDay = d?.getType() == Schema.DisplayType.DATE;
    List<String> out = new List<String>();
    List<Span> windows = spans();
    for (Integer i = 0; i < windows.size(); i++) {
      List<String> bounds = new List<String>();
      if (windows[i].since != null) {
        binds.put('since' + i, byDay ? (Object) windows[i].since.date() : windows[i].since);
        bounds.add(field + ' >= :since' + i);
      }
      if (windows[i].until != null) {
        binds.put('until' + i, byDay ? (Object) windows[i].until.date() : windows[i].until);
        bounds.add(field + ' <= :until' + i);
      }
      if (bounds.isEmpty()) {
        return '';
      }
      out.add('(' + String.join(bounds, ' AND ') + ')');
    }
    return out.isEmpty() ? '' : ' AND (' + String.join(out, ' OR ') + ')';
  }

  /**
   * For an Apex source's counts, from a query written once: the object, its
   * date field and the condition that finds this record's items (its values
   * bound in binds). Time Drive groups them by the period asked for, in the
   * user's time zone and the days asked for, in user mode, within the
   * platform's limits: countBy(OpportunityLineItem.SObjectType,
   * 'Opportunity.CloseDate', 'Opportunity.AccountId = :accountId', binds, unit).
   * @param objectType the object to count
   * @param field its date field (a path through lookups is fine)
   * @param condition the condition after WHERE, without the dates, or blank
   * @param binds the condition's values by name, or null
   * @param unit the period asked for (counts' unit)
   * @return the counts
   */
  global List<DayCount> countBy(
    Schema.SObjectType objectType,
    String field,
    String condition,
    Map<String, Object> binds,
    String unit
  ) {
    String objectName = String.valueOf(objectType);
    Schema.DescribeFieldResult d = field == null || !FIELD_PATH.matcher(field).matches()
      ? null
      : TimeDriveConfig.fieldDescribe(objectName, field);
    if (d == null) {
      throw new IllegalArgumentException(objectName + ' has no date field ' + field + ' to count by.');
    }
    RecordCount q = new RecordCount(condition, field);
    q.label = source?.Label;
    q.sourceName = source?.DeveloperName;
    q.objectName = objectName;
    q.dateRef = field;
    q.dateOnly = d.getType() == Schema.DisplayType.DATE;
    q.groupsByPeriod =
      !q.dateOnly ||
      unit == UNIT_DAY ||
      unit == UNIT_HOUR ||
      TimeDriveSoqlProvider.acceptsDateFunctions(objectName, field, null);
    q.binds = binds == null ? new Map<String, Object>() : new Map<String, Object>(binds);
    return TimeDriveSoqlProvider.countGrouped(q, spans(), unit);
  }

  // An Apex source's own condition, and the days asked for on its date.
  private class RecordCount extends TimeDriveSoqlProvider.CountedQuery {
    private String condition;
    private String field;
    private Integer bound = 0;

    RecordCount(String condition, String field) {
      this.condition = condition;
      this.field = field;
    }

    public override String conditions(List<Span> spans) {
      List<String> dates = new List<String>();
      for (Span span : spans) {
        String clause = field + ' >= :timeDriveSince' + bound;
        binds.put('timeDriveSince' + bound, dateOnly ? (Object) span.since.date() : span.since);
        if (span.until != null) {
          clause += ' AND ' + field + ' <= :timeDriveUntil' + bound;
          binds.put('timeDriveUntil' + bound, dateOnly ? (Object) span.until.date() : span.until);
        }
        bound++;
        dates.add('(' + clause + ')');
      }
      return (String.isBlank(condition) ? '' : '(' + condition + ') AND ') + '(' + String.join(dates, ' OR ') + ')';
    }
  }

  /**
   * For an Apex source's counts from data elsewhere: add each item's moment,
   * or each day's total, and return counter.counts(). Only the days asked
   * for are kept.
   * @param unit the period asked for (counts' unit)
   * @return an empty counter
   */
  global Counter counter(String unit) {
    return new Counter(this, unit);
  }

  /** Items added up by day (and hour, when counted by hour), in the user's time zone. */
  global class Counter {
    private TimeDriveContext context;
    private String unit;
    private Map<String, DayCount> byDay = new Map<String, DayCount>();

    private Counter(TimeDriveContext context, String unit) {
      this.context = context;
      this.unit = unit;
    }

    /**
     * Counts one item at this moment.
     * @param at the item's date and time
     * @return this counter
     */
    global Counter add(Datetime at) {
      if (context.wants(at)) {
        tally(at.date(), unit == UNIT_HOUR ? at.hour() : null, 1);
      }
      return this;
    }

    /**
     * Counts a day's items, as a service's daily totals give them.
     * @param day the day
     * @param count how many items it has
     * @return this counter
     */
    global Counter add(Date day, Integer count) {
      if (count != null && count > 0 && context.wants(day)) {
        tally(day, null, count);
      }
      return this;
    }

    /**
     * The counts so far.
     * @return a count for each day (or hour) with items
     */
    global List<DayCount> counts() {
      return byDay.values();
    }

    private void tally(Date day, Integer hour, Integer count) {
      String key = String.valueOf(day) + '|' + hour;
      DayCount same = byDay.get(key);
      if (same == null) {
        byDay.put(key, new DayCount(String.valueOf(day), hour, count));
      } else {
        same.count += count;
      }
    }
  }

  /**
   * For data from elsewhere: whether the timeline asks for an item at this
   * moment (a page asks for a few days at a time, the summary for the whole
   * window). Return only the items it wants.
   * @param at the item's date and time
   * @return true when it falls in a span asked for
   */
  global Boolean wants(Datetime at) {
    if (at == null) {
      return false;
    }
    for (Span w : spans()) {
      if ((w.since == null || at >= w.since) && (w.until == null || at <= w.until)) {
        return true;
      }
    }
    return false;
  }

  /**
   * For data from elsewhere: whether the timeline asks for anything on this day.
   * @param day the item's day
   * @return true when the day overlaps a span asked for
   */
  global Boolean wants(Date day) {
    if (day == null) {
      return false;
    }
    Datetime starts = Datetime.newInstance(day, Time.newInstance(0, 0, 0, 0));
    Datetime ends = Datetime.newInstance(day, Time.newInstance(23, 59, 59, 999));
    for (Span w : spans()) {
      if ((w.since == null || ends >= w.since) && (w.until == null || starts <= w.until)) {
        return true;
      }
    }
    return false;
  }

  /**
   * For record rows: the fields to SELECT, those given then those the
   * source's title, subtitle, detail and highlight fields name, each once and
   * only if it's a field path (so a source can't put anything else into the
   * query). Where the source names its object (Object Name), fields the user
   * can't read are left out: they show blank, rather than the query failing.
   * @param always the fields every row needs (its Id, the date), always kept
   * @return the fields to SELECT
   */
  global List<String> fieldsToQuery(List<String> always) {
    return fieldsFor(source?.Object_Name__c, always);
  }

  /**
   * As fieldsToQuery(always), for the object the query reads: fields the user
   * can't read are left out, so they show blank rather than the query failing.
   * @param objectType the object the source queries
   * @param always the fields every row needs (its Id, the date), always kept
   * @return the fields to SELECT
   */
  global List<String> fieldsToQuery(Schema.SObjectType objectType, List<String> always) {
    return fieldsFor(objectType == null ? source?.Object_Name__c : objectType.getDescribe().getName(), always);
  }

  private List<String> fieldsFor(String objectName, List<String> always) {
    List<String> shown = new List<String>();
    shown.addAll(TimeDrivePlotter.tokens(source?.Title__c));
    shown.addAll(TimeDrivePlotter.tokens(source?.Subtitle__c));
    for (Time_Drive_Detail_Field__mdt d : detailFields()) {
      shown.add(d.Field__c);
      // The record a detail ending at a related record's name names (Product2.Name: Product2.Id), for its link.
      shown.add(TimeDrivePlotter.linkPathOf(objectName, d.Field__c));
    }
    // What the highlight reads (a checkbox, as a field path).
    for (TimeDriveHighlights.Rule r : highlightRules()) {
      shown.add(r.field);
    }
    List<String> wanted = new List<String>(always ?? new List<String>());
    for (String name : shown) {
      if (String.isNotBlank(name) && TimeDriveConfig.canRead(objectName, name)) {
        wanted.add(name);
      }
    }
    Set<String> seen = new Set<String>();
    List<String> out = new List<String>();
    for (String name : wanted) {
      if (String.isNotBlank(name) && FIELD_PATH.matcher(name).matches() && seen.add(name.toLowerCase())) {
        out.add(name);
      }
    }
    return out;
  }

  /**
   * The highlight rules in use (Salesforce sources whose fields the user can read).
   * @return the rules, possibly empty
   */
  private List<Time_Drive_Highlight__mdt> storedHighlights() {
    return draftHighlights != null ? draftHighlights : TimeDriveConfig.highlights(source?.DeveloperName);
  }

  public List<TimeDriveHighlights.Rule> highlightRules() {
    if (highlightRulesCache == null) {
      highlightRulesCache = new List<TimeDriveHighlights.Rule>();
      if (source != null && kind() == KIND_SALESFORCE) {
        highlightRulesCache = TimeDriveHighlights.rulesFor(source.Object_Name__c, storedHighlights());
      } else if (source != null && kind() == KIND_APEX) {
        highlightRulesCache = TimeDriveHighlights.rulesForRows(storedHighlights());
      }
    }
    return highlightRulesCache;
  }

  /**
   * Records a source that couldn't be read: its name and the kind of failure for the user, never
   * the exception's message (it can carry query text and field names).
   * @param what the source's name
   * @param e the exception raised
   */
  public void fail(String what, Exception e) {
    for (TimeDriveController.Problem p : problems) {
      if (p.source == what) {
        return;
      }
    }
    problems.add(new TimeDriveController.Problem(what, TimeDriveController.kindOf(e)));
  }

  /**
   * Adds a warning, once, however many sources run into it.
   * @param message the warning text
   */
  global void warn(String message) {
    if (!warnings.contains(message)) {
      warnings.add(message);
    }
  }

  /**
   * Applies a source's icon and colour to an event.
   * @param e the event to style
   * @return the same event
   */
  public TimeDriveController.EngagementEvent styled(TimeDriveController.EngagementEvent e) {
    if (source != null) {
      if (String.isNotBlank(source.Icon__c)) {
        e.icon = source.Icon__c;
      }
      if (String.isNotBlank(source.Icon_Colour__c)) {
        e.iconColour = source.Icon_Colour__c;
      }
      String legend = TimeDriveConfig.legendLabel(source);
      if (String.isNotBlank(legend)) {
        e.typeLabel = legend;
        e.typeLabelName = TimeDriveConfig.legendLabelName(source);
      }
    }
    return e;
  }

  /** The events of the sources before this one, worked out on demand. */
  public interface PriorEvents {
    /**
     * Returns the events of the earlier sources.
     * @return the events
     */
    List<TimeDriveController.EngagementEvent> load();
  }

  /**
   * A span of time, from since to until: one of the periods a context asks
   * for (spans()), or the timeline's whole window, from the start of the day
   * History years ago to the end of the day Future years ahead (today, with
   * no Future), in the user's time zone.
   */
  global class Span {
    global Datetime since;
    global Datetime until;

    /** Builds the default window: the default history up to today. */
    public Span() {
      this(TimeDriveController.DEFAULT_HISTORY_YEARS, null);
    }

    /**
     * Builds a window from two dates.
     * @param since the start of the window
     * @param until the end of the window
     */
    public Span(Datetime since, Datetime until) {
      this.since = since;
      this.until = until;
    }

    /**
     * Builds a window from years of history and future.
     * @param historyYears how many years back to start
     * @param futureYears how many years ahead to end, or null for today
     */
    public Span(Decimal historyYears, Decimal futureYears) {
      Date today = Date.today();
      since = Datetime.newInstance(
        today.addMonths(-TimeDriveController.monthsIn(historyYears)),
        Time.newInstance(0, 0, 0, 0)
      );
      Date last = futureYears == null ? today : today.addMonths(TimeDriveController.monthsIn(futureYears));
      until = Datetime.newInstance(last, Time.newInstance(23, 59, 59, 999));
    }

    /**
     * Keeps the events whose time lies in the window.
     * @param events the events to filter, or null
     * @return the events inside the window
     */
    public List<TimeDriveController.EngagementEvent> within(List<TimeDriveController.EngagementEvent> events) {
      List<TimeDriveController.EngagementEvent> kept = new List<TimeDriveController.EngagementEvent>();
      for (
        TimeDriveController.EngagementEvent e : events == null
          ? new List<TimeDriveController.EngagementEvent>()
          : events
      ) {
        if (e.occurredAt != null && e.occurredAt >= since && e.occurredAt <= until) {
          kept.add(e);
        }
      }
      return kept;
    }
  }

  /** A count provider's items on one day (and hour, when asked by hour). */
  global class DayCount {
    // Read by an Apex source's own tests: the period's first day (yyyy-MM-dd),
    // its hour, and how many items it has.
    global String dayKey;
    // 0-23 in the user's time zone; null for date-only fields, or by day.
    global Integer hour;
    global Integer count;
    // Counted for the whole period (from the summary's counts), not by hour.
    public Boolean whole = false;

    /**
     * Builds a count for one day.
     * @param dayKey the day as yyyy-MM-dd
     * @param hour the hour 0-23, or null
     * @param count the number of items
     */
    public DayCount(String dayKey, Integer hour, Integer count) {
      this.dayKey = dayKey;
      this.hour = hour;
      this.count = count;
    }
  }

  /**
   * The key (yyyy-MM-dd) of the day, week or month a day falls in: its first day.
   * @param day a date in the period
   * @param unit the period unit (hour, day, week or month)
   * @return the key of the period's first day
   */
  public static String periodKey(Date day, String unit) {
    return String.valueOf(periodStart(day, unit));
  }

  /**
   * The first day of the day, week or month a day falls in.
   * @param day a date in the period
   * @param unit the period unit (hour, day, week or month)
   * @return the first day of the period
   */
  public static Date periodStart(Date day, String unit) {
    if (unit == UNIT_WEEK) {
      return Date.newInstance(day.year(), 1, 1).addDays((day.dayOfYear() - 1) / 7 * 7);
    }
    if (unit == UNIT_MONTH) {
      return day.toStartOfMonth();
    }
    return day;
  }

  /**
   * The last day of the period starting on `start` (weeks stop at 31 December).
   * @param start the first day of the period
   * @param unit the period unit (hour, day, week or month)
   * @return the last day of the period
   */
  public static Date periodEnd(Date start, String unit) {
    if (unit == UNIT_WEEK) {
      Date last = start.addDays(6);
      return last.year() == start.year() ? last : Date.newInstance(start.year(), 12, 31);
    }
    if (unit == UNIT_MONTH) {
      return start.addMonths(1).toStartOfMonth().addDays(-1);
    }
    return start;
  }

  /**
   * How many periods (hours, days, weeks or months) touch first..last, at most.
   * @param first the first day of the span
   * @param last the last day of the span
   * @param unit the period unit (hour, day, week or month)
   * @return the most periods the span touches
   */
  public static Integer periods(Date first, Date last, String unit) {
    Integer days = first.daysBetween(last) + 1;
    if (unit == UNIT_HOUR) {
      return days * 24;
    }
    if (unit == UNIT_WEEK) {
      // A partial week at each year's end, and one at each end of the span.
      return days / 7 + (last.year() - first.year()) + 2;
    }
    if (unit == UNIT_MONTH) {
      return first.monthsBetween(last) + 1;
    }
    return days;
  }
}
