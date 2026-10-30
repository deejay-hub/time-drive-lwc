/**
 * Turns a source's rows into timeline events, the same way for every kind of
 * source, using its Time Drive Source record:
 *
 *   Id Field          unique per event (default Id; ssot__Id__c for Data 360)
 *   Date Field        date or date/time to plot by
 *   Title, Subtitle   templates with {Field} tokens; separators around blank
 *                     values drop out
 *   Record Id Field   the record a click opens (default Id for
 *                     Salesforce sources); a path through lookups is fine
 *   Detail Fields     the Time Drive Detail Field records, in order: what
 *                     an opened item shows (the admin's choice, nothing else)
 */
// The branching follows the platform's cases and the plot's rules; splitting it up would only scatter them.
// Size, parameter lists and field counts follow the platform's entry points, its cases and the data the components exchange;
// splitting them up would only scatter what belongs together.
@SuppressWarnings('PMD.CyclomaticComplexity, PMD.CognitiveComplexity, PMD.ExcessiveParameterList')
public with sharing class TimeDrivePlotter {
  private static final Pattern TOKEN = Pattern.compile('\\{([A-Za-z0-9_.]+)\\}');
  public static final String SEPARATOR = ' · ';
  private static final Integer MAX_PLACES = 6;

  /**
   * Events from either kind of provider.
   *
   * @param provider a row provider or an event provider
   * @param context the request context
   * @return the plotted events
   */
  public static List<TimeDriveController.EngagementEvent> run(Object provider, TimeDriveContext context) {
    if (provider instanceof TimeDriveRowProvider) {
      return plot(context, ((TimeDriveRowProvider) provider).getRows(context));
    }
    return ((TimeDriveProvider) provider).getEvents(context);
  }

  /**
   * Turns rows into plotted events using the source's templates and fields.
   *
   * @param context the request context
   * @param rows the rows to plot
   * @return the events
   */
  public static List<TimeDriveController.EngagementEvent> plot(TimeDriveContext context, List<TimeDriveRow> rows) {
    Time_Drive_Source__mdt s = context.source;
    List<Time_Drive_Detail_Field__mdt> detailFields = context.detailFields();
    List<TimeDriveController.EngagementEvent> events = new List<TimeDriveController.EngagementEvent>();
    Integer skipped = 0;
    for (TimeDriveRow row : rows == null ? new List<TimeDriveRow>() : rows) {
      Datetime occurredAt = instant(row.get(context.dateField()));
      if (occurredAt == null) {
        skipped++;
        continue;
      }
      Object key = row.get(context.idField());
      TimeDriveController.EngagementEvent e = new TimeDriveController.EngagementEvent(
          (key == null ? String.valueOf(events.size()) : String.valueOf(key)) + '-' + s.DeveloperName,
          s.Event_Type__c,
          TimeDriveConfig.lensKey(s),
          String.isBlank(s.Title__c) ? s.Label : title(s.Title__c, row),
          fill(s.Subtitle__c, row),
          occurredAt
        )
        .source(context.sourceObject, context.sourceLabel)
        .record(salesforceId(row.get(context.recordIdField())));
      for (Time_Drive_Detail_Field__mdt d : detailFields) {
        e.detail(detailLabel(d, row), format(row.get(d.Field__c), d.Format__c, row, d.Field__c));
      }
      if (TimeDriveConfig.dateOwner(s) == 'Event' && row.get(TimeDriveConfig.datePrefix(s) + 'IsAllDayEvent') == true) {
        e.allDay = true;
      }
      e.flags = TimeDriveHighlights.flagsFor(context.highlightRules(), row);
      context.styled(e);
      events.add(e);
    }
    if (skipped > 0) {
      context.warn(
        String.format(
          Label.Time_Drive_Server_Rows_No_Date,
          new List<String>{ s.Label, String.valueOf(skipped), context.dateField() }
        )
      );
    }
    // Enhanced Email's messages say who they went to and whether they were opened.
    if (s.Object_Name__c == 'EmailMessage') {
      TimeDriveEmails.enrich(events);
    }
    return events;
  }

  /**
   * Finds the field paths named by {tokens} in a template.
   *
   * @param template the template text
   * @return the field paths
   */
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

  /**
   * The title, or where its fields are all blank, their labels in brackets:
   * an email with no subject is "[Subject]", so there's still something to
   * read and to click.
   *
   * @param template the title template
   * @param row the row to read
   * @return the title
   */
  public static String title(String template, TimeDriveRow row) {
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

  /**
   * Fill a template's tokens from a row, then drop separators left around
   * blank values: "{Subject} · {CaseNumber}" with no subject -> "00001028".
   *
   * @param template the template text
   * @param row the row to read
   * @return the filled template
   */
  public static String fill(String template, TimeDriveRow row) {
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
   *
   * @param value the value to format
   * @param format the format, blank for the value's type
   * @param row the row the value is from
   * @param path the value's field path
   * @return the formatted text
   */
  public static String format(Object value, String format, TimeDriveRow row, String path) {
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
      return (Boolean) value ? Label.Time_Drive_Server_Yes : Label.Time_Drive_Server_No;
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
  private static String detailLabel(Time_Drive_Detail_Field__mdt d, TimeDriveRow row) {
    if (String.isNotBlank(d.Label) && d.Label != String.valueOf(d.Field__c).left(40)) {
      return d.Label;
    }
    return row.labelOf(d.Field__c);
  }
}
