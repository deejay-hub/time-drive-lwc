/**
 * Data 360's own list of its data model objects (DMOs), from its query
 * API's metadata. Apex's global describe doesn't list DMOs in every org,
 * though each can be described and queried by name, so Time Drive Setup asks
 * Data 360 which there are. Only orgs with Data 360 can compile it, so it's
 * in force-app-data360 and Setup finds it by name.
 */
// Namespace accessible: the core package makes one by name (Type.forName) and asks it through Catalog.
@NamespaceAccessible
public with sharing class TimeDriveData360Catalog implements TimeDriveData360Provider.Catalog {
  // An item's own name (fields end __c, so only the object's ends __dlm).
  private static final Pattern DMO_NAME = Pattern.compile('\\bname=([A-Za-z0-9_]+__dlm)\\b');
  // An item's category: Profile, Engagement or Related (fields have none).
  private static final Pattern CATEGORY = Pattern.compile('\\bcategory=([A-Za-z]+)');
  // The metadata per data space, asked for once a request (a test fills it in,
  // since Data 360's query API can't run in a test).
  @TestVisible
  private static Map<String, List<Object>> metadataBySpace = new Map<String, List<Object>>();

  /** Makes the catalog; the core package does, by name. */
  @NamespaceAccessible
  public TimeDriveData360Catalog() {
    // Nothing to set up.
    return;
  }

  /**
   * A data space's DMOs (blank: the default one).
   *
   * @param dataSpace the data space, blank for the default one
   * @return the DMO API names
   */
  @NamespaceAccessible
  public List<String> dmoNames(String dataSpace) {
    return namesIn(metadata(dataSpace));
  }

  /**
   * A data space's Profile DMOs (blank: the default one): those describing
   * who someone is (Individual, Party, Account) rather than what they did.
   *
   * @param dataSpace the data space, blank for the default one
   * @return the API names of its Profile DMOs
   */
  @NamespaceAccessible
  public Set<String> profileDmoNames(String dataSpace) {
    return profileNamesIn(metadata(dataSpace));
  }

  private static List<Object> metadata(String dataSpace) {
    String space = String.isBlank(dataSpace) ? 'default' : dataSpace;
    if (!metadataBySpace.containsKey(space)) {
      ConnectApi.CdpQueryMetadataOutput meta = ConnectApi.CdpQuery.getAllMetadata('DataModelObject', null, null, space);
      metadataBySpace.put(space, meta.metadata);
    }
    return metadataBySpace.get(space);
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

  @TestVisible
  private static Set<String> profileNamesIn(List<Object> items) {
    Set<String> out = new Set<String>();
    for (Object item : items == null ? new List<Object>() : items) {
      String text = String.valueOf(item);
      Matcher name = DMO_NAME.matcher(text);
      Matcher category = CATEGORY.matcher(text);
      if (name.find() && category.find() && category.group(1) == 'Profile') {
        out.add(name.group(1));
      }
    }
    return out;
  }
}
