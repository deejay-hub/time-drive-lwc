/**
 * Highlights: a small icon on an item when a checkbox field is checked (high
 * priority, escalated, VIP), or when a date field is past on a record that
 * isn't closed (overdue: a task's Due Date). The fields are read with the
 * item's own query, so a highlight costs a column or two, not a request.
 */
// The branching follows the platform's cases and the plot's rules; splitting it up would only scatter them.
@SuppressWarnings('PMD.CyclomaticComplexity, PMD.CognitiveComplexity')
public with sharing class TimeDriveHighlights {
  /** One highlight per source. */
  public static final Integer MAX_RULES = 1;

  /** A rule ready to test rows against. */
  public class Rule {
    public String field;
    public String icon;
    public String colour;
    // The field's label in the user's language (for overdue, "Overdue"): what the icon says.
    public String fieldLabel;
    // A date field: the icon shows while the date is past.
    public Boolean overdue = false;
    // For overdue, the record's IsClosed where it has one: a closed record isn't overdue.
    public String closedField;
  }

  /**
   * The source's rules whose field the user can read (one they can't would fail the whole
   * query), at most MAX_RULES: a checkbox, or a date or date/time (overdue). Other kinds of
   * field are left out.
   * @param objectName the API name of the source's object
   * @param stored the saved highlight records for the source
   * @return the rules to apply
   */
  public static List<Rule> rulesFor(String objectName, List<Time_Drive_Highlight__mdt> stored) {
    List<Rule> out = new List<Rule>();
    if (stored == null || stored.isEmpty() || String.isBlank(objectName)) {
      return out;
    }
    try {
      TimeDriveConfig.fieldMap(objectName);
    } catch (Exception e) {
      return out;
    }
    for (Time_Drive_Highlight__mdt h : stored) {
      if (out.size() >= MAX_RULES) {
        break;
      }
      if (String.isBlank(h.Field__c)) {
        continue;
      }
      Schema.DescribeFieldResult fd = TimeDriveConfig.fieldDescribe(objectName, h.Field__c);
      if (fd == null) {
        continue;
      }
      Schema.DisplayType type = fd.getType();
      Boolean isDate = type == Schema.DisplayType.DATE || type == Schema.DisplayType.DATETIME;
      if (!fd.isAccessible() || (type != Schema.DisplayType.BOOLEAN && !isDate)) {
        continue;
      }
      Rule r = new Rule();
      // A field reached through a lookup keeps its path (Task.IsClosed).
      TimeDriveConfig.PathField path = TimeDriveConfig.pathField(objectName, h.Field__c);
      String prefix = path?.prefix ?? '';
      r.field = prefix + fd.getName();
      r.icon = String.isBlank(h.Icon__c) ? 'dot' : h.Icon__c;
      r.colour = String.isBlank(h.Colour__c) ? null : h.Colour__c;
      r.fieldLabel = fd.getLabel();
      if (isDate) {
        r.overdue = true;
        r.fieldLabel = Label.Time_Drive_Server_Overdue;
        Schema.DescribeFieldResult closed = TimeDriveConfig.fieldDescribe(path?.owner ?? objectName, 'IsClosed');
        if (closed != null && closed.isAccessible()) {
          r.closedField = prefix + closed.getName();
        }
      }
      out.add(r);
    }
    return out;
  }

  /**
   * The fields the rules read, for the item's query.
   * @param rules the rules in use
   * @return the field paths to select
   */
  public static Set<String> fieldsOf(List<Rule> rules) {
    Set<String> out = new Set<String>();
    for (Rule r : rules) {
      out.add(r.field);
      if (r.closedField != null) {
        out.add(r.closedField);
      }
    }
    return out;
  }

  /**
   * The icons a row earns; null for none.
   * @param rules the rules in use
   * @param row the row to test
   * @return the flags for the checked fields, or null
   */
  public static List<TimeDriveController.Flag> flagsFor(List<Rule> rules, TimeDriveRow row) {
    List<TimeDriveController.Flag> out;
    for (Rule r : rules) {
      if (!(r.overdue ? isOverdue(r, row) : row.get(r.field) == true)) {
        continue;
      }
      if (out == null) {
        out = new List<TimeDriveController.Flag>();
      }
      out.add(new TimeDriveController.Flag(r.icon, r.colour, r.fieldLabel));
    }
    return out;
  }

  // Past (a Date before the user's today, a Date/Time before now) and not closed.
  private static Boolean isOverdue(Rule r, TimeDriveRow row) {
    if (r.closedField != null && row.get(r.closedField) == true) {
      return false;
    }
    Object value = row.get(r.field);
    // A Date first: Apex counts a Date as a Datetime too.
    if (value instanceof Date) {
      return (Date) value < Date.today();
    }
    if (value instanceof Datetime) {
      return (Datetime) value < Datetime.now();
    }
    return false;
  }
}
