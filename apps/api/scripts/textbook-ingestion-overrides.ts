import type { Medium } from "@prisma/client";

import type { ManualChapterInput } from "../src/modules/ingestion/local-textbook-pipeline";

export interface TextbookIngestionOverride {
  indexPages?: number[];
  manualChapters?: ManualChapterInput[];
  tocScanPages?: number;
  forceCodexToc?: boolean;
  notes?: string[];
}

interface TextbookOverrideLookupRow {
  rowNumber: number;
  subjectCode: string;
  medium: Medium;
  partLabel?: string;
}

const ROW_OVERRIDES: Partial<Record<number, TextbookIngestionOverride>> = {
  2: {
    indexPages: [5],
    manualChapters: [
      {
        chapterNumber: 1,
        title: "Arithmetic Sequences",
        printedStartPage: 7,
      },
      {
        chapterNumber: 2,
        title: "Circles and Angles",
        printedStartPage: 31,
      },
      {
        chapterNumber: 3,
        title: "Arithmetic Sequences and Algebra",
        printedStartPage: 59,
      },
      {
        chapterNumber: 4,
        title: "Mathematics of Chance",
        printedStartPage: 73,
      },
      {
        chapterNumber: 5,
        title: "Second Degree Equations",
        printedStartPage: 85,
      },
      {
        chapterNumber: 6,
        title: "Trigonometry",
        printedStartPage: 97,
      },
      {
        chapterNumber: 7,
        title: "Coordinates",
        printedStartPage: 127,
      },
    ],
    notes: [
      "Manual chapter map pinned from the previously verified Mathematics Part 1 contents structure to prevent over-splitting on the live text layer.",
    ],
  },
  3: {
    indexPages: [12],
    manualChapters: [
      {
        chapterNumber: 1,
        title: "Tangents",
        printedStartPage: 159,
      },
      {
        chapterNumber: 2,
        title: "Solids",
        printedStartPage: 187,
      },
      {
        chapterNumber: 3,
        title: "Geometry and Algebra",
        printedStartPage: 211,
      },
      {
        chapterNumber: 4,
        title: "Polynomials",
        printedStartPage: 233,
      },
      {
        chapterNumber: 5,
        title: "Statistics",
        printedStartPage: 243,
      },
    ],
    notes: [
      "Manual chapter map pinned from the previously verified Mathematics Part 2 contents structure to keep part-two page offsets stable.",
    ],
  },
  21: {
    indexPages: [6],
    manualChapters: [
      {
        chapterNumber: 1,
        title: "لِغَدٍ أَفْضَلَ",
        printedStartPage: 9,
      },
      {
        chapterNumber: 2,
        title: "وَطَنِي عَزِيزٌ",
        printedStartPage: 33,
      },
      {
        chapterNumber: 3,
        title: "إِنَّهَا تَصْنَعُ التَّارِيخَ",
        printedStartPage: 45,
      },
      {
        chapterNumber: 4,
        title: "خُدَّامُ الْأُمَّةِ",
        printedStartPage: 60,
      },
      {
        chapterNumber: 5,
        title: "بَيْنَ الْإِفْرَاطِ وَالتَّفْرِيطِ",
        printedStartPage: 85,
      },
      {
        chapterNumber: 6,
        title: "أُخُوَّةٌ بِلَا حُدُودٍ",
        printedStartPage: 99,
      },
    ],
    notes: [
      "Manual chapter map pinned from the rendered table-of-contents page to avoid partial text-only chapter detection.",
    ],
  },
  22: {
    indexPages: [5],
    manualChapters: [
      {
        chapterNumber: 1,
        title: "العِلْمُ وَالثَّقَافَةُ",
        printedStartPage: 9,
      },
      {
        chapterNumber: 2,
        title: "تَعَالَوْا نَتَكَاتَفْ",
        printedStartPage: 28,
      },
      {
        chapterNumber: 3,
        title: "قُدْوَةٌ حَسَنَةٌ",
        printedStartPage: 48,
      },
      {
        chapterNumber: 4,
        title: "عَجَائِبُ الْكَوْنِ",
        printedStartPage: 60,
      },
    ],
    notes: [
      "Manual chapter map pinned from the rendered table-of-contents page because extracted text is heavily mojibaked.",
    ],
  },
  45: {
    indexPages: [6],
    manualChapters: [
      {
        chapterNumber: 1,
        title: "لِغَدٍ أَفْضَلَ",
        printedStartPage: 9,
      },
      {
        chapterNumber: 2,
        title: "وَطَنِي عَزِيزٌ",
        printedStartPage: 33,
      },
      {
        chapterNumber: 3,
        title: "إِنَّهَا تَصْنَعُ التَّارِيخَ",
        printedStartPage: 45,
      },
      {
        chapterNumber: 4,
        title: "خُدَّامُ الْأُمَّةِ",
        printedStartPage: 60,
      },
      {
        chapterNumber: 5,
        title: "بَيْنَ الْإِفْرَاطِ وَالتَّفْرِيطِ",
        printedStartPage: 85,
      },
      {
        chapterNumber: 6,
        title: "أُخُوَّةٌ بِلَا حُدُودٍ",
        printedStartPage: 99,
      },
    ],
    notes: [
      "Manual chapter map pinned from the rendered table-of-contents page to avoid partial text-only chapter detection.",
    ],
  },
  46: {
    indexPages: [5],
    manualChapters: [
      {
        chapterNumber: 1,
        title: "العِلْمُ وَالثَّقَافَةُ",
        printedStartPage: 9,
      },
      {
        chapterNumber: 2,
        title: "تَعَالَوْا نَتَكَاتَفْ",
        printedStartPage: 28,
      },
      {
        chapterNumber: 3,
        title: "قُدْوَةٌ حَسَنَةٌ",
        printedStartPage: 48,
      },
      {
        chapterNumber: 4,
        title: "عَجَائِبُ الْكَوْنِ",
        printedStartPage: 60,
      },
    ],
    notes: [
      "Manual chapter map pinned from the rendered table-of-contents page because extracted text is heavily mojibaked.",
    ],
  },
  49: {
    indexPages: [4],
    manualChapters: [
      {
        chapterNumber: 1,
        title: "ستائی ہے مغلی سی",
        printedStartPage: 6,
      },
      {
        chapterNumber: 2,
        title: "آپ بیتی",
        printedStartPage: 10,
      },
      {
        chapterNumber: 3,
        title: "کابلی والا",
        printedStartPage: 14,
      },
      {
        chapterNumber: 4,
        title: "غریبوں کا مسیحا",
        printedStartPage: 21,
      },
      {
        chapterNumber: 5,
        title: "کاغذ کی کشتی",
        printedStartPage: 25,
      },
      {
        chapterNumber: 6,
        title: "یاد رہی ہے",
        printedStartPage: 29,
      },
      {
        chapterNumber: 7,
        title: "چھری کے سائے میں",
        printedStartPage: 32,
      },
      {
        chapterNumber: 8,
        title: "مٹی کی سوندھی خوشبو",
        printedStartPage: 38,
      },
      {
        chapterNumber: 9,
        title: "سوا سیر گیہوں",
        printedStartPage: 42,
      },
      {
        chapterNumber: 10,
        title: "مل چلائیں",
        printedStartPage: 50,
      },
      {
        chapterNumber: 11,
        title: "نہ دھوپ سے پریشان",
        printedStartPage: 53,
      },
    ],
    notes: ["Manual chapter map pinned from the rendered Urdu Malayalam Part 1 contents page."],
  },
  50: {
    indexPages: [4],
    manualChapters: [
      {
        chapterNumber: 12,
        title: "ہاتھوں کا ترانہ",
        printedStartPage: 70,
      },
      {
        chapterNumber: 13,
        title: "باب 13",
        printedStartPage: 74,
      },
      {
        chapterNumber: 14,
        title: "انداز ہے یا دانه",
        printedStartPage: 81,
      },
      {
        chapterNumber: 15,
        title: "یکجا کرکے صحبت چکا میں",
        printedStartPage: 88,
      },
      {
        chapterNumber: 16,
        title: "دی چھیل",
        printedStartPage: 91,
      },
      {
        chapterNumber: 17,
        title: "یہ وقت کی آواز ہے",
        printedStartPage: 94,
      },
      {
        chapterNumber: 18,
        title: "دیس کی خاطر",
        printedStartPage: 97,
      },
      {
        chapterNumber: 19,
        title: "آپ کی فرمائش",
        printedStartPage: 100,
      },
      {
        chapterNumber: 20,
        title: "پھول والوں کی سیر",
        printedStartPage: 103,
      },
    ],
    notes: ["Manual chapter map pinned from the rendered Urdu Malayalam Part 2 contents page."],
  },
  27: {
    indexPages: [5],
    manualChapters: [
      {
        chapterNumber: 1,
        title: "സമാന്തരശ്രേണികൾ",
        printedStartPage: 7,
      },
      {
        chapterNumber: 2,
        title: "വൃത്തങ്ങളും കോണുകളും",
        printedStartPage: 31,
      },
      {
        chapterNumber: 3,
        title: "സമാന്തരശ്രേണിയും ബിജഗണിതവും",
        printedStartPage: 59,
      },
      {
        chapterNumber: 4,
        title: "സാധ്യതകളുടെ ഗണിതം",
        printedStartPage: 73,
      },
      {
        chapterNumber: 5,
        title: "രണ്ടാംകൃതി സമവാക്യങ്ങൾ",
        printedStartPage: 85,
      },
      {
        chapterNumber: 6,
        title: "ത്രികോണമിതി",
        printedStartPage: 97,
      },
      {
        chapterNumber: 7,
        title: "സൂചകസംഖ്യകൾ",
        printedStartPage: 127,
      },
    ],
    notes: [
      "Manual chapter map pinned from the rendered Malayalam Mathematics Part 1 contents page.",
    ],
  },
  38: {
    indexPages: [5],
    manualChapters: [
      {
        chapterNumber: 6,
        title: "ആകാശക്കണ്ണുകളും അറിവിന്റെ വിസ്ഫോടനവും",
        printedStartPage: 95,
      },
      {
        chapterNumber: 7,
        title: "വൈവിധ്യങ്ങളുടെ ഇന്ത്യ",
        printedStartPage: 111,
      },
      {
        chapterNumber: 8,
        title: "ഇന്ത്യ - സാമ്പത്തിക ഭൂമിശാസ്ത്രം",
        printedStartPage: 137,
      },
      {
        chapterNumber: 9,
        title: "ധനകാര്യ സ്ഥാപനങ്ങളും സേവനങ്ങളും",
        printedStartPage: 160,
      },
      {
        chapterNumber: 10,
        title: "ഉപഭോക്താവ്: സംതൃപ്തിയും സംരക്ഷണവും",
        printedStartPage: 180,
      },
    ],
    notes: [
      "Manual chapter map pinned from the rendered Malayalam Social Science II Part 2 contents page.",
    ],
  },
  15: {
    indexPages: [5],
    manualChapters: [
      {
        chapterNumber: 1,
        title: "Flights of Fancy",
        printedStartPage: 111,
      },
      {
        chapterNumber: 2,
        title: "Ray of Hope",
        printedStartPage: 142,
      },
    ],
    notes: ["Manual unit map pinned from the rendered English Part 2 contents page to avoid nested lesson overlaps."],
  },
  17: {
    indexPages: [5],
    manualChapters: [
      {
        chapterNumber: 1,
        title: "ഭാഷ പൂത്തും സംസ്കാരം തളിർത്തും",
        printedStartPage: 7,
      },
      {
        chapterNumber: 2,
        title: "ഉള്ളിലാണെപ്പോഴും ഉണ്മതാനെന്നപോൽ",
        printedStartPage: 21,
      },
      {
        chapterNumber: 3,
        title: "വിശ്വലോകവീഥിനത്തിൽ",
        printedStartPage: 35,
      },
      {
        chapterNumber: 4,
        title: "പിന്നെ നാട്ടിൻ ചെറുവഴിയിൽ",
        printedStartPage: 57,
      },
      {
        chapterNumber: 5,
        title: "ഉലകിന്നുയിരാം ഉണർവുകൾ",
        printedStartPage: 71,
      },
    ],
    notes: ["Manual chapter map pinned from the rendered Malayalam (AT) contents page."],
  },
  18: {
    indexPages: [5],
    manualChapters: [
      {
        chapterNumber: 1,
        title: "അരങ്ങും പൊരുളും",
        printedStartPage: 7,
      },
      {
        chapterNumber: 2,
        title: "ഏകോദരസോദരർ നാം",
        printedStartPage: 29,
      },
      {
        chapterNumber: 3,
        title: "അറിവിന്നറിവായ് നിറവായ്",
        printedStartPage: 41,
      },
    ],
    notes: ["Manual chapter map pinned from the rendered Malayalam (BT) contents page."],
  },
  36: {
    indexPages: [5],
    manualChapters: [
      {
        chapterNumber: 1,
        title: "സ്വതന്ത്രനന്തര ഇന്ത്യ",
        printedStartPage: 137,
      },
      {
        chapterNumber: 2,
        title: "കേരളം ആധുനികതയിലേക്ക്",
        printedStartPage: 151,
      },
      {
        chapterNumber: 3,
        title: "രാഷ്ട്രവും രാഷ്ട്രശാസ്ത്രവും",
        printedStartPage: 171,
      },
      {
        chapterNumber: 4,
        title: "പൗരബോധം",
        printedStartPage: 183,
      },
      {
        chapterNumber: 5,
        title: "സമൂഹശാസ്ത്രം: എന്ത്? എന്തിന്?",
        printedStartPage: 193,
      },
    ],
    notes: ["Manual chapter map pinned from the rendered Malayalam Social Science I Part 2 contents page."],
  },
  39: {
    indexPages: [5],
    manualChapters: [
      {
        chapterNumber: 1,
        title: "Glimpses of Green",
        printedStartPage: 7,
      },
      {
        chapterNumber: 2,
        title: "The Frames",
        printedStartPage: 40,
      },
      {
        chapterNumber: 3,
        title: "Lore of Values",
        printedStartPage: 75,
      },
    ],
    notes: ["Manual unit map pinned from the rendered English Part 1 contents page to avoid lesson-level TOC drift."],
  },
  40: {
    indexPages: [5],
    manualChapters: [
      {
        chapterNumber: 1,
        title: "Flights of Fancy",
        printedStartPage: 111,
      },
      {
        chapterNumber: 2,
        title: "Ray of Hope",
        printedStartPage: 142,
      },
    ],
    notes: ["Manual unit map pinned from the rendered English Part 2 contents page to avoid nested lesson overlaps."],
  },
  42: {
    indexPages: [5],
    manualChapters: [
      {
        chapterNumber: 1,
        title: "ഭാഷ പൂത്തും സംസ്കാരം തളിർത്തും",
        printedStartPage: 7,
      },
      {
        chapterNumber: 2,
        title: "ഉള്ളിലാണെപ്പോഴും ഉണ്മതാനെന്നപോൽ",
        printedStartPage: 21,
      },
      {
        chapterNumber: 3,
        title: "വിശ്വലോകവീഥിനത്തിൽ",
        printedStartPage: 35,
      },
      {
        chapterNumber: 4,
        title: "പിന്നെ നാട്ടിൻ ചെറുവഴിയിൽ",
        printedStartPage: 57,
      },
      {
        chapterNumber: 5,
        title: "ഉലകിന്നുയിരാം ഉണർവുകൾ",
        printedStartPage: 71,
      },
    ],
    notes: ["Manual chapter map pinned from the rendered Malayalam (AT) contents page."],
  },
  43: {
    indexPages: [5],
    manualChapters: [
      {
        chapterNumber: 1,
        title: "അരങ്ങും പൊരുളും",
        printedStartPage: 7,
      },
      {
        chapterNumber: 2,
        title: "ഏകോദരസോദരർ നാം",
        printedStartPage: 29,
      },
      {
        chapterNumber: 3,
        title: "അറിവിന്നറിവായ് നിറവായ്",
        printedStartPage: 41,
      },
    ],
    notes: ["Manual chapter map pinned from the rendered Malayalam (BT) contents page."],
  },
};

const SUBJECT_MEDIUM_OVERRIDES: Array<{
  subjectCode: string;
  medium: Medium;
  partLabel?: string;
  override: TextbookIngestionOverride;
}> = [
  {
    subjectCode: "english",
    medium: "en",
    partLabel: "part-1",
    override: {
      indexPages: [5],
      manualChapters: [
        {
          chapterNumber: 1,
          title: "Glimpses of Green",
          printedStartPage: 7,
        },
        {
          chapterNumber: 2,
          title: "The Frames",
          printedStartPage: 40,
        },
        {
          chapterNumber: 3,
          title: "Lore of Values",
          printedStartPage: 75,
        },
      ],
      notes: ["Manual unit map pinned from the rendered English Part 1 contents page to avoid lesson-level TOC drift."],
    },
  },
  {
    subjectCode: "english",
    medium: "ml",
    partLabel: "part-1",
    override: {
      indexPages: [5],
      manualChapters: [
        {
          chapterNumber: 1,
          title: "Glimpses of Green",
          printedStartPage: 7,
        },
        {
          chapterNumber: 2,
          title: "The Frames",
          printedStartPage: 40,
        },
        {
          chapterNumber: 3,
          title: "Lore of Values",
          printedStartPage: 75,
        },
      ],
      notes: ["Manual unit map pinned from the rendered English Part 1 contents page to avoid lesson-level TOC drift."],
    },
  },
  {
    subjectCode: "english",
    medium: "en",
    partLabel: "part-2",
    override: {
      indexPages: [5],
      manualChapters: [
        {
          chapterNumber: 1,
          title: "Flights of Fancy",
          printedStartPage: 111,
        },
        {
          chapterNumber: 2,
          title: "Ray of Hope",
          printedStartPage: 142,
        },
      ],
      notes: ["Manual unit map pinned from the rendered English Part 2 contents page to avoid nested lesson overlaps."],
    },
  },
  {
    subjectCode: "english",
    medium: "ml",
    partLabel: "part-2",
    override: {
      indexPages: [5],
      manualChapters: [
        {
          chapterNumber: 1,
          title: "Flights of Fancy",
          printedStartPage: 111,
        },
        {
          chapterNumber: 2,
          title: "Ray of Hope",
          printedStartPage: 142,
        },
      ],
      notes: ["Manual unit map pinned from the rendered English Part 2 contents page to avoid nested lesson overlaps."],
    },
  },
  {
    subjectCode: "social-science-ii",
    medium: "en",
    partLabel: "part-2",
    override: {
      indexPages: [5],
      manualChapters: [
        {
          chapterNumber: 1,
          title: "Eyes in the Sky and Data Analysis",
          printedStartPage: 95,
        },
        {
          chapterNumber: 2,
          title: "India: The Land of Diversities",
          printedStartPage: 111,
        },
        {
          chapterNumber: 3,
          title: "Resource Wealth of India",
          printedStartPage: 137,
        },
        {
          chapterNumber: 4,
          title: "Financial Institutions and Services",
          printedStartPage: 161,
        },
        {
          chapterNumber: 5,
          title: "Consumer: Satisfaction and Protection",
          printedStartPage: 181,
        },
      ],
      notes: ["Manual chapter map pinned from the rendered English Social Science II Part 2 contents page."],
    },
  },
  {
    subjectCode: "social-science-i",
    medium: "ml",
    partLabel: "part-2",
    override: {
      indexPages: [5],
      manualChapters: [
        {
          chapterNumber: 1,
          title: "സ്വതന്ത്രനന്തര ഇന്ത്യ",
          printedStartPage: 137,
        },
        {
          chapterNumber: 2,
          title: "കേരളം ആധുനികതയിലേക്ക്",
          printedStartPage: 151,
        },
        {
          chapterNumber: 3,
          title: "രാഷ്ട്രവും രാഷ്ട്രശാസ്ത്രവും",
          printedStartPage: 171,
        },
        {
          chapterNumber: 4,
          title: "പൗരബോധം",
          printedStartPage: 183,
        },
        {
          chapterNumber: 5,
          title: "സമൂഹശാസ്ത്രം: എന്ത്? എന്തിന്?",
          printedStartPage: 193,
        },
      ],
      notes: ["Manual chapter map pinned from the rendered Malayalam Social Science I Part 2 contents page."],
    },
  },
  {
    subjectCode: "malayalam-at",
    medium: "en",
    partLabel: "full",
    override: {
      indexPages: [5],
      manualChapters: [
        {
          chapterNumber: 1,
          title: "ഭാഷ പൂത്തും സംസ്കാരം തളിർത്തും",
          printedStartPage: 7,
        },
        {
          chapterNumber: 2,
          title: "ഉള്ളിലാണെപ്പോഴും ഉണ്മതാനെന്നപോൽ",
          printedStartPage: 21,
        },
        {
          chapterNumber: 3,
          title: "വിശ്വലോകവീഥിനത്തിൽ",
          printedStartPage: 35,
        },
        {
          chapterNumber: 4,
          title: "പിന്നെ നാട്ടിൻ ചെറുവഴിയിൽ",
          printedStartPage: 57,
        },
        {
          chapterNumber: 5,
          title: "ഉലകിന്നുയിരാം ഉണർവുകൾ",
          printedStartPage: 71,
        },
      ],
      notes: ["Manual chapter map pinned from the rendered Malayalam (AT) contents page."],
    },
  },
  {
    subjectCode: "malayalam-at",
    medium: "ml",
    partLabel: "full",
    override: {
      indexPages: [5],
      manualChapters: [
        {
          chapterNumber: 1,
          title: "ഭാഷ പൂത്തും സംസ്കാരം തളിർത്തും",
          printedStartPage: 7,
        },
        {
          chapterNumber: 2,
          title: "ഉള്ളിലാണെപ്പോഴും ഉണ്മതാനെന്നപോൽ",
          printedStartPage: 21,
        },
        {
          chapterNumber: 3,
          title: "വിശ്വലോകവീഥിനത്തിൽ",
          printedStartPage: 35,
        },
        {
          chapterNumber: 4,
          title: "പിന്നെ നാട്ടിൻ ചെറുവഴിയിൽ",
          printedStartPage: 57,
        },
        {
          chapterNumber: 5,
          title: "ഉലകിന്നുയിരാം ഉണർവുകൾ",
          printedStartPage: 71,
        },
      ],
      notes: ["Manual chapter map pinned from the rendered Malayalam (AT) contents page."],
    },
  },
  {
    subjectCode: "malayalam-bt",
    medium: "en",
    partLabel: "full",
    override: {
      indexPages: [5],
      manualChapters: [
        {
          chapterNumber: 1,
          title: "അരങ്ങും പൊരുളും",
          printedStartPage: 7,
        },
        {
          chapterNumber: 2,
          title: "ഏകോദരസോദരർ നാം",
          printedStartPage: 29,
        },
        {
          chapterNumber: 3,
          title: "അറിവിന്നറിവായ് നിറവായ്",
          printedStartPage: 41,
        },
      ],
      notes: ["Manual chapter map pinned from the rendered Malayalam (BT) contents page."],
    },
  },
  {
    subjectCode: "malayalam-bt",
    medium: "ml",
    partLabel: "full",
    override: {
      indexPages: [5],
      manualChapters: [
        {
          chapterNumber: 1,
          title: "അരങ്ങും പൊരുളും",
          printedStartPage: 7,
        },
        {
          chapterNumber: 2,
          title: "ഏകോദരസോദരർ നാം",
          printedStartPage: 29,
        },
        {
          chapterNumber: 3,
          title: "അറിവിന്നറിവായ് നിറവായ്",
          printedStartPage: 41,
        },
      ],
      notes: ["Manual chapter map pinned from the rendered Malayalam (BT) contents page."],
    },
  },
  {
    subjectCode: "ict",
    medium: "ml",
    override: {
      indexPages: [5],
      manualChapters: [
        {
          chapterNumber: 1,
          title: "ഡിസൈൻ ഫാക്ടറി",
          printedStartPage: 7,
        },
        {
          chapterNumber: 2,
          title: "പത്രത്താളൊരുക്കാം",
          printedStartPage: 25,
        },
        {
          chapterNumber: 3,
          title: "കമ്പ്യൂട്ടർഭാഷ",
          printedStartPage: 45,
        },
        {
          chapterNumber: 4,
          title: "സൈബർ പ്രപഞ്ചം",
          printedStartPage: 67,
        },
        {
          chapterNumber: 5,
          title: "വെബ്പേജ് സ്റ്റൈലാക്കാം",
          printedStartPage: 85,
        },
        {
          chapterNumber: 6,
          title: "റോബോട്ടുകളുടെ ലോകം",
          printedStartPage: 98,
        },
      ],
      notes: [
        "Manual chapter map pinned from the rendered Malayalam ICT contents page because extracted line breaks split chapter 3.",
      ],
    },
  },
];

export function getTextbookIngestionOverride(row: TextbookOverrideLookupRow): TextbookIngestionOverride | undefined {
  const rowOverride = ROW_OVERRIDES[row.rowNumber];
  if (rowOverride) {
    return rowOverride;
  }

  return SUBJECT_MEDIUM_OVERRIDES.find(
    (candidate) =>
      candidate.subjectCode === row.subjectCode &&
      candidate.medium === row.medium &&
      (candidate.partLabel ?? undefined) === (row.partLabel ?? undefined),
  )?.override;
}
