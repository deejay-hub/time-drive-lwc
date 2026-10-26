/**
 * Data 360's own list of its data model objects (DMOs), from its query
 * API's metadata. Apex's global describe doesn't list DMOs in every org,
 * though each can be described and queried by name, so Time Trail Setup asks
 * Data 360 which there are. Only orgs with Data 360 can compile it, so it's
 * in force-app-data360 and Setup finds it by name.
 */
public with sharing class TimeShiftData360Catalog implements TimeShiftData360Provider.Catalog {
  // An item's own name (fields end __c, so only the object's ends __dlm).
  private static final Pattern DMO_NAME = Pattern.compile('\\bname=([A-Za-z0-9_]+__dlm)\\b');

  // A data space's DMOs (blank: the default one).
  public List<String> dmoNames(String dataSpace) {
    ConnectApi.CdpQueryMetadataOutput meta = ConnectApi.CdpQuery.getAllMetadata(
      'DataModelObject',
      null,
      null,
      String.isBlank(dataSpace) ? 'default' : dataSpace
    );
    return namesIn(meta.metadata);
  }

  // The items come back as untyped objects; their text holds the name.
  @TestVisible
  private static List<String> namesIn(List<Object> items) {
    Set<String> out = new Set<String>();
    for (Object item : items == null ? new List<Object>() : items) {
      Matcher m = DMO_NAME.matcher(String.valueOf(item));
      if (m.find()) {
        out.add(m.group(1));
      }
    }
    return new List<String>(out);
  }
}
