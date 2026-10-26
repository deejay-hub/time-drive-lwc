/**
 * Highlights: a small icon on an item when a checkbox field is checked (high
 * priority, escalated, VIP). The field is read with the item's own query, so a
 * highlight costs a column, not a request.
 */
public with sharing class TimeShiftHighlights {
  /** One highlight per source. */
  public static final Integer MAX_RULES = 1;

  /** A rule ready to test rows against. */
  public class Rule {
    public String field;
    public String icon;
    public String colour;
    // The field's label in the user's language: what the icon says.
    public String fieldLabel;
  }

  /**
   * The source's rules whose checkbox the user can read (one they can't would
   * fail the whole query), at most MAX_RULES. Other kinds of field are left out.
   */
  public static List<Rule> rulesFor(String objectName, List<Time_Shift_Highlight__mdt> stored) {
    List<Rule> out = new List<Rule>();
    if (stored == null || stored.isEmpty() || String.isBlank(objectName)) {
      return out;
    }
    try {
      TimeShiftConfig.fieldMap(objectName);
    } catch (Exception e) {
      return out;
    }
    for (Time_Shift_Highlight__mdt h : stored) {
      if (out.size() >= MAX_RULES) {
        break;
      }
      if (String.isBlank(h.Field__c)) {
        continue;
      }
      Schema.DescribeFieldResult fd = TimeShiftConfig.fieldDescribe(objectName, h.Field__c);
      if (fd == null) {
        continue;
      }
      if (!fd.isAccessible() || fd.getType() != Schema.DisplayType.BOOLEAN) {
        continue;
      }
      Rule r = new Rule();
      // A field reached through a lookup keeps its path (Task.IsClosed).
      r.field = (TimeShiftConfig.pathField(objectName, h.Field__c)?.prefix ?? '') + fd.getName();
      r.icon = String.isBlank(h.Icon__c) ? 'dot' : h.Icon__c;
      r.colour = String.isBlank(h.Colour__c) ? null : h.Colour__c;
      r.fieldLabel = fd.getLabel();
      out.add(r);
    }
    return out;
  }

  /** The fields the rules read, for the item's query. */
  public static Set<String> fieldsOf(List<Rule> rules) {
    Set<String> out = new Set<String>();
    for (Rule r : rules) {
      out.add(r.field);
    }
    return out;
  }

  /** The icons a row earns; null for none. */
  public static List<TimeShiftController.Flag> flagsFor(List<Rule> rules, TimeShiftRow row) {
    List<TimeShiftController.Flag> out;
    for (Rule r : rules) {
      if (row.get(r.field) != true) {
        continue;
      }
      if (out == null) {
        out = new List<TimeShiftController.Flag>();
      }
      out.add(new TimeShiftController.Flag(r.icon, r.colour, r.fieldLabel));
    }
    return out;
  }
}
