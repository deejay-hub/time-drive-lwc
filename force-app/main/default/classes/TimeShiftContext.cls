/**
 * What a provider gets: the record the timeline is on, how far back to
 * look, its own Time Trail Source record, the events earlier sources
 * returned (a provider can build on them), and somewhere to
 * report what it couldn't read.
 */
public with sharing class TimeShiftContext {
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

  public Id recordId;
  public String parentObject;
  public Datetime since;
  // The end of the timeline's window, or null for up to now. Events after it
  // are dropped anyway; queries can skip them.
  public Datetime until;
  // Just these spans of the window, when set: the days on screen.
  public List<TimeShiftController.TimeWindow> ranges;
  public Time_Shift_Source__mdt source;
  // A page of the source's items (View all), when set: at most pageSize,
  // newest first, after pageAt (and, at that same moment, before pageId).
  public Integer pageSize;
  public Datetime pageAt;
  public Id pageId;
  // A page's extra columns (the object's compact layout fields): each
  // field asked for, and the path read for it (a lookup's name).
  public Map<String, String> columnPaths;
  // Read when a provider first asks: earlier sources the summary only
  // counted are read in full then, not for every source.
  public List<TimeShiftController.EngagementEvent> priorEvents {
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
  public List<TimeShiftController.Problem> problems = new List<TimeShiftController.Problem>();
  // A person account's own Contact: links to Contact (Task.WhoId,
  // Case.ContactId) match it, links to Account match the account.
  public Id personContactId;

  // The Contact a Contact-based source reads for: the page's, or a person
  // account's own.
  public Id contactId() {
    return personContactId != null ? personContactId : recordId;
  }

  // The Id a link field matches: a person account's Contact when the field
  // points at Contact, else the page's record.
  public Id parentIdFor(Schema.DescribeFieldResult link) {
    if (personContactId != null && link != null && link.getReferenceTo().contains(Contact.SObjectType)) {
      return personContactId;
    }
    return recordId;
  }

  // Where the events say they come from (the expanded event's footer).
  // Defaults to Object Name and the record's label; providers may set them.
  public String sourceObject;
  public String sourceLabel;

  public TimeShiftContext(
    Id recordId,
    String parentObject,
    Datetime since,
    Time_Shift_Source__mdt source,
    List<TimeShiftController.EngagementEvent> priorEvents,
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
    this.priorEvents = priorEvents == null
      ? new List<TimeShiftController.EngagementEvent>()
      : priorEvents;
    this.warnings = warnings == null ? new List<String>() : warnings;
    this.sourceObject = source?.Object_Name__c;
    this.sourceLabel = source?.Label;
  }

  /** The windows a provider should read: its ranges, or the whole window. */
  public List<TimeShiftController.TimeWindow> spans() {
    if (ranges != null) {
      // Clipped to the source's own history, when it has one.
      List<TimeShiftController.TimeWindow> out = new List<TimeShiftController.TimeWindow>();
      for (TimeShiftController.TimeWindow r : ranges) {
        if (since == null || r.until == null || r.until >= since) {
          out.add(
            r.since == null ||
              since == null ||
              r.since >= since
              ? r
              : new TimeShiftController.TimeWindow(since, r.until)
          );
        }
      }
      return out;
    }
    return new List<TimeShiftController.TimeWindow>{
      new TimeShiftController.TimeWindow(since, until)
    };
  }

  // Salesforce, Data 360 or Apex. Records from before Kind default from
  // their provider class.
  public String kind() {
    if (String.isNotBlank(source?.Kind__c)) {
      return source.Kind__c;
    }
    return String.isBlank(source?.Provider_Class__c) ? KIND_SALESFORCE : KIND_APEX;
  }

  // The source's record cap, newest first.
  public Integer maxRecords() {
    return source?.Max_Records__c == null ? DEFAULT_MAX_RECORDS : source.Max_Records__c.intValue();
  }

  public String dateField() {
    if (String.isNotBlank(source?.Date_Field__c)) {
      return source.Date_Field__c;
    }
    return kind() == KIND_DATA_360 ? 'ssot__EngagementDateTm__c' : null;
  }

  public String idField() {
    if (String.isNotBlank(source?.Id_Field__c)) {
      return source.Id_Field__c;
    }
    return kind() == KIND_DATA_360 ? 'ssot__Id__c' : 'Id';
  }

  public String recordIdField() {
    if (String.isNotBlank(source?.Record_Id_Field__c)) {
      return source.Record_Id_Field__c;
    }
    return kind() == KIND_SALESFORCE ? 'Id' : null;
  }

  // Whose compact layout an opened item shows: the Details Record Field,
  // else the item's own record (Id for Salesforce sources, the linked
  // record otherwise), on the Details Object, else the source's.
  public String detailsRecordField() {
    String own = populated('Details_Record_Field__c');
    if (String.isNotBlank(own)) {
      return own;
    }
    return kind() == KIND_SALESFORCE ? 'Id' : recordIdField();
  }

  public String detailsObject() {
    String objectName = populated('Details_Object__c');
    if (String.isNotBlank(populated('Details_Record_Field__c')) && String.isNotBlank(objectName)) {
      return objectName;
    }
    return sourceObject;
  }

  // A field of the source, when it has one: a source read by a query that
  // didn't select the field (or built in memory without it) has none.
  private String populated(String field) {
    Object value = source?.getPopulatedFieldsAsMap().get(field);
    return value == null ? null : String.valueOf(value);
  }

  // The Details Record Field, when one is set, for the providers to read.
  public String detailsRecordFieldIfSet() {
    return populated('Details_Record_Field__c');
  }

  // A draft source's detail fields (the setup wizard's preview), in place
  // of the saved ones.
  public List<Time_Shift_Detail_Field__mdt> draftDetailFields;

  public List<Time_Shift_Detail_Field__mdt> detailFields() {
    if (draftDetailFields != null) {
      return draftDetailFields;
    }
    return TimeShiftConfig.detailFields(source?.DeveloperName);
  }

  // A draft source's highlights (the setup wizard's preview), in place of the
  // saved ones.
  public List<Time_Shift_Highlight__mdt> draftHighlights;
  private List<TimeShiftHighlights.Rule> highlightRulesCache;

  /** The highlight rules in use (Salesforce sources whose fields the user can read). */
  public List<TimeShiftHighlights.Rule> highlightRules() {
    if (highlightRulesCache == null) {
      highlightRulesCache = new List<TimeShiftHighlights.Rule>();
      if (source != null && kind() == KIND_SALESFORCE) {
        highlightRulesCache = TimeShiftHighlights.rulesFor(
          source.Object_Name__c,
          draftHighlights != null ? draftHighlights : TimeShiftConfig.highlights(source.DeveloperName)
        );
      }
    }
    return highlightRulesCache;
  }

  // A source that couldn't be read: its name and the kind of failure for the
  // user, never the exception's message (it can carry query text and field
  // names); that goes to the debug log for an admin.
  public void fail(String what, Exception e) {
    System.debug(
      LoggingLevel.WARN,
      'Time Trail: ' + what + ' couldn\'t be read. ' + e.getTypeName() + ': ' + e.getMessage()
    );
    for (TimeShiftController.Problem p : problems) {
      if (p.source == what) {
        return;
      }
    }
    problems.add(new TimeShiftController.Problem(what, TimeShiftController.kindOf(e)));
  }

  // A warning, once, however many sources run into it.
  public void warn(String message) {
    if (!warnings.contains(message)) {
      warnings.add(message);
    }
  }

  // Applies a source's icon, colour and compact-layout choice to an event.
  public TimeShiftController.EngagementEvent styled(
    TimeShiftController.EngagementEvent e
  ) {
    if (source != null) {
      if (String.isNotBlank(source.Icon__c)) {
        e.icon = source.Icon__c;
      }
      if (String.isNotBlank(source.Icon_Colour__c)) {
        e.iconColour = source.Icon_Colour__c;
      }
      String legend = TimeShiftConfig.legendLabel(source);
      if (String.isNotBlank(legend)) {
        e.typeLabel = legend;
      }
      e.useCompactLayout = source.Use_Compact_Layout__c == true && (e.detailRecordId != null || e.recordId != null);
    }
    return e;
  }

  /** The events of the sources before this one, worked out on demand. */
  public interface PriorEvents {
    List<TimeShiftController.EngagementEvent> load();
  }

  /** A count provider's items on one day (and hour, when asked by hour). */
  public class DayCount {
    public String dayKey;
    // 0-23 in the user's time zone; null for date-only fields, or by day.
    public Integer hour;
    public Integer count;
    // Counted for the whole period (from the summary's counts), not by hour.
    public Boolean whole = false;

    public DayCount(String dayKey, Integer hour, Integer count) {
      this.dayKey = dayKey;
      this.hour = hour;
      this.count = count;
    }
  }

  /** The key (yyyy-MM-dd) of the day, week or month a day falls in: its first day. */
  public static String periodKey(Date day, String unit) {
    return String.valueOf(periodStart(day, unit));
  }

  public static Date periodStart(Date day, String unit) {
    if (unit == UNIT_WEEK) {
      return Date.newInstance(day.year(), 1, 1).addDays((day.dayOfYear() - 1) / 7 * 7);
    }
    if (unit == UNIT_MONTH) {
      return day.toStartOfMonth();
    }
    return day;
  }

  /** The last day of the period starting on `start` (weeks stop at 31 December). */
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

  /** How many periods (hours, days, weeks or months) touch first..last, at most. */
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
