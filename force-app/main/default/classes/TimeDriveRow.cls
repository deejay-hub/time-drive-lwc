/**
 * One row a provider hands back for plotting: a queried record (Salesforce or
 * Data 360) or a map of values (an Apex provider). Its Time Drive Source
 * record says which values are the date, title and details, so every
 * kind of source is plotted the same way.
 */
// The branching follows the platform's cases and the plot's rules; splitting it up would only scatter them.
@SuppressWarnings('PMD.CyclomaticComplexity, PMD.CognitiveComplexity')
public with sharing class TimeDriveRow {
  private SObject record;
  // An object's fields by lower-case name, and the labels worked out for its
  // paths, kept for the request: describing an object builds its whole field
  // map, and a page of rows would otherwise do it for every row.
  private static Map<Schema.SObjectType, Map<String, Schema.SObjectField>> fieldMaps = new Map<Schema.SObjectType, Map<String, Schema.SObjectField>>();
  private static Map<String, String> labels = new Map<String, String>();

  // Lower-case keys, so templates and detail fields match any case.
  private Map<String, Object> values = new Map<String, Object>();

  private static Map<String, Schema.SObjectField> fieldsOf(Schema.SObjectType type) {
    Map<String, Schema.SObjectField> found = fieldMaps.get(type);
    if (found == null) {
      found = TimeDriveConfig.fieldMap(TimeDriveConfig.describeType(type).getName());
      fieldMaps.put(type, found);
    }
    return found;
  }

  /**
   * A row over a record.
   *
   * @param record the record
   */
  public TimeDriveRow(SObject record) {
    this.record = record;
  }

  /**
   * A row over a map of values.
   *
   * @param values the values by name
   */
  public TimeDriveRow(Map<String, Object> values) {
    if (values != null) {
      for (String key : values.keySet()) {
        put(key, values.get(key));
      }
    }
  }

  /**
   * Adds or overrides a value.
   *
   * @param key the value's name
   * @param value the value
   * @return this row
   */
  public TimeDriveRow put(String key, Object value) {
    values.put(key.toLowerCase(), value);
    return this;
  }

  /**
   * A value by name or path, following relationships on records:
   * Account.Owner.Name.
   *
   * @param path a field name or relationship path
   * @return the value, or null
   */
  public Object get(String path) {
    if (String.isBlank(path)) {
      return null;
    }
    String key = path.toLowerCase();
    if (values.containsKey(key) || record == null) {
      return values.get(key);
    }
    List<String> steps = path.split('\\.');
    SObject current = record;
    for (Integer i = 0; i < steps.size() - 1; i++) {
      current = current?.getSObject(steps[i]);
    }
    return current?.get(steps[steps.size() - 1]);
  }

  /**
   * A field's label in the user's language, for a detail with no label of
   * its own: the field's, or for a path through a lookup the lookup's
   * ("Who.Name" reads "Name", "What.Name" "Related To") when it ends at Name,
   * else the last field's. Never prefixed with an object's name.
   *
   * @param path a field name or relationship path
   * @return the label
   */
  public String labelOf(String path) {
    if (record == null || String.isBlank(path)) {
      return path;
    }
    String cacheKey = String.valueOf(record.getSObjectType()) + '|' + path;
    String cached = labels.get(cacheKey);
    if (cached == null) {
      cached = worksOutLabel(path);
      labels.put(cacheKey, cached);
    }
    return cached;
  }

  private String worksOutLabel(String path) {
    Schema.DescribeFieldResult own = describe(path);
    if (own != null) {
      return plainLabel(own);
    }
    if (record == null || String.isBlank(path) || !path.contains('.')) {
      return path;
    }
    List<String> steps = path.split('\\.');
    Schema.SObjectType type = record.getSObjectType();
    Schema.DescribeFieldResult lookup;
    for (Integer i = 0; i < steps.size() - 1; i++) {
      lookup = null;
      for (Schema.SObjectField f : fieldsOf(type).values()) {
        Schema.DescribeFieldResult d = f.getDescribe();
        if (d.getRelationshipName() != null && d.getRelationshipName().equalsIgnoreCase(steps[i])) {
          lookup = d;
          break;
        }
      }
      if (lookup == null) {
        return path;
      }
      if (i < steps.size() - 2) {
        if (lookup.getReferenceTo().size() != 1) {
          return path;
        }
        type = lookup.getReferenceTo()[0];
      }
    }
    String last = steps[steps.size() - 1];
    if (last.equalsIgnoreCase('Name') || lookup.getReferenceTo().size() != 1) {
      return plainLabel(lookup);
    }
    Schema.SObjectField target = fieldsOf(lookup.getReferenceTo()[0]).get(last.toLowerCase());
    return target == null ? plainLabel(lookup) : plainLabel(target.getDescribe());
  }

  /**
   * A field's label as the page shows it. Apex's describe ends a lookup's
   * label with " ID" ("Related To ID", "Account ID"), which the page leaves
   * off; so does Setup. Only a lookup's: a text field called "Account ID"
   * is left as it is.
   *
   * @param field the field
   * @return the field's label without a trailing ID
   */
  @TestVisible
  private static String plainLabel(Schema.DescribeFieldResult field) {
    String label = field.getLabel();
    return field.getType() == Schema.DisplayType.REFERENCE &&
      label.endsWith(' ID') &&
      label.length() > 3
      ? label.removeEnd(' ID')
      : label;
  }

  /**
   * The row's field, when it's a record and the path is one of its own
   * fields; used to format currency and default detail labels.
   *
   * @param path a field name
   * @return the field's describe result, or null
   */
  public Schema.DescribeFieldResult describe(String path) {
    if (record == null || String.isBlank(path)) {
      return null;
    }
    // A path through lookups (Opportunity.StageName) is described where it lives.
    if (path.contains('.')) {
      return TimeDriveConfig.fieldDescribe(String.valueOf(record.getSObjectType()), path);
    }
    Schema.SObjectField field = fieldsOf(record.getSObjectType()).get(path.toLowerCase());
    return field?.getDescribe();
  }
}
