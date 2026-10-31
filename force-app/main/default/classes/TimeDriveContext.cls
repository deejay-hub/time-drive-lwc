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
public with sharing class TimeDriveContext {
  public static final Integer DEFAULT_MAX_RECORDS = 1000;
  public static final String KIND_SALESFORCE = 'Salesforce';
  public static final String KIND_DATA_360 = 'Data 360';
  public static final String KIND_APEX = 'Apex';
  // What a count is per: an hour of a day, a day, a week (from 1 January:
  // the 1st-7th, 8th-14th ... as SOQL's WEEK_IN_YEAR) or a calendar month.
  public static final String UNIT_HOUR = 'hour';
  public static final String UNIT_DAY = 'day';
  public static final String UNIT_WEEK = 'week';
  public static final String UNIT_MONTH = 'month';
  // A field a source names, as a field path and nothing else.
  private static final Pattern FIELD_PATH = Pattern.compile('[A-Za-z][A-Za-z0-9_]*(\\.[A-Za-z][A-Za-z0-9_]*)*');

  public Id recordId;
  public String parentObject;
  public Datetime since;
  // The end of the timeline's window, or null for up to now. Events after it
  // are dropped anyway; queries can skip them.
  public Datetime until;
  // Just these spans of the window, when set: the days on screen.
  public List<TimeDriveController.TimeWindow> ranges;
  public Time_Drive_Source__mdt source;
  // A page of the source's items (View all), when set: at most pageSize,
  // newest first, after pageAt (and, at that same moment, before pageId).
  public Integer pageSize;
  public Datetime pageAt;
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
  // every source's context; the raw exception goes to the debug log only).
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
    Object months = source?.getPopulatedFieldsAsMap().get('History_Months__c');
    Datetime own = months == null
      ? null
      : Datetime.newInstance(Date.today().addMonths(-((Decimal) months).intValue()), Time.newInstance(0, 0, 0, 0));
    this.since = since != null && own != null && own > since ? own : since;
    this.source = source;
    this.priorEvents = priorEvents == null ? new List<TimeDriveController.EngagementEvent>() : priorEvents;
    this.warnings = warnings == null ? new List<String>() : warnings;
    this.sourceObject = source?.Object_Name__c;
    this.sourceLabel = source?.Label;
  }

  /**
   * The windows a provider should read: its ranges, or the whole window.
   * @return the time windows to read
   */
  public List<TimeDriveController.TimeWindow> spans() {
    if (ranges != null) {
      // Clipped to the source's own history, when it has one.
      List<TimeDriveController.TimeWindow> out = new List<TimeDriveController.TimeWindow>();
      for (TimeDriveController.TimeWindow r : ranges) {
        if (since == null || r.until == null || r.until >= since) {
          out.add(
            r.since == null ||
              since == null ||
              r.since >= since
              ? r
              : new TimeDriveController.TimeWindow(since, r.until)
          );
        }
      }
      return out;
    }
    return new List<TimeDriveController.TimeWindow>{ new TimeDriveController.TimeWindow(since, until) };
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
  public Integer maxRecords() {
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
  public Plot plotBy(String dateKey) {
    source = source == null ? new Time_Drive_Source__mdt() : source.clone(true);
    if (String.isBlank(source.Date_Field__c)) {
      source.Date_Field__c = dateKey;
    }
    return new Plot(this);
  }

  /** The rest of how an Apex source's rows are plotted (see plotBy). */
  public class Plot {
    private TimeDriveContext context;

    private Plot(TimeDriveContext context) {
      this.context = context;
    }

    /**
     * The title, with {Key} filled from each row, as '{Product2.Name}'.
     * @param template the title
     * @return this plot
     */
    public Plot title(String template) {
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
    public Plot subtitle(String template) {
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
    public Plot opens(String recordIdKey) {
      if (String.isBlank(context.source.Record_Id_Field__c)) {
        context.source.Record_Id_Field__c = recordIdKey;
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
  public String dateCondition(Schema.SObjectType objectType, String field, Map<String, Object> binds) {
    Schema.DescribeFieldResult d = TimeDriveConfig.fieldDescribe(String.valueOf(objectType), field);
    Boolean byDay = d?.getType() == Schema.DisplayType.DATE;
    List<String> out = new List<String>();
    List<TimeDriveController.TimeWindow> windows = spans();
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
   * For data from elsewhere: whether the timeline asks for an item at this
   * moment (a page asks for a few days at a time, the summary for the whole
   * window). Return only the items it wants.
   * @param at the item's date and time
   * @return true when it falls in a span asked for
   */
  public Boolean wants(Datetime at) {
    if (at == null) {
      return false;
    }
    for (TimeDriveController.TimeWindow w : spans()) {
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
  public Boolean wants(Date day) {
    if (day == null) {
      return false;
    }
    Datetime starts = Datetime.newInstance(day, Time.newInstance(0, 0, 0, 0));
    Datetime ends = Datetime.newInstance(day, Time.newInstance(23, 59, 59, 999));
    for (TimeDriveController.TimeWindow w : spans()) {
      if ((w.since == null || ends >= w.since) && (w.until == null || starts <= w.until)) {
        return true;
      }
    }
    return false;
  }

  /**
   * For record rows: the fields to SELECT, those given then those the
   * source's title, subtitle and detail fields name, each once and only if
   * it's a field path (so a source can't put anything else into the query).
   * @param always the fields every row needs (its Id, the date)
   * @return the fields to SELECT
   */
  public List<String> fieldsToQuery(List<String> always) {
    List<String> wanted = new List<String>(always);
    wanted.addAll(TimeDrivePlotter.tokens(source?.Title__c));
    wanted.addAll(TimeDrivePlotter.tokens(source?.Subtitle__c));
    for (Time_Drive_Detail_Field__mdt d : detailFields()) {
      wanted.add(d.Field__c);
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
  public List<TimeDriveHighlights.Rule> highlightRules() {
    if (highlightRulesCache == null) {
      highlightRulesCache = new List<TimeDriveHighlights.Rule>();
      if (source != null && kind() == KIND_SALESFORCE) {
        highlightRulesCache = TimeDriveHighlights.rulesFor(
          source.Object_Name__c,
          draftHighlights != null ? draftHighlights : TimeDriveConfig.highlights(source.DeveloperName)
        );
      }
    }
    return highlightRulesCache;
  }

  /**
   * Records a source that couldn't be read: its name and the kind of failure for the user, never
   * the exception's message (it can carry query text and field names); that goes to the debug log
   * for an admin.
   * @param what the source's name
   * @param e the exception raised
   */
  public void fail(String what, Exception e) {
    System.debug(
      LoggingLevel.WARN,
      'Time Drive: ' + what + ' couldn\'t be read. ' + e.getTypeName() + ': ' + e.getMessage()
    );
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
  public void warn(String message) {
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

  /** A count provider's items on one day (and hour, when asked by hour). */
  public class DayCount {
    public String dayKey;
    // 0-23 in the user's time zone; null for date-only fields, or by day.
    public Integer hour;
    public Integer count;
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
