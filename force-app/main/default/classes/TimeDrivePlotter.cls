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
  // Each picklist's labels by value, in the user's language, once a request.
  private static Map<Schema.SObjectField, Map<String, String>> picklistLabels = new Map<Schema.SObjectField, Map<String, String>>();

  /**
   * A provider's rows, plotted.
   *
   * @param provider the source's provider
   * @param context the request context
   * @return the plotted events
   */
  public static List<TimeDriveController.EngagementEvent> run(TimeDriveRowProvider provider, TimeDriveContext context) {
    return plot(context, provider.getRows(context));
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
    for (TimeDriveRow row : rows == null ? new List<TimeDriveRow>() : rows) {
      Datetime occurredAt = instant(row.get(context.dateField()));
      // Items with no date are left out quietly, so a few gaps in the data
      // don't put a warning over the rest.
      if (occurredAt == null) {
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
        e.detail(detailOf(d, row));
      }
      if (TimeDriveConfig.dateOwner(s) == 'Event' && row.get(TimeDriveConfig.datePrefix(s) + 'IsAllDayEvent') == true) {
        e.allDay = true;
      }
      e.flags = TimeDriveHighlights.flagsFor(context.highlightRules(), row);
      context.styled(e);
      events.add(e);
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
    Decimal amount = amountOf(value);
    Schema.DescribeFieldResult field = row?.describe(path);
    if (amount != null) {
      // In the user's locale (1,200.5 or 1.200,5); money with its currency
      // (AUD 1,200), as the components can't fill a title themselves.
      return isMoney(format, field) ? currencyOf(row) + ' ' + money(amount) : plain(amount, field);
    }
    if (value instanceof String && field != null) {
      return picklistLabel((String) value, field);
    }
    return String.valueOf(value);
  }

  /**
   * A detail field's label and value for a row: a number keeps its amount
   * (and money its currency) for the components to show in the user's own way.
   *
   * @param d the detail field
   * @param row the row
   * @return the detail
   */
  @TestVisible
  private static TimeDriveController.Detail detailOf(Time_Drive_Detail_Field__mdt d, TimeDriveRow row) {
    Object value = row.get(d.Field__c);
    TimeDriveController.Detail detail = new TimeDriveController.Detail(
      detailLabel(d, row),
      format(value, d.Format__c, row, d.Field__c)
    );
    detail.amount = amountOf(value);
    if (detail.amount != null && isMoney(d.Format__c, row.describe(d.Field__c))) {
      detail.currencyCode = currencyOf(row);
    }
    return detail;
  }

  // A number as a Decimal, or null for anything else (dates included).
  private static Decimal amountOf(Object value) {
    if (value instanceof Decimal) {
      return (Decimal) value;
    }
    if (value instanceof Double) {
      return Decimal.valueOf((Double) value);
    }
    if (value instanceof Integer || value instanceof Long) {
      return Decimal.valueOf(String.valueOf(value));
    }
    return null;
  }

  private static Boolean isMoney(String format, Schema.DescribeFieldResult field) {
    return format == 'Currency' || (String.isBlank(format) && field?.getType() == Schema.DisplayType.CURRENCY);
  }

  // The row's own currency (a record's CurrencyIsoCode where the org has
  // several, or a CurrencyIsoCode key in a map), else the user's.
  private static String currencyOf(TimeDriveRow row) {
    Object own;
    try {
      own = row?.get('CurrencyIsoCode');
    } catch (Exception e) {
      own = null;
    }
    return own instanceof String && String.isNotBlank((String) own) ? (String) own : UserInfo.getDefaultCurrency();
  }

  // A picklist's value as its label in the user's language (each value of a
  // multi-select); highlights still compare the values themselves.
  private static String picklistLabel(String value, Schema.DescribeFieldResult field) {
    Schema.DisplayType type = field.getType();
    if (type != Schema.DisplayType.PICKLIST && type != Schema.DisplayType.MULTIPICKLIST) {
      return value;
    }
    // By field token, which is each object's own (Case.Status isn't Task.Status).
    Schema.SObjectField key = field.getSObjectField();
    Map<String, String> labels = picklistLabels.get(key);
    if (labels == null) {
      labels = new Map<String, String>();
      for (Schema.PicklistEntry entry : field.getPicklistValues()) {
        labels.put(entry.getValue(), entry.getLabel());
      }
      picklistLabels.put(key, labels);
    }
    List<String> shown = new List<String>();
    for (String part : value.split(';')) {
      shown.add(labels.containsKey(part) ? labels.get(part) : part);
    }
    return String.join(shown, '; ');
  }

  // A number to its field's decimal places (at most 6), without trailing
  // zeros: floating-point noise (2713.3099999999999) reads 2713.31, and a
  // count stored with decimals (2.000000) reads 2.
  @TestVisible
  private static String plain(Decimal value, Schema.DescribeFieldResult field) {
    Integer places = field == null ? MAX_PLACES : Math.min(Math.max(field.getScale(), 0), MAX_PLACES);
    // Grouped and separated as the user's locale does it.
    return value.setScale(Math.min(value.scale(), places), System.RoundingMode.HALF_UP).stripTrailingZeros().format();
  }

  // Money to two places in the user's locale (1,200.50 or 1.200,50):
  // Decimal.format() drops trailing zeros, so they go back after its mark.
  @TestVisible
  private static String money(Decimal amount) {
    String text = amount.setScale(2, System.RoundingMode.HALF_UP).format();
    String mark = Decimal.valueOf('1.5').format().substring(1, 2);
    Integer at = text.lastIndexOf(mark);
    if (at < 0) {
      return text + mark + '00';
    }
    return text.length() - at == 2 ? text + '0' : text;
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
    // A custom label ($Label.Points) is shown in the user's language.
    if (String.isNotBlank(d.Label) && d.Label.startsWith(TimeDriveConfig.LABEL_PREFIX)) {
      String translated = TimeDriveConfig.customLabel(d.Label.substring(TimeDriveConfig.LABEL_PREFIX.length()));
      return translated == null ? d.Label : translated;
    }
    if (String.isNotBlank(d.Label) && d.Label != String.valueOf(d.Field__c).left(40)) {
      return d.Label;
    }
    return row.labelOf(d.Field__c);
  }
}
