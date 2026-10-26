/**
 * An example Apex source: rows from somewhere other than a queried object
 * (here, loyalty points worked out from the Contact's orders; in practice an
 * external system or a calculation), plotted by its Time Trail Source
 * record (Loyalty_Points_Example, inactive as shipped).
 *
 * Each row is a map. The record names which keys are the date
 * (Date Field: EarnedAt), the unique key (Id Field: Id), the title and
 * subtitle ("Earned {Points} points", "{Reason}") and the detail fields.
 */
public with sharing class TimeShiftExampleProvider implements TimeShiftRowProvider {
  public List<TimeShiftRow> getRows(TimeShiftContext context) {
    List<TimeShiftRow> rows = new List<TimeShiftRow>();
    Decimal balance = 0;
    List<TimeShiftController.EngagementEvent> orders = new List<TimeShiftController.EngagementEvent>();
    for (TimeShiftController.EngagementEvent e : context.priorEvents) {
      if (e.type == 'purchase') {
        orders.add(e);
      }
    }
    // Oldest first, so the balance builds up.
    for (Integer i = orders.size() - 1; i >= 0; i--) {
      TimeShiftController.EngagementEvent order = orders[i];
      // A flat 100 points an order.
      Decimal points = 100;
      balance += points;
      rows.add(
        new TimeShiftRow(
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
