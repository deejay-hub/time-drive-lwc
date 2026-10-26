// Questions for the home page's FAQs, kept here so Home never waits on
// the network. The Docs' FAQs come from the docs repo on GitHub.

export const FAQS = [
  [
    "Who can use Time Trail Setup?",
    "Admins with the Customize Application permission. Everyone else sees the timeline on record pages, but can't change its sources."
  ],
  ["Which record pages can show a timeline?", "Contact record pages today. Other record pages are planned."],
  [
    "What can a source show?",
    "Records from a standard or custom object, engagement from a Data 360 data model object, or items an Apex class returns."
  ],
  [
    "Will people see records they can't access?",
    "No. Every query runs as the person looking. A source they can't read is left off their timeline and named, and the rest still loads."
  ],
  [
    "How many records can a timeline handle?",
    "Years of history. The timeline counts first and reads details only for the days on screen; a busy day shows one row per type."
  ],
  [
    "Why does saving take a few seconds?",
    "Sources are stored as custom metadata, so saving deploys it. Setup tells you when the deployment finishes."
  ],
  [
    "Can I make a source inactive without deleting it?",
    "Yes. Make it inactive with the Active switch on its record page. Removing takes it off the list; delete it for good in Custom Metadata Types."
  ],
  [
    "What does Most records do?",
    "For sources read item by item (Apex, and any source while someone searches), the newest this many are plotted."
  ],
  [
    "How far back does the timeline look?",
    "As far as the History and Future set on the record page in App Builder, from 3 months to 10 years. A source can look back less."
  ],
  [
    "What if Data 360 isn't set up yet?",
    "Data 360 sources show a note instead of items and everything else still loads.."
  ]
];
