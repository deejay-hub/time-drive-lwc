/**
 * A source of timeline events. Every provider, the generic SOQL one and
 * Apex ones such as Data 360, implements this one method and
 * returns the same event shape, so a new source is a Time Trail Source
 * record (SOQL) or a small class named in one (Apex).
 *
 * Add a message to context.warnings rather than throw when data can't be
 * read, so one missing source never empties the timeline.
 */
public interface TimeShiftProvider {
  List<TimeShiftController.EngagementEvent> getEvents(TimeShiftContext context);
}
