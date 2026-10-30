/**
 * Enhanced Email's messages on the timeline: whether each was opened, is
 * unopened or bounced (for the icon after its title), and its subtitle,
 * which is always the timeline's own, not the source's: who it went to
 * ("Sent to: Sam Lee and 1 other"). One query for
 * the messages and one for their recipients, in user mode; if they can't be
 * read, the items stay as they are.
 */
// The branching follows the platform's cases and the plot's rules; splitting it up would only scatter them.
@SuppressWarnings('PMD.CyclomaticComplexity, PMD.CognitiveComplexity')
public with sharing class TimeDriveEmails {
  public static final String OPENED = 'opened';
  public static final String UNOPENED = 'unopened';
  public static final String BOUNCED = 'bounced';

  /**
   * Adds the opened state and recipients subtitle to the events that are Enhanced Email messages.
   *
   * @param events the events to enrich
   */
  public static void enrich(List<TimeDriveController.EngagementEvent> events) {
    Set<Id> ids = new Set<Id>();
    for (TimeDriveController.EngagementEvent e : events) {
      if (e.recordId != null && e.recordId.getSObjectType() == EmailMessage.SObjectType && e.grouped != true) {
        ids.add(e.recordId);
      }
    }
    if (ids.isEmpty()) {
      return;
    }
    try {
      Map<Id, EmailMessage> messages = new Map<Id, EmailMessage>(
        [
          SELECT Id, Incoming, IsTracked, IsOpened, IsBounced, LastOpenedDate, ToAddress, CcAddress
          FROM EmailMessage
          WHERE Id IN :ids
          WITH USER_MODE
        ]
      );
      // Recipients' names by message and address, where Salesforce knows them.
      Map<String, String> names = new Map<String, String>();
      for (EmailMessageRelation r : [
        SELECT EmailMessageId, Relation.Name, RelationAddress
        FROM EmailMessageRelation
        WHERE EmailMessageId IN :ids AND RelationType IN ('ToAddress', 'CcAddress')
        WITH USER_MODE
      ]) {
        if (String.isNotBlank(r.RelationAddress) && String.isNotBlank(r.Relation?.Name)) {
          names.put(r.EmailMessageId + '|' + r.RelationAddress.toLowerCase(), r.Relation.Name);
        }
      }
      for (TimeDriveController.EngagementEvent e : events) {
        EmailMessage m = e.recordId == null ? null : messages.get(e.recordId);
        if (m == null) {
          continue;
        }
        e.emailState = stateOf(m);
        e.emailOpenedAt = m.LastOpenedDate;
        e.subtitle = sentTo(m, names);
      }
    } catch (Exception e) {
      // Email fields this user can't read: the items show without them.
      System.debug(LoggingLevel.WARN, 'Time Drive: email details unavailable. ' + e.getMessage());
    }
  }

  // Bounced first; then opened, or unopened for a tracked message sent from
  // Salesforce. Received or untracked messages can't say, so they have none.
  @TestVisible
  private static String stateOf(EmailMessage m) {
    if (m.IsBounced == true) {
      return BOUNCED;
    }
    if (m.IsOpened == true || m.LastOpenedDate != null) {
      return OPENED;
    }
    return m.Incoming != true && m.IsTracked == true ? UNOPENED : null;
  }

  // "Sent to: Sam Lee and 2 others": the first To recipient Salesforce
  // knows, by name (else the first address), and how many others it went
  // to, To and CC.
  @TestVisible
  private static String sentTo(EmailMessage m, Map<String, String> names) {
    List<String> to = addresses(m.ToAddress);
    if (to.isEmpty()) {
      return null;
    }
    Integer others = to.size() - 1 + addresses(m.CcAddress).size();
    String primary;
    for (String address : to) {
      primary = names.get(m.Id + '|' + address.toLowerCase());
      if (String.isNotBlank(primary)) {
        break;
      }
    }
    String who = String.isBlank(primary) ? to[0] : primary;
    if (others == 0) {
      return String.format(Label.Time_Drive_Server_Sent_To, new List<String>{ who });
    }
    return others == 1
      ? String.format(Label.Time_Drive_Server_Sent_To_One_Other, new List<String>{ who })
      : String.format(Label.Time_Drive_Server_Sent_To_Others, new List<String>{ who, String.valueOf(others) });
  }

  private static List<String> addresses(String field) {
    List<String> out = new List<String>();
    if (String.isBlank(field)) {
      return out;
    }
    for (String part : field.split('[;,]')) {
      if (String.isNotBlank(part)) {
        out.add(part.trim());
      }
    }
    return out;
  }
}
