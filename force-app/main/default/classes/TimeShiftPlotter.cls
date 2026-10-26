/**
 * Turns a source's rows into timeline events, the same way for every kind of
 * source, using its Time Trail Source record:
 *
 *   Id Field          unique per event (default Id; ssot__Id__c for Data 360)
 *   Date Field        date or date/time to plot by
 *   Title, Subtitle   templates with {Field} tokens; separators around blank
 *                     values drop out
 *   Record Id Field   the record a click opens (default Id for
 *                     Salesforce sources); a path through lookups is fine
 *   Details Record    the record (and object) whose compact layout an
 *     Field, Object   opened item shows (default the item's own)
 *   Detail Fields     the Time Trail Detail Field records, in order;
 *                     when there are any they replace the compact layout
 */
public with sharing class TimeShiftPlotter {
  private static final Pattern TOKEN = Pattern.compile('\\{([A-Za-z0-9_.]+)\\}');
  public static final String SEPARATOR = ' · ';

  /** Events from either kind of provider. */
  public static List<TimeShiftController.EngagementEvent> run(
    Object provider,
    TimeShiftContext context
  ) {
    if (provider instanceof TimeShiftRowProvider) {
      return plot(context, ((TimeShiftRowProvider) provider).getRows(context));
    }
    return ((TimeShiftProvider) provider).getEvents(context);
  }

  public static List<TimeShiftController.EngagementEvent> plot(
    TimeShiftContext context,
    List<TimeShiftRow> rows
  ) {
    Time_Shift_Source__mdt s = context.source;
    List<Time_Shift_Detail_Field__mdt> detailFields = context.detailFields();
    List<TimeShiftController.EngagementEvent> events = new List<TimeShiftController.EngagementEvent>();
    Integer skipped = 0;
    for (TimeShiftRow row : rows == null ? new List<TimeShiftRow>() : rows) {
      Datetime occurredAt = instant(row.get(context.dateField()));
      if (occurredAt == null) {
        skipped++;
        continue;
      }
      Object key = row.get(context.idField());
      TimeShiftController.EngagementEvent e = new TimeShiftController.EngagementEvent(
          (key == null ? String.valueOf(events.size()) : String.valueOf(key)) + '-' + s.DeveloperName,
          s.Event_Type__c,
          s.Category__c,
          String.isBlank(s.Title__c) ? s.Label : title(s.Title__c, row),
          fill(s.Subtitle__c, row),
          occurredAt
        )
        .source(context.sourceObject, context.sourceLabel)
        .record(salesforceId(row.get(context.recordIdField())))
        .detailRecord(salesforceId(row.get(context.detailsRecordField())), context.detailsObject());
      for (Time_Shift_Detail_Field__mdt d : detailFields) {
        e.detail(detailLabel(d, row), format(row.get(d.Field__c), d.Format__c, row, d.Field__c));
      }
      if (context.columnPaths != null) {
        e.columns = new Map<String, String>();
        for (String field : context.columnPaths.keySet()) {
          String path = context.columnPaths.get(field);
          e.columns.put(field, format(row.get(path), null, row, path));
        }
      }
      if (s.Object_Name__c == 'Event' && row.get('IsAllDayEvent') == true) {
        e.allDay = true;
      }
      e.flags = TimeShiftHighlights.flagsFor(context.highlightRules(), row);
      context.styled(e);
      if (!detailFields.isEmpty()) {
        e.useCompactLayout = false;
      }
      events.add(e);
    }
    if (skipped > 0) {
      context.warn(String.format(Label.Time_Shift_Server_Rows_No_Date, new List<String>{ s.Label, String.valueOf(skipped), context.dateField() }));
    }
    // Enhanced Email's messages say who they went to and whether they were opened.
    if (s.Object_Name__c == 'EmailMessage') {
      TimeShiftEmails.enrich(events);
    }
    return events;
  }

  // Field paths named by {tokens} in a template.
  public static Set<String> tokens(String template) {
    Set<String> found = new Set<String>();
    if (String.isBlank(template)) {
      return found;
    }
    Matcher m = TOKEN.matcher(template);
    while (m.find()) {
      found.add(m.group(1));
    }
    return found;
  }

  // The title, or where its fields are all blank, their labels in brackets:
  // an email with no subject is "[Subject]", so there's still something to
  // read and to click.
  public static String title(String template, TimeShiftRow row) {
    String filled = fill(template, row);
    if (String.isNotBlank(filled) || tokens(template).isEmpty()) {
      return filled;
    }
    List<String> labels = new List<String>();
    for (String path : tokens(template)) {
      Schema.DescribeFieldResult field = row?.describe(path);
      labels.add('[' + (field == null ? path : field.getLabel()) + ']');
    }
    return String.join(labels, SEPARATOR);
  }

  // Fill a template's tokens from a row, then drop separators left around
  // blank values: "{Subject} · {CaseNumber}" with no subject -> "00001028".
  public static String fill(String template, TimeShiftRow row) {
    if (String.isBlank(template)) {
      return null;
    }
    String result = template;
    for (String path : tokens(template)) {
      result = result.replace('{' + path + '}', format(row.get(path), null, row, path));
    }
    List<String> parts = new List<String>();
    for (String part : result.split(SEPARATOR)) {
      if (String.isNotBlank(part)) {
        parts.add(part.trim());
      }
    }
    return String.join(parts, SEPARATOR);
  }

  /**
   * A value as text. Format (Text, Date, Date/Time, Currency, Number) is the
   * detail field's; blank means by the value's type, with currency fields
   * on records shown as currency.
   */
  public static String format(Object value, String format, TimeShiftRow row, String path) {
    if (value == null) {
      return '';
    }
    if (value instanceof Datetime) {
      return format == 'Date' ? ((Datetime) value).date().format() : ((Datetime) value).format();
    }
    if (value instanceof Date) {
      return ((Date) value).format();
    }
    if (value instanceof Boolean) {
      return (Boolean) value ? Label.Time_Shift_Server_Yes : Label.Time_Shift_Server_No;
    }
    if (value instanceof Double) {
      value = Decimal.valueOf((Double) value);
    }
    if (value instanceof Decimal) {
      Schema.DescribeFieldResult field = row?.describe(path);
      Boolean asCurrency =
        format == 'Currency' || (String.isBlank(format) && field?.getType() == Schema.DisplayType.CURRENCY);
      return asCurrency ? '$' + String.valueOf(((Decimal) value).setScale(2)) : plain((Decimal) value, field);
    }
    return String.valueOf(value);
  }

  // A number to its field's decimal places (at most 6), without trailing
  // zeros: floating-point noise (2713.3099999999999) reads 2713.31, and a
  // count stored with decimals (2.000000) reads 2.
  @TestVisible
  private static String plain(Decimal value, Schema.DescribeFieldResult field) {
    Integer places = field == null ? MAX_PLACES : Math.min(Math.max(field.getScale(), 0), MAX_PLACES);
    return value.setScale(Math.min(value.scale(), places), System.RoundingMode.HALF_UP)
      .stripTrailingZeros()
      .toPlainString();
  }
  private static final Integer MAX_PLACES = 6;

  // Dates plot at midday, so they land on their own day in any time zone.
  private static Datetime instant(Object value) {
    if (value instanceof Datetime) {
      return (Datetime) value;
    }
    if (value instanceof Date) {
      return Datetime.newInstance((Date) value, Time.newInstance(12, 0, 0, 0));
    }
    return null;
  }

  private static Id salesforceId(Object value) {
    if (value instanceof Id) {
      return (Id) value;
    }
    try {
      return value == null ? null : Id.valueOf(String.valueOf(value));
    } catch (Exception e) {
      return null;
    }
  }

  // A label of its own, else the field's in the user's language. Setup
  // saves a record with no label of its own as Label = the field (a label
  // is required), so that counts as none.
  private static String detailLabel(Time_Shift_Detail_Field__mdt d, TimeShiftRow row) {
    if (String.isNotBlank(d.Label) && d.Label != String.valueOf(d.Field__c).left(40)) {
      return d.Label;
    }
    return row.labelOf(d.Field__c);
  }
}
