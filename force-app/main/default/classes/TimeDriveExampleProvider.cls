/**
 * An example Apex source: rows from somewhere other than a queried object
 * (here, loyalty points worked out from the Contact's orders; in practice an
 * external system or a calculation), plotted by its Time Drive Source
 * record (Loyalty_Points_Example, inactive as shipped).
 *
 * Each row is a map. The record names which keys are the date
 * (Date Field: EarnedAt), the unique key (Id Field: Id), the title and
 * subtitle ("Earned {Points} points", "{Reason}") and the detail fields.
 */
public with sharing class TimeDriveExampleProvider implements TimeDriveRowProvider {
  /**
   * Builds the example rows.
   *
   * @param context the request context
   * @return the example rows
   */
  public List<TimeDriveRow> getRows(TimeDriveContext context) {
    List<TimeDriveRow> rows = new List<TimeDriveRow>();
    Decimal balance = 0;
    List<TimeDriveController.EngagementEvent> orders = new List<TimeDriveController.EngagementEvent>();
    for (TimeDriveController.EngagementEvent e : context.priorEvents) {
      if (e.type == 'purchase') {
        orders.add(e);
      }
    }
    // Oldest first, so the balance builds up.
    for (Integer i = orders.size() - 1; i >= 0; i--) {
      TimeDriveController.EngagementEvent order = orders[i];
      // A flat 100 points an order.
      Decimal points = 100;
      balance += points;
      rows.add(
        new TimeDriveRow(
          new Map<String, Object>{
            'Id' => 'loyalty-' + order.id,
            'EarnedAt' => order.occurredAt.addMinutes(1),
            'Points' => points,
            'Balance' => balance,
            'Reason' => order.title,
            'OrderId' => order.recordId
          }
        )
      );
      if (rows.size() >= context.maxRecords()) {
        break;
      }
    }
    return rows;
  }
}
